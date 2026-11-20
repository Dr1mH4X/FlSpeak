//! Actor 与 `tsclient_rs::stream::Streams` 的桥接层。
//!
//! 连接期由单个 [`ActiveStreamSession`] 持有 `Streams`、当前观看句柄与本地推流句柄；
//! `Streams` 以全服维度缓存流信息，Actor 只负责按当前所在频道投影 `SessionView.streams`
//! 并将推拉流指令与信令经异步任务转发给 UI。

use std::cell::RefCell;
use std::collections::HashMap;
use std::future::Future;
use std::rc::Rc;

use tokio::sync::watch;
use tokio::task::JoinHandle;
use tsclient_rs::AbortSignal;
use tsclient_rs::stream::{
    IceCandidate, JoinRequest, JoinRequestCloseCause, JoinRequestEvent, JoinRequestState,
    PeerEvent, PublishedStream, PublishedStreamEvent, StreamError, StreamInfo, StreamSubscription,
    StreamTransport, StreamView as TsStreamView, Streams, StreamsEvent, StreamsOptions, ViewerPeer,
    WatchOptions,
};

use super::*;
use crate::streams::{
    PublisherSignal, StreamEndReason, ice_candidate, peer_close_reason, project_channel_streams,
    publish_options, stream_error, watch_error_reason,
};

struct PumpGuard(JoinHandle<()>);

impl Drop for PumpGuard {
    fn drop(&mut self) {
        self.0.abort();
    }
}

enum EventStream<E> {
    Live(StreamSubscription<E>),
    #[cfg(test)]
    Test(mpsc::UnboundedReceiver<E>),
}

impl<E> EventStream<E> {
    async fn recv(&mut self) -> Option<E> {
        match self {
            Self::Live(sub) => sub.recv().await,
            #[cfg(test)]
            Self::Test(rx) => rx.recv().await,
        }
    }
}

#[derive(Clone, Debug)]
enum PublishedStreamHandle {
    Live(PublishedStream),
    #[cfg(test)]
    Test {
        id: String,
    },
}

impl PublishedStreamHandle {
    fn id(&self) -> &str {
        match self {
            Self::Live(stream) => stream.id(),
            #[cfg(test)]
            Self::Test { id } => id,
        }
    }

    async fn stop(&self, reason: u32) -> Result<(), StreamError> {
        match self {
            Self::Live(stream) => stream.stop(reason).await,
            #[cfg(test)]
            Self::Test { .. } => Ok(()),
        }
    }
}

#[cfg(test)]
#[derive(Clone, Debug)]
pub(crate) struct TestViewerPeer {
    stream_id: String,
    closed: Arc<std::sync::atomic::AtomicBool>,
    events_rx: Arc<std::sync::Mutex<Option<mpsc::UnboundedReceiver<PeerEvent>>>>,
    sent_candidates: Arc<std::sync::Mutex<Vec<IceCandidate>>>,
    send_candidate_error: Arc<std::sync::Mutex<Option<StreamError>>>,
}

#[derive(Clone, Debug)]
pub(crate) enum ViewerPeerHandle {
    Live(ViewerPeer),
    #[cfg(test)]
    Test(TestViewerPeer),
}

impl ViewerPeerHandle {
    fn stream_id(&self) -> &str {
        match self {
            Self::Live(peer) => peer.stream_id(),
            #[cfg(test)]
            Self::Test(peer) => &peer.stream_id,
        }
    }

    fn closed(&self) -> bool {
        match self {
            Self::Live(peer) => peer.closed(),
            #[cfg(test)]
            Self::Test(peer) => peer.closed.load(std::sync::atomic::Ordering::Acquire),
        }
    }

    fn subscribe(&self) -> EventStream<PeerEvent> {
        match self {
            Self::Live(peer) => EventStream::Live(peer.subscribe()),
            #[cfg(test)]
            Self::Test(peer) => EventStream::Test(
                peer.events_rx
                    .lock()
                    .unwrap()
                    .take()
                    .expect("test peer already subscribed"),
            ),
        }
    }

    async fn send_candidate(&self, candidate: &IceCandidate) -> Result<(), StreamError> {
        match self {
            Self::Live(peer) => peer.send_candidate(candidate).await,
            #[cfg(test)]
            Self::Test(peer) => {
                if let Some(err) = peer.send_candidate_error.lock().unwrap().as_ref() {
                    return Err(err.clone());
                }
                peer.sent_candidates.lock().unwrap().push(candidate.clone());
                Ok(())
            }
        }
    }

    async fn close(&self) -> Result<(), StreamError> {
        match self {
            Self::Live(peer) => peer.close().await,
            #[cfg(test)]
            Self::Test(peer) => {
                peer.closed
                    .store(true, std::sync::atomic::Ordering::Release);
                Ok(())
            }
        }
    }

    async fn kick(&self, reason: u16) -> Result<(), StreamError> {
        match self {
            Self::Live(peer) => peer.kick(reason).await,
            #[cfg(test)]
            Self::Test(peer) => {
                peer.closed
                    .store(true, std::sync::atomic::Ordering::Release);
                Ok(())
            }
        }
    }
}

#[cfg(test)]
#[derive(Clone, Debug)]
struct TestJoinRequest {
    viewer_clid: i32,
    state: Arc<std::sync::Mutex<JoinRequestState>>,
    events_rx: Arc<std::sync::Mutex<Option<mpsc::UnboundedReceiver<JoinRequestEvent>>>>,
    accept_result: Arc<std::sync::Mutex<Option<Result<TestViewerPeer, StreamError>>>>,
    deny_result: Arc<std::sync::Mutex<Option<Result<(), StreamError>>>>,
    offers_seen: Arc<std::sync::Mutex<Vec<String>>>,
}

#[derive(Clone, Debug)]
enum JoinRequestHandle {
    Live(JoinRequest),
    #[cfg(test)]
    Test(TestJoinRequest),
}

impl JoinRequestHandle {
    fn viewer_client_id(&self) -> i32 {
        match self {
            Self::Live(req) => req.viewer().client_id,
            #[cfg(test)]
            Self::Test(req) => req.viewer_clid,
        }
    }

    fn state(&self) -> JoinRequestState {
        match self {
            Self::Live(req) => req.state(),
            #[cfg(test)]
            Self::Test(req) => *req.state.lock().unwrap(),
        }
    }

    fn subscribe(&self) -> EventStream<JoinRequestEvent> {
        match self {
            Self::Live(req) => EventStream::Live(req.subscribe()),
            #[cfg(test)]
            Self::Test(req) => EventStream::Test(
                req.events_rx
                    .lock()
                    .unwrap()
                    .take()
                    .expect("test request already subscribed"),
            ),
        }
    }

    async fn accept(&self, offer: &str, message: &str) -> Result<ViewerPeerHandle, StreamError> {
        match self {
            Self::Live(req) => req.accept(offer, message).await.map(ViewerPeerHandle::Live),
            #[cfg(test)]
            Self::Test(req) => {
                req.offers_seen.lock().unwrap().push(offer.to_string());
                let res = req
                    .accept_result
                    .lock()
                    .unwrap()
                    .take()
                    .expect("missing test accept_result");
                match res {
                    Ok(peer) => {
                        *req.state.lock().unwrap() = JoinRequestState::Accepted;
                        Ok(ViewerPeerHandle::Test(peer))
                    }
                    Err(err) => {
                        *req.state.lock().unwrap() = JoinRequestState::Failed;
                        Err(err)
                    }
                }
            }
        }
    }

    async fn deny(&self, reason: &str) -> Result<(), StreamError> {
        match self {
            Self::Live(req) => req.deny(reason).await,
            #[cfg(test)]
            Self::Test(req) => {
                let res = req.deny_result.lock().unwrap().take().unwrap_or(Ok(()));
                if res.is_ok() {
                    *req.state.lock().unwrap() = JoinRequestState::Denied;
                }
                res
            }
        }
    }
}

fn candidate_summary(cand: &IceCandidate) -> String {
    let mid = cand.sdp_mid.as_deref().unwrap_or("-");
    let m_line = cand
        .sdp_m_line_index
        .map_or_else(|| "-".to_string(), |idx| idx.to_string());
    format!("mid={mid}, m_line={m_line}")
}

struct ActiveWatch {
    id: u64,
    stream_id: String,
    source_clid: i32,
    phase: WatchPhase,
}

enum WatchPhase {
    Joining {
        abort: AbortSignal,
        done: watch::Receiver<bool>,
        settled_view: Rc<RefCell<Option<TsStreamView>>>,
    },
    Active {
        view: TsStreamView,
        _task: PumpGuard,
    },
}

struct StartingPublish {
    token: u64,
    abort: AbortSignal,
}

struct PendingViewerRequest {
    token: u64,
    request: JoinRequestHandle,
    responding: bool,
    _task: PumpGuard,
}

struct AcceptedViewer {
    token: u64,
    peer: ViewerPeerHandle,
    _task: PumpGuard,
}

struct ActivePublish {
    stream: PublishedStreamHandle,
    requests: HashMap<i32, PendingViewerRequest>,
    viewers: HashMap<i32, AcceptedViewer>,
    _task: PumpGuard,
}

#[cfg(test)]
type TestWatchHook = Rc<
    dyn Fn(String, AbortSignal) -> Pin<Box<dyn Future<Output = Result<TsStreamView, StreamError>>>>,
>;

/// 单次连接生命周期内的屏幕共享会话状态。
pub(super) struct ActiveStreamSession {
    streams: Streams,
    watch: Option<ActiveWatch>,
    starting_publish: Option<StartingPublish>,
    publish: Option<ActivePublish>,
    pending_watch_cleanups: HashMap<String, watch::Receiver<bool>>,
    unsupported_logged: bool,
    _bus_task: PumpGuard,
    #[cfg(test)]
    test_infos: std::collections::BTreeMap<String, StreamInfo>,
    #[cfg(test)]
    test_refreshed_clids: RefCell<Vec<u16>>,
    #[cfg(test)]
    test_watch_hook: Option<TestWatchHook>,
}

impl ActiveStreamSession {
    fn infos(&self) -> Vec<StreamInfo> {
        #[cfg(not(test))]
        {
            self.streams.list()
        }
        #[cfg(test)]
        {
            let mut merged: std::collections::BTreeMap<String, StreamInfo> = self
                .streams
                .list()
                .into_iter()
                .map(|info| (info.id.clone(), info))
                .collect();
            for (id, info) in &self.test_infos {
                merged.entry(id.clone()).or_insert_with(|| info.clone());
            }
            merged.into_values().collect()
        }
    }

    fn get_info(&self, id: &str) -> Option<StreamInfo> {
        #[cfg(not(test))]
        {
            self.streams.get(id)
        }
        #[cfg(test)]
        {
            self.streams
                .get(id)
                .or_else(|| self.test_infos.get(id).cloned())
        }
    }

    fn refresh_client(&self, clid: u16) {
        #[cfg(test)]
        self.test_refreshed_clids.borrow_mut().push(clid);
        self.streams.refresh_client(clid);
    }

    fn record_watch_cleanup(&mut self, stream_id: &str, rx: watch::Receiver<bool>) {
        self.pending_watch_cleanups
            .retain(|_, done| !*done.borrow());
        self.pending_watch_cleanups
            .insert(stream_id.to_string(), rx);
    }
}

fn spawn_best_effort_leave_notifying(
    view: TsStreamView,
    events: broadcast::Sender<SessionEvent>,
) -> watch::Receiver<bool> {
    let (closed_tx, closed_rx) = watch::channel(false);
    tokio::task::spawn_local(async move {
        let stream_id = view.stream_id().to_string();
        let mut fut = std::pin::pin!(view.leave());
        // 先推进到首个 await（完成本地 on_closed 并从 Streams::watching 移除），再放行后续重看。
        let first_res = std::future::poll_fn(|cx| match fut.as_mut().poll(cx) {
            std::task::Poll::Ready(res) => std::task::Poll::Ready(Some(res)),
            std::task::Poll::Pending => std::task::Poll::Ready(None),
        })
        .await;
        let _ = closed_tx.send(true);
        let res = match first_res {
            Some(res) => res,
            None => fut.await,
        };
        if let Err(err) = res
            && !err.is_not_connected()
        {
            emit(
                &events,
                SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("退出屏幕共享 {stream_id} 失败: {err}"),
                },
            );
        }
    });
    closed_rx
}

fn spawn_best_effort_stop(stream: PublishedStreamHandle, events: broadcast::Sender<SessionEvent>) {
    tokio::task::spawn_local(async move {
        if let Err(err) = stream.stop(0).await
            && !err.is_not_connected()
        {
            emit(
                &events,
                SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("停止屏幕共享 {} 失败: {err}", stream.id()),
                },
            );
        }
    });
}

fn cancel_joining_watch(
    abort: AbortSignal,
    done: watch::Receiver<bool>,
    settled_view: Rc<RefCell<Option<TsStreamView>>>,
    events: broadcast::Sender<SessionEvent>,
) -> watch::Receiver<bool> {
    abort.abort();
    if let Some(view) = settled_view.borrow_mut().take() {
        return spawn_best_effort_leave_notifying(view, events);
    }
    done
}

impl Actor {
    fn next_stream_token(&mut self) -> u64 {
        self.next_stream_token = self.next_stream_token.wrapping_add(1);
        if self.next_stream_token == 0 {
            self.next_stream_token = 1;
        }
        self.next_stream_token
    }

    /// 为新建立的 `Client` 挂接 `tsclient_rs::stream::Streams` 并开始转发流事件。
    pub(super) fn init_stream_session(&mut self, client: &Client) {
        self.stream_epoch = self.stream_epoch.wrapping_add(1);
        let streams = Streams::new(
            client,
            StreamsOptions {
                remember_denied: false,
            },
        );
        let mut sub = streams.subscribe();
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let bus_task = tokio::task::spawn_local(async move {
            while let Some(event) = sub.recv().await {
                if signals
                    .send(SessionSignal::StreamsBusEvent { epoch, event })
                    .is_err()
                {
                    break;
                }
            }
        });
        self.stream_session = Some(ActiveStreamSession {
            streams,
            watch: None,
            starting_publish: None,
            publish: None,
            pending_watch_cleanups: HashMap::new(),
            unsupported_logged: false,
            _bus_task: PumpGuard(bus_task),
            #[cfg(test)]
            test_infos: std::collections::BTreeMap::new(),
            #[cfg(test)]
            test_refreshed_clids: RefCell::new(Vec::new()),
            #[cfg(test)]
            test_watch_hook: None,
        });
        self.sync_streams_view();
    }

    /// 断线或重连前回收全部屏幕共享会话并清理缓存的成员频道。
    pub(super) fn reset_streams(&mut self, reason: StreamEndReason) {
        self.stream_epoch = self.stream_epoch.wrapping_add(1);
        self.client_channels.clear();
        if let Some(mut session) = self.stream_session.take() {
            if let Some(watch) = session.watch.take() {
                if let WatchPhase::Joining {
                    abort,
                    done,
                    settled_view,
                } = watch.phase
                {
                    let _ = cancel_joining_watch(abort, done, settled_view, self.events.clone());
                }
                self.emit(SessionEvent::StreamEnded {
                    stream_id: watch.stream_id,
                    reason,
                });
            }
            if let Some(starting) = session.starting_publish.take() {
                starting.abort.abort();
            }
            if session.publish.take().is_some() {
                self.emit(SessionEvent::ScreenShareStopped);
            }
            session.streams.dispose();
        }
        self.sync_streams_view();
    }

    pub(super) fn record_client_channel(&mut self, clid: i32, channel_id: u64) {
        if channel_id != 0 {
            self.client_channels.insert(clid, channel_id);
        } else {
            self.client_channels.remove(&clid);
        }
    }

    pub(super) fn remove_client_channel(&mut self, clid: i32) {
        self.client_channels.remove(&clid);
    }

    pub(super) fn sync_client_channels_from_snapshot(&mut self, clients: &[ClientView]) {
        self.client_channels.clear();
        for client in clients {
            if client.channel_id != 0 {
                self.client_channels.insert(client.id, client.channel_id);
            }
        }
    }

    fn client_channel(&self, clid: i32) -> Option<u64> {
        if Some(clid) == self.self_client_id {
            return (self.self_channel_id != 0).then_some(self.self_channel_id);
        }
        self.client_channels
            .get(&clid)
            .copied()
            .filter(|channel| *channel != 0)
            .or_else(|| {
                self.client
                    .as_ref()
                    .and_then(|client| client.directory_snapshot())
                    .and_then(|snapshot| snapshot.clients.into_iter().find(|c| c.id == clid))
                    .map(|info| info.channel_id)
                    .filter(|channel| *channel != 0)
            })
            .or_else(|| {
                self.last_snapshot
                    .as_ref()
                    .and_then(|(_, clients)| clients.iter().find(|c| c.id == clid))
                    .map(|client| client.channel_id)
                    .filter(|channel| *channel != 0)
            })
    }

    /// 根据全服已发现流与当前频道成员关系重新投影 `SessionView.streams`，仅在变化时广播。
    pub(super) fn sync_streams_view(&mut self) {
        let next = match &self.stream_session {
            Some(session) => {
                let infos = session.infos();
                let streams = project_channel_streams(
                    &infos,
                    self.self_channel_id,
                    self.self_client_id,
                    |clid| self.client_channel(clid),
                );
                let watching = session.watch.as_ref().map(|watch| watch.stream_id.clone());
                (streams, watching)
            }
            None => (Vec::new(), None),
        };
        if next != self.last_streams_state {
            self.last_streams_state = next.clone();
            self.emit(SessionEvent::Streams {
                streams: next.0,
                watching: next.1,
            });
        }
    }

    /// 自己切换频道后中止跨频道观看/推流，并直接将目标频道内已发现的流投影给 UI。
    pub(super) fn on_stream_self_channel_changed(&mut self, prev_channel: u64, next_channel: u64) {
        if let Some(self_id) = self.self_client_id {
            self.record_client_channel(self_id, next_channel);
        }
        if prev_channel != 0 && prev_channel != next_channel {
            self.stream_epoch = self.stream_epoch.wrapping_add(1);
            self.end_active_watch_best_effort(StreamEndReason::SelfMoved);
            if let Some(session) = self.stream_session.as_mut() {
                if let Some(starting) = session.starting_publish.take() {
                    starting.abort.abort();
                }
                if let Some(publish) = session.publish.take() {
                    let events = self.events.clone();
                    let stream = publish.stream.clone();
                    drop(publish);
                    self.emit(SessionEvent::ScreenShareStopped);
                    spawn_best_effort_stop(stream, events);
                }
            }
        }
        self.sync_streams_view();
    }

    pub(super) fn on_stream_peer_moved(&mut self, peer_clid: i32, channel_id: u64) {
        self.record_client_channel(peer_clid, channel_id);
        let watched_left_channel = self
            .stream_session
            .as_ref()
            .and_then(|session| session.watch.as_ref())
            .is_some_and(|watch| watch.source_clid == peer_clid)
            && channel_id != self.self_channel_id;
        if watched_left_channel {
            self.end_active_watch_best_effort(StreamEndReason::SourceMoved);
        }
        if self.self_channel_id != 0
            && channel_id == self.self_channel_id
            && Some(peer_clid) != self.self_client_id
            && let Ok(clid) = u16::try_from(peer_clid)
            && clid != 0
            && let Some(session) = self.stream_session.as_ref()
            && !session
                .infos()
                .iter()
                .any(|info| info.client_id == peer_clid)
        {
            session.refresh_client(clid);
        }
        self.sync_streams_view();
    }

    pub(super) fn on_stream_peer_left(&mut self, peer_clid: i32) {
        self.remove_client_channel(peer_clid);
        let watched_left = self
            .stream_session
            .as_ref()
            .and_then(|session| session.watch.as_ref())
            .is_some_and(|watch| watch.source_clid == peer_clid);
        if watched_left {
            self.end_active_watch_best_effort(StreamEndReason::SourceLeft);
        }
        if let Some(session) = self.stream_session.as_mut()
            && let Some(publish) = session.publish.as_mut()
        {
            let stream_id = publish.stream.id().to_string();
            let removed = publish.requests.remove(&peer_clid).is_some()
                | publish.viewers.remove(&peer_clid).is_some();
            if removed {
                self.emit(SessionEvent::StreamViewerLeft {
                    stream_id,
                    viewer_clid: peer_clid,
                });
            }
        }
        self.sync_streams_view();
    }

    fn end_active_watch_best_effort(&mut self, reason: StreamEndReason) {
        let Some(watch) = self
            .stream_session
            .as_mut()
            .and_then(|session| session.watch.take())
        else {
            return;
        };
        let stream_id = watch.stream_id;
        let cleanup = match watch.phase {
            WatchPhase::Joining {
                abort,
                done,
                settled_view,
            } => cancel_joining_watch(abort, done, settled_view, self.events.clone()),
            WatchPhase::Active { view, _task } => {
                drop(_task);
                spawn_best_effort_leave_notifying(view, self.events.clone())
            }
        };
        if let Some(session) = self.stream_session.as_mut() {
            session.record_watch_cleanup(&stream_id, cleanup);
        }
        self.emit(SessionEvent::StreamEnded { stream_id, reason });
    }

    pub(super) fn join_stream(
        &mut self,
        stream_id: String,
        source_clid: i32,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let source_channel = self.client_channel(source_clid);
        let session = self
            .stream_session
            .as_ref()
            .ok_or(SessionError::NotConnected)?;
        let Some(info) = session.get_info(&stream_id) else {
            if !session.streams.supported() {
                return Err(SessionError::Stream("服务器不支持 TS6 屏幕共享".into()));
            }
            return Err(SessionError::Stream("当前频道没有这路屏幕共享".into()));
        };
        if info.client_id != source_clid {
            return Err(SessionError::Stream("推流者与屏幕共享不匹配".into()));
        }
        if self.self_channel_id == 0 || source_channel != Some(self.self_channel_id) {
            return Err(SessionError::Stream("当前频道没有这路屏幕共享".into()));
        }
        if let Some(StreamTransport::Unknown(mode)) = info.transport {
            return Err(SessionError::Stream(format!(
                "屏幕共享传输模式不受支持: mode={mode}"
            )));
        }
        if let Some(existing) = &session.watch
            && existing.stream_id == stream_id
            && existing.source_clid == source_clid
        {
            return Ok(());
        }

        self.end_active_watch_best_effort(StreamEndReason::Left);

        self.next_watch_id = self.next_watch_id.wrapping_add(1);
        let watch_id = self.next_watch_id;
        let abort = AbortSignal::new();
        let task_abort = abort.clone();
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        let target_stream_id = stream_id.clone();
        let (done_tx, done_rx) = watch::channel(false);
        let settled_view: Rc<RefCell<Option<TsStreamView>>> = Rc::new(RefCell::new(None));
        let task_settled = Rc::clone(&settled_view);
        let events_for_leave = self.events.clone();

        let Some(session) = self.stream_session.as_mut() else {
            return Err(SessionError::NotConnected);
        };
        let streams = session.streams.clone();
        let prev_cleanup = session.pending_watch_cleanups.remove(&stream_id);
        #[cfg(test)]
        let test_hook = session.test_watch_hook.clone();

        tokio::task::spawn_local(async move {
            if let Some(mut prev_done) = prev_cleanup {
                let _ = prev_done.wait_for(|&finished| finished).await;
            }
            if task_abort.is_aborted() {
                let _ = done_tx.send(true);
                let _ = signals.send(SessionSignal::WatchResolved {
                    epoch,
                    stream_epoch,
                    watch_id,
                    stream_id: target_stream_id,
                    outcome: Err(StreamError::Aborted),
                });
                return;
            }
            #[cfg(not(test))]
            let outcome = streams
                .watch(
                    &target_stream_id,
                    WatchOptions {
                        message: String::new(),
                        timeout_ms: None,
                        abort: Some(task_abort.clone()),
                    },
                )
                .await;
            #[cfg(test)]
            let outcome = match test_hook {
                Some(hook) => hook(target_stream_id.clone(), task_abort.clone()).await,
                None => {
                    streams
                        .watch(
                            &target_stream_id,
                            WatchOptions {
                                message: String::new(),
                                timeout_ms: None,
                                abort: Some(task_abort.clone()),
                            },
                        )
                        .await
                }
            };
            if task_abort.is_aborted() {
                if let Ok(view) = outcome {
                    let mut closed_rx = spawn_best_effort_leave_notifying(view, events_for_leave);
                    let _ = closed_rx.wait_for(|&closed| closed).await;
                }
                let _ = done_tx.send(true);
                let _ = signals.send(SessionSignal::WatchResolved {
                    epoch,
                    stream_epoch,
                    watch_id,
                    stream_id: target_stream_id,
                    outcome: Err(StreamError::Aborted),
                });
                return;
            }
            if let Ok(ref view) = outcome {
                *task_settled.borrow_mut() = Some(view.clone());
            }
            let _ = done_tx.send(true);
            let _ = signals.send(SessionSignal::WatchResolved {
                epoch,
                stream_epoch,
                watch_id,
                stream_id: target_stream_id,
                outcome,
            });
        });

        session.watch = Some(ActiveWatch {
            id: watch_id,
            stream_id,
            source_clid,
            phase: WatchPhase::Joining {
                abort,
                done: done_rx,
                settled_view,
            },
        });
        self.sync_streams_view();
        Ok(())
    }

    /// 先清理本地观看状态再在后台任务通知服务端退出，命令失败也不会残留悬空观看或阻塞 Actor。
    pub(super) fn leave_stream(
        &mut self,
        stream_id: String,
        reply: oneshot::Sender<Result<(), SessionError>>,
    ) {
        let Some(session) = self.stream_session.as_mut() else {
            let _ = reply.send(Err(SessionError::Stream("没有在观看这路屏幕共享".into())));
            return;
        };
        if session
            .watch
            .as_ref()
            .is_none_or(|watch| watch.stream_id != stream_id)
        {
            let _ = reply.send(Err(SessionError::Stream("没有在观看这路屏幕共享".into())));
            return;
        }
        let watch = session.watch.take().unwrap();
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        match watch.phase {
            WatchPhase::Joining {
                abort,
                done,
                settled_view,
            } => {
                abort.abort();
                if let Some(view) = settled_view.borrow_mut().take() {
                    let (closed_tx, closed_rx) = watch::channel(false);
                    session.record_watch_cleanup(&watch.stream_id, closed_rx);
                    self.sync_streams_view();
                    self.emit(SessionEvent::StreamEnded {
                        stream_id: watch.stream_id,
                        reason: StreamEndReason::Left,
                    });
                    tokio::task::spawn_local(async move {
                        let mut fut = std::pin::pin!(view.leave());
                        let first_res = std::future::poll_fn(|cx| match fut.as_mut().poll(cx) {
                            std::task::Poll::Ready(res) => std::task::Poll::Ready(Some(res)),
                            std::task::Poll::Pending => std::task::Poll::Ready(None),
                        })
                        .await;
                        let _ = closed_tx.send(true);
                        let outcome = match first_res {
                            Some(res) => res,
                            None => fut.await,
                        };
                        let _ = signals.send(SessionSignal::StreamCommandFinished {
                            epoch,
                            stream_epoch,
                            require_matching_epoch: false,
                            outcome,
                            reply,
                        });
                    });
                    return;
                }
                let mut wait_done = done.clone();
                session.record_watch_cleanup(&watch.stream_id, done);
                self.sync_streams_view();
                self.emit(SessionEvent::StreamEnded {
                    stream_id: watch.stream_id,
                    reason: StreamEndReason::Left,
                });
                tokio::task::spawn_local(async move {
                    let _ = wait_done.wait_for(|&finished| finished).await;
                    let _ = signals.send(SessionSignal::StreamCommandFinished {
                        epoch,
                        stream_epoch,
                        require_matching_epoch: false,
                        outcome: Ok(()),
                        reply,
                    });
                });
            }
            WatchPhase::Active { view, _task } => {
                drop(_task);
                let (closed_tx, closed_rx) = watch::channel(false);
                session.record_watch_cleanup(&watch.stream_id, closed_rx);
                self.sync_streams_view();
                self.emit(SessionEvent::StreamEnded {
                    stream_id: watch.stream_id,
                    reason: StreamEndReason::Left,
                });
                tokio::task::spawn_local(async move {
                    let mut fut = std::pin::pin!(view.leave());
                    let first_res = std::future::poll_fn(|cx| match fut.as_mut().poll(cx) {
                        std::task::Poll::Ready(res) => std::task::Poll::Ready(Some(res)),
                        std::task::Poll::Pending => std::task::Poll::Ready(None),
                    })
                    .await;
                    let _ = closed_tx.send(true);
                    let outcome = match first_res {
                        Some(res) => res,
                        None => fut.await,
                    };
                    let _ = signals.send(SessionSignal::StreamCommandFinished {
                        epoch,
                        stream_epoch,
                        require_matching_epoch: false,
                        outcome,
                        reply,
                    });
                });
            }
        }
    }

    fn watched_active_view(
        &self,
        stream_id: &str,
        target_clid: i32,
    ) -> Result<TsStreamView, SessionError> {
        let watch = self
            .stream_session
            .as_ref()
            .and_then(|session| session.watch.as_ref())
            .filter(|watch| watch.stream_id == stream_id)
            .ok_or_else(|| SessionError::Stream("没有在观看这路屏幕共享".into()))?;
        if watch.source_clid != target_clid {
            return Err(SessionError::Stream("信令目标不是这路共享的推流者".into()));
        }
        match &watch.phase {
            WatchPhase::Active { view, .. } => Ok(view.clone()),
            WatchPhase::Joining { .. } => {
                Err(SessionError::Stream("观看会话尚未收到推流者应答".into()))
            }
        }
    }

    pub(super) fn send_stream_answer(
        &self,
        stream_id: String,
        target_clid: i32,
        sdp: String,
        reply: oneshot::Sender<Result<(), SessionError>>,
    ) {
        if let Err(err) = self.connected() {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!(
                    "发送 Answer 失败: stream_id={stream_id}, target_clid={target_clid}, error={err}"
                ),
            });
            let _ = reply.send(Err(err));
            return;
        }
        let view = match self.watched_active_view(&stream_id, target_clid) {
            Ok(view) => view,
            Err(err) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "发送 Answer 失败: stream_id={stream_id}, target_clid={target_clid}, error={err}"
                    ),
                });
                let _ = reply.send(Err(err));
                return;
            }
        };
        let signals = self.signals.clone();
        let events = self.events.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        tokio::task::spawn_local(async move {
            let outcome = view.answer(&sdp).await;
            if let Err(ref err) = outcome {
                emit(
                    &events,
                    SessionEvent::Log {
                        level: "warn".into(),
                        message: format!(
                            "发送 Answer 失败: stream_id={stream_id}, target_clid={target_clid}, error={err}"
                        ),
                    },
                );
            }
            let _ = signals.send(SessionSignal::StreamCommandFinished {
                epoch,
                stream_epoch,
                require_matching_epoch: true,
                outcome,
                reply,
            });
        });
    }

    pub(super) fn send_stream_ice_candidate(
        &self,
        stream_id: String,
        target_clid: i32,
        sdp: String,
        mid: Option<String>,
        m_line: Option<i32>,
        reply: oneshot::Sender<Result<(), SessionError>>,
    ) {
        if let Err(err) = self.connected() {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!(
                    "发送 iceCandidate 失败: stream_id={stream_id}, target_clid={target_clid}, error={err}"
                ),
            });
            let _ = reply.send(Err(err));
            return;
        }
        let view = match self.watched_active_view(&stream_id, target_clid) {
            Ok(view) => view,
            Err(err) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "发送 iceCandidate 失败: stream_id={stream_id}, target_clid={target_clid}, error={err}"
                    ),
                });
                let _ = reply.send(Err(err));
                return;
            }
        };
        let cand = match ice_candidate(sdp, mid, m_line) {
            Ok(cand) => cand,
            Err(err) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "发送 iceCandidate 失败: stream_id={stream_id}, target_clid={target_clid}, error={err}"
                    ),
                });
                let _ = reply.send(Err(err));
                return;
            }
        };
        let signals = self.signals.clone();
        let events = self.events.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        tokio::task::spawn_local(async move {
            let outcome = view.send_candidate(&cand).await;
            if let Err(ref err) = outcome {
                emit(
                    &events,
                    SessionEvent::Log {
                        level: "warn".into(),
                        message: format!(
                            "发送 iceCandidate 失败: stream_id={stream_id}, target_clid={target_clid}, error={err}"
                        ),
                    },
                );
            }
            let _ = signals.send(SessionSignal::StreamCommandFinished {
                epoch,
                stream_epoch,
                require_matching_epoch: true,
                outcome,
                reply,
            });
        });
    }

    pub(super) fn start_screen_share(
        &mut self,
        name: String,
        audio: bool,
        bitrate: u32,
        viewer_limit: u32,
        reply: oneshot::Sender<Result<(), SessionError>>,
    ) {
        if let Err(err) = self.connected() {
            let _ = reply.send(Err(err));
            return;
        }
        if self.self_channel_id == 0 {
            let _ = reply.send(Err(SessionError::NotInChannel));
            return;
        }
        let mut options = match publish_options(&name, audio, bitrate, viewer_limit) {
            Ok(options) => options,
            Err(err) => {
                let _ = reply.send(Err(err));
                return;
            }
        };
        let Some(session) = self.stream_session.as_ref() else {
            let _ = reply.send(Err(SessionError::NotConnected));
            return;
        };
        if session.publish.is_some() || session.starting_publish.is_some() {
            let _ = reply.send(Err(SessionError::Stream(
                "当前已在推流或正在启动推流".into(),
            )));
            return;
        }
        let publish_token = self.next_stream_token();
        let abort = AbortSignal::new();
        options.abort = Some(abort.clone());
        let session = self.stream_session.as_mut().expect("checked above");
        session.starting_publish = Some(StartingPublish {
            token: publish_token,
            abort,
        });
        let streams = session.streams.clone();
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        tokio::task::spawn_local(async move {
            let outcome = streams.publish(options).await;
            let _ = signals.send(SessionSignal::StartScreenShareResolved {
                epoch,
                stream_epoch,
                publish_token,
                outcome,
                reply,
            });
        });
    }

    pub(super) fn handle_start_screen_share_resolved(
        &mut self,
        epoch: u64,
        stream_epoch: u64,
        publish_token: u64,
        outcome: Result<PublishedStream, StreamError>,
        reply: oneshot::Sender<Result<(), SessionError>>,
    ) {
        if epoch != self.connection_epoch || stream_epoch != self.stream_epoch {
            if let Ok(published) = outcome {
                spawn_best_effort_stop(PublishedStreamHandle::Live(published), self.events.clone());
            }
            let _ = reply.send(Err(if epoch != self.connection_epoch {
                SessionError::NotConnected
            } else {
                SessionError::Stream("屏幕共享启动已取消".into())
            }));
            return;
        }
        let Some(session) = self.stream_session.as_mut() else {
            if let Ok(published) = outcome {
                spawn_best_effort_stop(PublishedStreamHandle::Live(published), self.events.clone());
            }
            let _ = reply.send(Err(SessionError::NotConnected));
            return;
        };
        let is_current = session
            .starting_publish
            .as_ref()
            .is_some_and(|starting| starting.token == publish_token);
        if !is_current || session.publish.is_some() {
            if let Ok(published) = outcome {
                spawn_best_effort_stop(PublishedStreamHandle::Live(published), self.events.clone());
            }
            let _ = reply.send(Err(SessionError::Stream("屏幕共享启动已取消".into())));
            return;
        }
        session.starting_publish = None;
        match outcome {
            Ok(published) => {
                let stream_id = published.id().to_string();
                let mut sub = published.subscribe();
                let signals = self.signals.clone();
                let pub_stream_id = stream_id.clone();
                let pub_task = tokio::task::spawn_local(async move {
                    while let Some(event) = sub.recv().await {
                        if signals
                            .send(SessionSignal::PublishedStreamEvent {
                                epoch,
                                stream_epoch,
                                stream_id: pub_stream_id.clone(),
                                event,
                            })
                            .is_err()
                        {
                            break;
                        }
                    }
                });
                session.publish = Some(ActivePublish {
                    stream: PublishedStreamHandle::Live(published),
                    requests: HashMap::new(),
                    viewers: HashMap::new(),
                    _task: PumpGuard(pub_task),
                });
                self.emit(SessionEvent::ScreenSharePublished { stream_id });
                let _ = reply.send(Ok(()));
            }
            Err(err) => {
                let _ = reply.send(Err(stream_error(err)));
            }
        }
    }

    pub(super) fn stop_screen_share(&mut self, reply: oneshot::Sender<Result<(), SessionError>>) {
        let Some(session) = self.stream_session.as_mut() else {
            let _ = reply.send(Ok(()));
            return;
        };
        if let Some(starting) = session.starting_publish.take() {
            starting.abort.abort();
        }
        let Some(publish) = session.publish.take() else {
            let _ = reply.send(Ok(()));
            return;
        };
        let stream = publish.stream.clone();
        drop(publish);
        self.emit(SessionEvent::ScreenShareStopped);
        if self.client.is_none() {
            let _ = reply.send(Ok(()));
            return;
        }
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        tokio::task::spawn_local(async move {
            let outcome = stream.stop(0).await;
            let _ = signals.send(SessionSignal::StreamCommandFinished {
                epoch,
                stream_epoch,
                require_matching_epoch: false,
                outcome,
                reply,
            });
        });
    }

    pub(super) fn respond_stream_join_request(
        &mut self,
        viewer_clid: i32,
        accept: bool,
        offer_sdp: String,
        reply: oneshot::Sender<Result<(), SessionError>>,
    ) {
        if let Err(err) = self.connected() {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!(
                    "发送 respondjoinstreamrequest 失败: viewer_clid={viewer_clid}, accept={accept}, error={err}"
                ),
            });
            let _ = reply.send(Err(err));
            return;
        }
        if accept && offer_sdp.trim().is_empty() {
            let err = SessionError::Stream("接受观看请求必须提供 SDP Offer".into());
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!(
                    "发送 respondjoinstreamrequest 失败: viewer_clid={viewer_clid}, accept={accept}, error={err}"
                ),
            });
            let _ = reply.send(Err(err));
            return;
        }
        let Some(publish) = self
            .stream_session
            .as_mut()
            .and_then(|session| session.publish.as_mut())
        else {
            let err = SessionError::Stream("当前没有活动的屏幕共享推流".into());
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!(
                    "发送 respondjoinstreamrequest 失败: viewer_clid={viewer_clid}, accept={accept}, error={err}"
                ),
            });
            let _ = reply.send(Err(err));
            return;
        };
        let stream_id = publish.stream.id().to_string();
        let Some(pending) = publish.requests.get_mut(&viewer_clid) else {
            let err = SessionError::Stream("该客户端未请求观看屏幕共享".into());
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!(
                    "发送 respondjoinstreamrequest 失败: stream_id={stream_id}, viewer_clid={viewer_clid}, accept={accept}, error={err}"
                ),
            });
            let _ = reply.send(Err(err));
            return;
        };
        if pending.responding {
            let err = SessionError::Stream("正在响应这名观众的加入请求".into());
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!(
                    "发送 respondjoinstreamrequest 失败: stream_id={stream_id}, viewer_clid={viewer_clid}, accept={accept}, error={err}"
                ),
            });
            let _ = reply.send(Err(err));
            return;
        }
        pending.responding = true;
        let request = pending.request.clone();
        let request_token = pending.token;
        self.emit(SessionEvent::Log {
            level: "info".into(),
            message: format!(
                "发送 respondjoinstreamrequest: stream_id={stream_id}, viewer_clid={viewer_clid}, accept={accept}, offer_sdp_len={}",
                offer_sdp.len()
            ),
        });
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        tokio::task::spawn_local(async move {
            let outcome = if accept {
                request.accept(&offer_sdp, "").await.map(Some)
            } else {
                request.deny("").await.map(|()| None)
            };
            let _ = signals.send(SessionSignal::StreamJoinResponseResolved(
                StreamJoinResponse {
                    epoch,
                    stream_epoch,
                    stream_id,
                    viewer_clid,
                    request_token,
                    accept,
                    outcome,
                    reply,
                },
            ));
        });
    }

    pub(super) fn handle_stream_join_response_resolved(&mut self, response: StreamJoinResponse) {
        let StreamJoinResponse {
            epoch,
            stream_epoch,
            stream_id,
            viewer_clid,
            request_token,
            accept,
            outcome,
            reply,
        } = response;
        if let Err(ref err) = outcome {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!(
                    "发送 respondjoinstreamrequest 失败: stream_id={stream_id}, viewer_clid={viewer_clid}, accept={accept}, error={err}"
                ),
            });
        }
        if epoch != self.connection_epoch || stream_epoch != self.stream_epoch {
            if let Ok(Some(peer)) = outcome {
                tokio::task::spawn_local(async move {
                    let _ = peer.close().await;
                });
            }
            let _ = reply.send(Err(if epoch != self.connection_epoch {
                SessionError::NotConnected
            } else {
                SessionError::Stream("屏幕共享会话已结束".into())
            }));
            return;
        }
        let has_matching_publish = self
            .stream_session
            .as_ref()
            .and_then(|session| session.publish.as_ref())
            .is_some_and(|publish| publish.stream.id() == stream_id);
        if !has_matching_publish {
            if let Ok(Some(peer)) = outcome {
                tokio::task::spawn_local(async move {
                    let _ = peer.close().await;
                });
            }
            let _ = reply.send(Err(SessionError::Stream(
                "当前没有活动的屏幕共享推流".into(),
            )));
            return;
        }

        let still_pending = self
            .stream_session
            .as_ref()
            .and_then(|session| session.publish.as_ref())
            .and_then(|publish| publish.requests.get(&viewer_clid))
            .is_some_and(|pending| pending.token == request_token);
        if !still_pending {
            let result = match outcome {
                Ok(Some(peer)) => {
                    tokio::task::spawn_local(async move {
                        let _ = peer.kick(1).await;
                    });
                    Err(SessionError::Stream("观看请求已取消".into()))
                }
                Ok(None) => {
                    if accept {
                        Err(SessionError::Stream("观看请求已取消".into()))
                    } else {
                        Ok(())
                    }
                }
                Err(err) => {
                    if accept {
                        Err(SessionError::Stream("观看请求已取消".into()))
                    } else {
                        Err(stream_error(err))
                    }
                }
            };
            let _ = reply.send(result);
            return;
        }

        match outcome {
            Ok(Some(peer)) => {
                if peer.closed() {
                    if let Some(publish) = self
                        .stream_session
                        .as_mut()
                        .and_then(|session| session.publish.as_mut())
                    {
                        publish.requests.remove(&viewer_clid);
                    }
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!(
                            "发送 respondjoinstreamrequest 后观众已关闭: stream_id={stream_id}, viewer_clid={viewer_clid}"
                        ),
                    });
                    self.emit(SessionEvent::StreamViewerLeft {
                        stream_id,
                        viewer_clid,
                    });
                    let _ = reply.send(Err(SessionError::Stream("观众已离开屏幕共享".into())));
                    return;
                }
                let peer_token = self.next_stream_token();
                let mut sub = peer.subscribe();
                let signals = self.signals.clone();
                let peer_stream_id = peer.stream_id().to_string();
                let peer_task = tokio::task::spawn_local(async move {
                    while let Some(event) = sub.recv().await {
                        if signals
                            .send(SessionSignal::PublisherPeerEvent {
                                epoch,
                                stream_epoch,
                                stream_id: peer_stream_id.clone(),
                                viewer_clid,
                                token: peer_token,
                                event,
                            })
                            .is_err()
                        {
                            break;
                        }
                    }
                });
                if let Some(publish) = self
                    .stream_session
                    .as_mut()
                    .and_then(|session| session.publish.as_mut())
                    .filter(|publish| publish.stream.id() == stream_id)
                {
                    publish.requests.remove(&viewer_clid);
                    publish.viewers.insert(
                        viewer_clid,
                        AcceptedViewer {
                            token: peer_token,
                            peer,
                            _task: PumpGuard(peer_task),
                        },
                    );
                }
                let _ = reply.send(Ok(()));
            }
            Ok(None) => {
                if let Some(publish) = self
                    .stream_session
                    .as_mut()
                    .and_then(|session| session.publish.as_mut())
                {
                    publish.requests.remove(&viewer_clid);
                }
                let _ = reply.send(Ok(()));
            }
            Err(err) => {
                let mut removed_terminal = false;
                if let Some(publish) = self
                    .stream_session
                    .as_mut()
                    .and_then(|session| session.publish.as_mut())
                    && let Some(pending) = publish.requests.get_mut(&viewer_clid)
                    && pending.token == request_token
                {
                    if pending.request.state() == JoinRequestState::Pending {
                        pending.responding = false;
                    } else {
                        publish.requests.remove(&viewer_clid);
                        removed_terminal = true;
                    }
                }
                if removed_terminal {
                    self.emit(SessionEvent::StreamViewerLeft {
                        stream_id,
                        viewer_clid,
                    });
                }
                let _ = reply.send(Err(stream_error(err)));
            }
        }
    }

    pub(super) fn send_publisher_ice_candidate(
        &self,
        viewer_clid: i32,
        sdp: String,
        mid: Option<String>,
        m_line: Option<i32>,
        reply: oneshot::Sender<Result<(), SessionError>>,
    ) {
        if let Err(err) = self.connected() {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("发送 iceCandidate 失败: viewer_clid={viewer_clid}, error={err}"),
            });
            let _ = reply.send(Err(err));
            return;
        }
        let Some(publish) = self
            .stream_session
            .as_ref()
            .and_then(|session| session.publish.as_ref())
        else {
            let err = SessionError::Stream("当前没有活动的屏幕共享推流".into());
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("发送 iceCandidate 失败: viewer_clid={viewer_clid}, error={err}"),
            });
            let _ = reply.send(Err(err));
            return;
        };
        let stream_id = publish.stream.id().to_string();
        let peer = match publish.viewers.get(&viewer_clid) {
            Some(accepted) => accepted.peer.clone(),
            None if publish.requests.contains_key(&viewer_clid) => {
                let err = SessionError::Stream("观众尚未完成加入应答，不能发送信令".into());
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "发送 iceCandidate 失败: stream_id={stream_id}, viewer_clid={viewer_clid}, error={err}"
                    ),
                });
                let _ = reply.send(Err(err));
                return;
            }
            None => {
                let err = SessionError::Stream("信令目标不是当前推流的观众".into());
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "发送 iceCandidate 失败: stream_id={stream_id}, viewer_clid={viewer_clid}, error={err}"
                    ),
                });
                let _ = reply.send(Err(err));
                return;
            }
        };
        let cand = match ice_candidate(sdp, mid, m_line) {
            Ok(cand) => cand,
            Err(err) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "发送 iceCandidate 失败: stream_id={stream_id}, viewer_clid={viewer_clid}, error={err}"
                    ),
                });
                let _ = reply.send(Err(err));
                return;
            }
        };
        self.emit(SessionEvent::Log {
            level: "info".into(),
            message: format!(
                "发送 iceCandidate: stream_id={stream_id}, viewer_clid={viewer_clid}, {}",
                candidate_summary(&cand)
            ),
        });
        let signals = self.signals.clone();
        let events = self.events.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        tokio::task::spawn_local(async move {
            let outcome = peer.send_candidate(&cand).await;
            if let Err(ref err) = outcome {
                emit(
                    &events,
                    SessionEvent::Log {
                        level: "warn".into(),
                        message: format!(
                            "发送 iceCandidate 失败: stream_id={stream_id}, viewer_clid={viewer_clid}, error={err}"
                        ),
                    },
                );
            }
            let _ = signals.send(SessionSignal::StreamCommandFinished {
                epoch,
                stream_epoch,
                require_matching_epoch: true,
                outcome,
                reply,
            });
        });
    }

    pub(super) fn kick_stream_viewer(
        &mut self,
        viewer_clid: i32,
        reply: oneshot::Sender<Result<(), SessionError>>,
    ) {
        if let Err(err) = self.connected() {
            let _ = reply.send(Err(err));
            return;
        }
        let Some(publish) = self
            .stream_session
            .as_mut()
            .and_then(|session| session.publish.as_mut())
        else {
            let _ = reply.send(Err(SessionError::Stream(
                "当前没有活动的屏幕共享推流".into(),
            )));
            return;
        };
        let stream_id = publish.stream.id().to_string();
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        if let Some(accepted) = publish.viewers.remove(&viewer_clid) {
            drop(accepted._task);
            self.emit(SessionEvent::StreamViewerLeft {
                stream_id,
                viewer_clid,
            });
            tokio::task::spawn_local(async move {
                let outcome = accepted.peer.kick(1).await;
                let _ = signals.send(SessionSignal::StreamCommandFinished {
                    epoch,
                    stream_epoch,
                    require_matching_epoch: false,
                    outcome,
                    reply,
                });
            });
            return;
        }
        if let Some(pending) = publish.requests.remove(&viewer_clid) {
            drop(pending._task);
            self.emit(SessionEvent::StreamViewerLeft {
                stream_id,
                viewer_clid,
            });
            if pending.responding {
                let _ = reply.send(Ok(()));
                return;
            }
            tokio::task::spawn_local(async move {
                let outcome = pending.request.deny("").await;
                let _ = signals.send(SessionSignal::StreamCommandFinished {
                    epoch,
                    stream_epoch,
                    require_matching_epoch: false,
                    outcome,
                    reply,
                });
            });
            return;
        }
        let _ = reply.send(Err(SessionError::Stream(
            "目标客户端不是当前推流的观众".into(),
        )));
    }

    pub(super) fn handle_stream_command_finished(
        &self,
        epoch: u64,
        stream_epoch: u64,
        require_matching_epoch: bool,
        outcome: Result<(), StreamError>,
        reply: oneshot::Sender<Result<(), SessionError>>,
    ) {
        if epoch != self.connection_epoch {
            let _ = reply.send(Err(SessionError::NotConnected));
            return;
        }
        if require_matching_epoch && stream_epoch != self.stream_epoch {
            let _ = reply.send(Err(match outcome {
                Err(err) => stream_error(err),
                Ok(()) => SessionError::Stream("屏幕共享会话已结束".into()),
            }));
            return;
        }
        let _ = reply.send(outcome.map_err(stream_error));
    }

    pub(super) fn handle_streams_bus_event(&mut self, event: StreamsEvent) {
        match event {
            StreamsEvent::Started(info) | StreamsEvent::Updated(info) => {
                self.emit(SessionEvent::Log {
                    level: "debug".into(),
                    message: format!(
                        "发现或更新屏幕共享: id={}, clid={}, name={}",
                        info.id, info.client_id, info.name
                    ),
                });
                self.sync_streams_view();
            }
            StreamsEvent::Stopped(stopped) => {
                let stop_id = stopped.info.id;
                let watching_stopped = self
                    .stream_session
                    .as_ref()
                    .and_then(|session| session.watch.as_ref())
                    .is_some_and(|watch| watch.stream_id == stop_id);
                if watching_stopped {
                    self.end_active_watch_best_effort(StreamEndReason::SourceStopped);
                }
                if let Some(session) = self.stream_session.as_mut()
                    && session
                        .publish
                        .as_ref()
                        .is_some_and(|publish| publish.stream.id() == stop_id)
                {
                    session.publish = None;
                    self.emit(SessionEvent::ScreenShareStopped);
                }
                self.sync_streams_view();
            }
            StreamsEvent::ViewerJoined(_) => {}
            StreamsEvent::ViewerLeft(ev) => {
                if let Some(session) = self.stream_session.as_mut()
                    && let Some(publish) = session.publish.as_mut()
                    && publish.stream.id() == ev.info.id
                {
                    // 仅清理已进入终态/已关闭的旧会话，防止迟到的总线事件误删重连后的新观众。
                    let mut removed = false;
                    if publish.requests.get(&ev.client_id).is_some_and(|pending| {
                        !pending.responding
                            && matches!(
                                pending.request.state(),
                                JoinRequestState::Withdrawn | JoinRequestState::Ended
                            )
                    }) {
                        publish.requests.remove(&ev.client_id);
                        removed = true;
                    }
                    if publish
                        .viewers
                        .get(&ev.client_id)
                        .is_some_and(|accepted| accepted.peer.closed())
                    {
                        publish.viewers.remove(&ev.client_id);
                        removed = true;
                    }
                    if removed {
                        self.emit(SessionEvent::StreamViewerLeft {
                            stream_id: ev.info.id,
                            viewer_clid: ev.client_id,
                        });
                    }
                }
            }
            StreamsEvent::Error(err) => match err {
                StreamError::Unsupported(_) => {
                    let should_log = self.stream_session.as_mut().is_some_and(|session| {
                        let first = !session.unsupported_logged;
                        session.unsupported_logged = true;
                        first
                    });
                    if should_log {
                        self.emit(SessionEvent::Log {
                            level: "info".into(),
                            message: "服务器不支持 TS6 屏幕共享".into(),
                        });
                    }
                }
                StreamError::Aborted => {}
                other => {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("屏幕共享异常: {other}"),
                    });
                }
            },
            StreamsEvent::Warning(warning) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("屏幕共享告警 [{}]: {}", warning.stream_id, warning.message),
                });
            }
        }
    }

    pub(super) fn handle_watch_resolved(
        &mut self,
        watch_id: u64,
        stream_id: String,
        outcome: Result<TsStreamView, StreamError>,
    ) {
        let is_current = self
            .stream_session
            .as_ref()
            .and_then(|session| session.watch.as_ref())
            .is_some_and(|watch| watch.id == watch_id);
        if !is_current {
            if let Ok(view) = outcome
                && !view.closed()
            {
                let _ = spawn_best_effort_leave_notifying(view, self.events.clone());
            }
            return;
        }

        match outcome {
            Ok(view) => {
                let mut sub = view.subscribe();
                let signals = self.signals.clone();
                let epoch = self.connection_epoch;
                let stream_epoch = self.stream_epoch;
                let view_stream_id = view.stream_id().to_string();
                let source_client_id = view.client_id();
                let sdp = view.offer().to_string();
                let peer_task = tokio::task::spawn_local(async move {
                    while let Some(event) = sub.recv().await {
                        if signals
                            .send(SessionSignal::ViewerPeerEvent {
                                epoch,
                                stream_epoch,
                                watch_id,
                                stream_id: view_stream_id.clone(),
                                event,
                            })
                            .is_err()
                        {
                            break;
                        }
                    }
                });
                if let Some(session) = self.stream_session.as_mut()
                    && let Some(watch) = session.watch.as_mut()
                    && watch.id == watch_id
                {
                    watch.phase = WatchPhase::Active {
                        view,
                        _task: PumpGuard(peer_task),
                    };
                }
                self.emit(SessionEvent::StreamOffer {
                    stream_id,
                    source_client_id,
                    sdp,
                });
            }
            Err(err) => {
                if let Some(session) = self.stream_session.as_mut() {
                    session.watch = None;
                }
                self.sync_streams_view();
                if !matches!(err, StreamError::Aborted) {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("观看屏幕共享 {stream_id} 失败: {err}"),
                    });
                }
                self.emit(SessionEvent::StreamEnded {
                    stream_id,
                    reason: watch_error_reason(&err),
                });
            }
        }
    }

    pub(super) fn handle_viewer_peer_event(
        &mut self,
        watch_id: u64,
        stream_id: String,
        event: PeerEvent,
    ) {
        let Some(source_clid) = self
            .stream_session
            .as_ref()
            .and_then(|session| session.watch.as_ref())
            .filter(|watch| watch.id == watch_id)
            .map(|watch| watch.source_clid)
        else {
            return;
        };

        match event {
            PeerEvent::Offer(sdp) => {
                self.emit(SessionEvent::StreamOffer {
                    stream_id,
                    source_client_id: source_clid,
                    sdp,
                });
            }
            PeerEvent::Candidate(cand) => {
                self.emit(SessionEvent::StreamIceCandidate {
                    stream_id,
                    source_client_id: source_clid,
                    sdp: cand.candidate,
                    mid: cand.sdp_mid,
                    m_line: cand.sdp_m_line_index.map(i32::from),
                });
            }
            PeerEvent::Closed(closed) => {
                if let Some(session) = self.stream_session.as_mut() {
                    session.watch = None;
                }
                self.sync_streams_view();
                self.emit(SessionEvent::StreamEnded {
                    stream_id,
                    reason: peer_close_reason(closed.cause),
                });
            }
            PeerEvent::Answer(_) | PeerEvent::Signal(_) => {}
        }
    }

    pub(super) fn handle_published_stream_event(
        &mut self,
        stream_id: String,
        event: PublishedStreamEvent,
    ) {
        match event {
            PublishedStreamEvent::Request(request) => {
                self.handle_published_stream_request(stream_id, JoinRequestHandle::Live(request));
            }
            PublishedStreamEvent::Ended(_) => {
                let is_current = self
                    .stream_session
                    .as_ref()
                    .and_then(|session| session.publish.as_ref())
                    .is_some_and(|publish| publish.stream.id() == stream_id);
                if !is_current {
                    return;
                }
                if let Some(session) = self.stream_session.as_mut() {
                    session.publish = None;
                }
                self.emit(SessionEvent::ScreenShareStopped);
            }
        }
    }

    fn handle_published_stream_request(&mut self, stream_id: String, request: JoinRequestHandle) {
        let viewer_clid = request.viewer_client_id();
        // 同一个 viewer_clid 重新发起请求时，旧 PeerEvent::Closed 可能还留在信号队列中；
        // 先清理旧会话并通知前端关闭，再注册新请求，避免迟到的 Closed 误删新会话。
        let (replaced_viewer, replaced_request) = {
            let Some(publish) = self
                .stream_session
                .as_mut()
                .and_then(|session| session.publish.as_mut())
                .filter(|publish| publish.stream.id() == stream_id)
            else {
                return;
            };
            (
                publish.viewers.remove(&viewer_clid),
                publish.requests.remove(&viewer_clid),
            )
        };
        let replaced = replaced_viewer.is_some() || replaced_request.is_some();
        drop(replaced_viewer);
        drop(replaced_request);

        self.emit(SessionEvent::Log {
            level: "info".into(),
            message: format!(
                "收到 notifyjoinstreamrequest: stream_id={stream_id}, viewer_clid={viewer_clid}, replaced={replaced}"
            ),
        });
        if replaced {
            self.emit(SessionEvent::StreamViewerLeft {
                stream_id: stream_id.clone(),
                viewer_clid,
            });
        }

        let token = self.next_stream_token();
        let mut sub = request.subscribe();
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let stream_epoch = self.stream_epoch;
        let req_stream_id = stream_id.clone();
        let req_task = tokio::task::spawn_local(async move {
            if let Some(JoinRequestEvent::Closed { cause }) = sub.recv().await {
                let _ = signals.send(SessionSignal::JoinRequestClosed {
                    epoch,
                    stream_epoch,
                    stream_id: req_stream_id,
                    viewer_clid,
                    token,
                    cause,
                });
            }
        });
        if let Some(session) = self.stream_session.as_mut()
            && let Some(publish) = session.publish.as_mut()
            && publish.stream.id() == stream_id
        {
            publish.requests.insert(
                viewer_clid,
                PendingViewerRequest {
                    token,
                    request,
                    responding: false,
                    _task: PumpGuard(req_task),
                },
            );
            self.emit(SessionEvent::StreamViewerJoinRequested {
                stream_id,
                viewer_clid,
            });
        }
    }

    pub(super) fn handle_join_request_closed(
        &mut self,
        stream_id: String,
        viewer_clid: i32,
        token: u64,
        _cause: JoinRequestCloseCause,
    ) {
        let Some(publish) = self
            .stream_session
            .as_mut()
            .and_then(|session| session.publish.as_mut())
            .filter(|publish| publish.stream.id() == stream_id)
        else {
            return;
        };
        if publish
            .requests
            .get(&viewer_clid)
            .is_some_and(|pending| pending.token == token)
        {
            publish.requests.remove(&viewer_clid);
            self.emit(SessionEvent::StreamViewerLeft {
                stream_id,
                viewer_clid,
            });
        }
    }

    pub(super) fn handle_publisher_peer_event(
        &mut self,
        stream_id: String,
        viewer_clid: i32,
        token: u64,
        event: PeerEvent,
    ) {
        let Some(publish) = self
            .stream_session
            .as_mut()
            .and_then(|session| session.publish.as_mut())
            .filter(|publish| publish.stream.id() == stream_id)
        else {
            return;
        };
        if !publish
            .viewers
            .get(&viewer_clid)
            .is_some_and(|viewer| viewer.token == token)
        {
            return;
        }
        match event {
            PeerEvent::Answer(sdp) => {
                self.emit(SessionEvent::Log {
                    level: "info".into(),
                    message: format!(
                        "收到推流观众信令: stream_id={stream_id}, viewer_clid={viewer_clid}, type=Answer, sdp_len={}",
                        sdp.len()
                    ),
                });
                self.emit(SessionEvent::PublisherSignalReceived {
                    stream_id,
                    viewer_clid,
                    signal: PublisherSignal::Answer { sdp },
                });
            }
            PeerEvent::Candidate(cand) => {
                self.emit(SessionEvent::Log {
                    level: "info".into(),
                    message: format!(
                        "收到推流观众信令: stream_id={stream_id}, viewer_clid={viewer_clid}, type=iceCandidate, {}",
                        candidate_summary(&cand)
                    ),
                });
                self.emit(SessionEvent::PublisherSignalReceived {
                    stream_id,
                    viewer_clid,
                    signal: PublisherSignal::IceCandidate {
                        sdp: cand.candidate,
                        mid: cand.sdp_mid,
                        m_line: cand.sdp_m_line_index.map(i32::from),
                    },
                });
            }
            PeerEvent::Closed(closed) => {
                if publish.viewers.remove(&viewer_clid).is_some() {
                    self.emit(SessionEvent::Log {
                        level: "info".into(),
                        message: format!(
                            "推流观众会话关闭: stream_id={stream_id}, viewer_clid={viewer_clid}, cause={:?}",
                            closed.cause
                        ),
                    });
                    self.emit(SessionEvent::StreamViewerLeft {
                        stream_id,
                        viewer_clid,
                    });
                }
            }
            PeerEvent::Offer(_) | PeerEvent::Signal(_) => {}
        }
    }
}

#[cfg(test)]
impl Actor {
    pub(super) fn push_test_stream_event(&mut self, event: StreamsEvent) {
        if let Some(session) = &mut self.stream_session {
            match &event {
                StreamsEvent::Started(info) | StreamsEvent::Updated(info) => {
                    session.test_infos.insert(info.id.clone(), info.clone());
                }
                StreamsEvent::Stopped(stopped) => {
                    session.test_infos.remove(&stopped.info.id);
                }
                _ => {}
            }
        }
        self.handle_streams_bus_event(event);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::test_support::*;
    use std::future::Future;
    use tsclient_rs::stream::{StreamAccessibility, StreamSource, StreamsUnsupportedError};
    use tsclient_rs::{ClientInfo, ClientOptions, DirectorySnapshot};

    async fn run_local<F: Future>(fut: F) -> F::Output {
        tokio::task::LocalSet::new().run_until(fut).await
    }

    fn make_client() -> Arc<Client> {
        Arc::new(Client::new(
            tsclient_rs::generateIdentity(0),
            "127.0.0.1:9987".into(),
            "Self".into(),
            ClientOptions::default(),
        ))
    }

    fn stream_info(id: &str, client_id: i32, name: &str) -> StreamInfo {
        StreamInfo {
            id: id.to_string(),
            client_id,
            name: name.to_string(),
            source: Some(StreamSource::Window),
            audio: true,
            bitrate: Some(2_500_000),
            accessibility: Some(StreamAccessibility::Public),
            transport: None,
            viewer_limit: Some(0),
            viewers: None,
        }
    }

    fn drain_stream_events(
        rx: &mut broadcast::Receiver<SessionEvent>,
    ) -> Vec<(Vec<StreamView>, Option<String>)> {
        let mut out = Vec::new();
        while let Ok(event) = rx.try_recv() {
            if let SessionEvent::Streams { streams, watching } = event {
                out.push((streams, watching));
            }
        }
        out
    }

    #[tokio::test]
    async fn pre_join_streamer_visible_when_snapshot_arrives_after_500ms_early_stream_first() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.init_stream_session(&client);

            // 模拟建连 500ms 超时时仅先提交了不完整的空快照，不能锁死后续补查。
            actor.commit_snapshot(
                vec![],
                vec![ClientView::from(client_info(1, 5, "Self"))],
                true,
            );
            let mut events = actor.events.subscribe();

            // 此时对方已在开播，Streams 在频道映射尚未到达前即缓存该流（不得丢弃）。
            actor.push_test_stream_event(StreamsEvent::Started(stream_info("s1", 2, "Screen")));
            assert!(drain_stream_events(&mut events).is_empty());

            // 晚于 500ms 才到齐的 channellistfinished 目录快照补齐了开播者频道与标志。
            actor.handle_directory_snapshot(DirectorySnapshot {
                channels: Vec::new(),
                clients: vec![
                    client_info(1, 0, "Self"),
                    ClientInfo {
                        is_streaming: Some(true),
                        ..client_info(2, 5, "Streamer")
                    },
                ],
                truncated: false,
            });

            let mut saw_snapshot_flag = false;
            let mut stream_updates = Vec::new();
            while let Ok(event) = events.try_recv() {
                match event {
                    SessionEvent::Snapshot { clients, .. } => {
                        let peer = clients.iter().find(|c| c.id == 2).expect("peer row");
                        assert!(peer.is_streaming);
                        saw_snapshot_flag = true;
                    }
                    SessionEvent::Streams { streams, watching } => {
                        stream_updates.push((streams, watching));
                    }
                    _ => {}
                }
            }
            assert!(saw_snapshot_flag);
            assert_eq!(
                stream_updates.last(),
                Some(&(
                    vec![crate::streams::stream_view(&stream_info("s1", 2, "Screen"))],
                    None
                ))
            );
        })
        .await;
    }

    #[tokio::test]
    async fn pre_join_streamer_visible_when_snapshot_arrives_after_500ms_snapshot_first() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.init_stream_session(&client);

            actor.commit_snapshot(
                vec![],
                vec![ClientView::from(client_info(1, 5, "Self"))],
                true,
            );
            let mut events = actor.events.subscribe();

            // 晚于 500ms 的目录快照先到达，随后 requeststreaminfo 返回 StreamsEvent::Started。
            actor.handle_directory_snapshot(DirectorySnapshot {
                channels: Vec::new(),
                clients: vec![
                    client_info(1, 0, "Self"),
                    ClientInfo {
                        is_streaming: Some(true),
                        ..client_info(2, 5, "Streamer")
                    },
                ],
                truncated: false,
            });
            assert!(drain_stream_events(&mut events).is_empty());

            actor.push_test_stream_event(StreamsEvent::Started(stream_info("s1", 2, "Screen")));
            let stream_updates = drain_stream_events(&mut events);
            assert_eq!(
                stream_updates,
                vec![(
                    vec![crate::streams::stream_view(&stream_info("s1", 2, "Screen"))],
                    None
                )]
            );
        })
        .await;
    }

    #[tokio::test]
    async fn switching_into_channel_with_existing_streamer_projects_cached_streams() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.subscribed_all_channels = true;
            actor.init_stream_session(&client);

            actor.handle_directory_snapshot(DirectorySnapshot {
                channels: Vec::new(),
                clients: vec![
                    client_info(1, 0, "Self"),
                    ClientInfo {
                        is_streaming: Some(true),
                        ..client_info(9, 8, "Ch8Streamer")
                    },
                    ClientInfo {
                        is_streaming: Some(true),
                        ..client_info(12, 9, "Ch9Streamer")
                    },
                ],
                truncated: false,
            });
            actor.push_test_stream_event(StreamsEvent::Started(stream_info("s-ch8", 9, "Ch8")));
            actor.push_test_stream_event(StreamsEvent::Started(stream_info("s-ch9", 12, "Ch9")));

            // 当前在频道 5，不应看到频道 8 / 频道 9 的流。
            assert!(actor.last_streams_state.0.is_empty());

            // 在频道 5 注册一个正在等待中的观看以验证切频道时会发 SelfMoved。
            if let Some(session) = &mut actor.stream_session {
                let (_tx, done) = watch::channel(false);
                session.watch = Some(ActiveWatch {
                    id: 77,
                    stream_id: "s-ch5".into(),
                    source_clid: 50,
                    phase: WatchPhase::Joining {
                        abort: AbortSignal::new(),
                        done,
                        settled_view: Rc::new(RefCell::new(None)),
                    },
                });
            }

            let mut events = actor.events.subscribe();
            actor
                .handle_signal(SessionSignal::ClientMoved {
                    epoch: actor.connection_epoch,
                    id: 1,
                    channel_id: 8,
                })
                .await;

            let mut ended = None;
            let mut projected = Vec::new();
            while let Ok(event) = events.try_recv() {
                match event {
                    SessionEvent::StreamEnded { stream_id, reason } => {
                        ended = Some((stream_id, reason));
                    }
                    SessionEvent::Streams { streams, watching } => {
                        projected.push((streams, watching));
                    }
                    _ => {}
                }
            }
            assert_eq!(ended, Some(("s-ch5".into(), StreamEndReason::SelfMoved)));
            assert_eq!(
                projected.last(),
                Some(&(
                    vec![crate::streams::stream_view(&stream_info("s-ch8", 9, "Ch8"))],
                    None
                ))
            );

            // 验证经 refresh_snapshot -> apply_self_channel 率先切换频道时的投影。
            actor.apply_self_channel(9, Some(4));
            let next = drain_stream_events(&mut events);
            assert_eq!(
                next.last(),
                Some(&(
                    vec![crate::streams::stream_view(&stream_info(
                        "s-ch9", 12, "Ch9"
                    ))],
                    None
                ))
            );
        })
        .await;
    }

    #[tokio::test]
    async fn switching_channel_after_subscribe_all_failure_handles_enter_and_stream_either_order() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.subscribed_all_channels = false;
            actor.init_stream_session(&client);

            actor
                .handle_signal(SessionSignal::ClientMoved {
                    epoch: actor.connection_epoch,
                    id: 1,
                    channel_id: 8,
                })
                .await;

            let mut events = actor.events.subscribe();
            // 顺序一：notifycliententerview (ClientJoined) 先于 notifystreaminfo 到达。
            actor
                .handle_signal(SessionSignal::ClientJoined {
                    epoch: actor.connection_epoch,
                    client: ClientView::from(ClientInfo {
                        is_streaming: Some(true),
                        ..client_info(9, 8, "Peer9")
                    }),
                })
                .await;
            actor.push_test_stream_event(StreamsEvent::Started(stream_info(
                "s-unsub-1",
                9,
                "Peer9Share",
            )));
            assert_eq!(
                drain_stream_events(&mut events).last(),
                Some(&(
                    vec![crate::streams::stream_view(&stream_info(
                        "s-unsub-1",
                        9,
                        "Peer9Share"
                    ))],
                    None
                ))
            );

            // 顺序二：notifystreaminfo 先于 notifycliententerview (ClientJoined) 到达。
            actor.push_test_stream_event(StreamsEvent::Started(stream_info(
                "s-unsub-2",
                10,
                "Peer10Share",
            )));
            assert!(drain_stream_events(&mut events).is_empty());

            actor
                .handle_signal(SessionSignal::ClientJoined {
                    epoch: actor.connection_epoch,
                    client: ClientView::from(ClientInfo {
                        is_streaming: Some(true),
                        ..client_info(10, 8, "Peer10")
                    }),
                })
                .await;
            assert_eq!(
                drain_stream_events(&mut events).last(),
                Some(&(
                    vec![
                        crate::streams::stream_view(&stream_info("s-unsub-1", 9, "Peer9Share")),
                        crate::streams::stream_view(&stream_info("s-unsub-2", 10, "Peer10Share")),
                    ],
                    None
                ))
            );
        })
        .await;
    }

    #[tokio::test]
    async fn peer_move_leave_unsupported_and_reset_cleanup() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.init_stream_session(&client);

            // 真实 Client 未携带 STREAM_P2P 时，join_stream 应直接拒绝。
            let err = actor
                .join_stream("missing".into(), 2)
                .expect_err("unsupported server should reject join_stream");
            assert!(matches!(err, SessionError::Stream(_)));

            actor.handle_directory_snapshot(DirectorySnapshot {
                channels: Vec::new(),
                clients: vec![
                    client_info(1, 0, "Self"),
                    ClientInfo {
                        is_streaming: Some(true),
                        ..client_info(2, 5, "Streamer")
                    },
                ],
                truncated: false,
            });
            actor.push_test_stream_event(StreamsEvent::Started(stream_info("s1", 2, "Screen")));
            assert_eq!(actor.last_streams_state.0.len(), 1);

            let mut events = actor.events.subscribe();
            // Unsupported 错误只记录一次 info 日志，不刷屏。
            for _ in 0..2 {
                actor.handle_streams_bus_event(StreamsEvent::Error(StreamError::Unsupported(
                    StreamsUnsupportedError {
                        version: "3.13.7".into(),
                        extensions: Vec::new(),
                    },
                )));
            }
            let unsupported_logs = std::iter::from_fn(|| events.try_recv().ok())
                .filter(|event| matches!(event, SessionEvent::Log { level, message } if level == "info" && message.contains("TS6")))
                .count();
            assert_eq!(unsupported_logs, 1);

            // 对端切走频道后，当前频道流目录立即清空。
            actor
                .handle_signal(SessionSignal::ClientMoved {
                    epoch: actor.connection_epoch,
                    id: 2,
                    channel_id: 99,
                })
                .await;
            assert!(actor.last_streams_state.0.is_empty());

            // 验证 WatchResolved(JoinDenied) 会映射为 StreamEndReason::Rejected。
            if let Some(session) = &mut actor.stream_session {
                let (_tx, done) = watch::channel(false);
                session.watch = Some(ActiveWatch {
                    id: 88,
                    stream_id: "s-denied".into(),
                    source_clid: 2,
                    phase: WatchPhase::Joining {
                        abort: AbortSignal::new(),
                        done,
                        settled_view: Rc::new(RefCell::new(None)),
                    },
                });
            }
            actor
                .handle_signal(SessionSignal::WatchResolved {
                    epoch: actor.connection_epoch,
                    stream_epoch: actor.stream_epoch,
                    watch_id: 88,
                    stream_id: "s-denied".into(),
                    outcome: Err(StreamError::JoinDenied(
                        tsclient_rs::stream::StreamJoinDeniedError {
                            stream_id: "s-denied".into(),
                            server_message: "busy".into(),
                        },
                    )),
                })
                .await;
            let ended_reasons: Vec<_> = std::iter::from_fn(|| events.try_recv().ok())
                .filter_map(|event| match event {
                    SessionEvent::StreamEnded { reason, .. } => Some(reason),
                    _ => None,
                })
                .collect();
            assert_eq!(ended_reasons, vec![StreamEndReason::Rejected]);

            // disconnect/reset_streams 释放 Streams 会话并清空状态。
            actor.reset_streams(StreamEndReason::Disconnected);
            assert!(actor.stream_session.is_none());
            assert!(actor.client_channels.is_empty());
        })
        .await;
    }

    #[tokio::test]
    async fn joining_cancel_awaits_graceful_cleanup_and_allows_immediate_rewatch() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.init_stream_session(&client);
            actor.handle_directory_snapshot(DirectorySnapshot {
                channels: Vec::new(),
                clients: vec![
                    client_info(1, 5, "Self"),
                    ClientInfo {
                        is_streaming: Some(true),
                        ..client_info(2, 5, "Streamer")
                    },
                ],
                truncated: false,
            });
            if let Some(session) = &mut actor.stream_session {
                session
                    .test_infos
                    .insert("s1".into(), stream_info("s1", 2, "Screen"));
            }

            let attempts = Rc::new(std::cell::Cell::new(0usize));
            let first_abort_observed = Rc::new(std::cell::Cell::new(false));
            let first_cleanup_finished = Rc::new(std::cell::Cell::new(false));
            let second_abort_observed = Rc::new(std::cell::Cell::new(false));
            let dropped_unexpectedly = Rc::new(std::cell::Cell::new(false));
            let (release_tx, release_rx) = oneshot::channel::<()>();
            let release_rx = Rc::new(RefCell::new(Some(release_rx)));

            struct CancelDropGuard(Rc<std::cell::Cell<bool>>, bool);
            impl Drop for CancelDropGuard {
                fn drop(&mut self) {
                    if !self.1 {
                        self.0.set(true);
                    }
                }
            }

            if let Some(session) = &mut actor.stream_session {
                let attempts = Rc::clone(&attempts);
                let first_abort_observed = Rc::clone(&first_abort_observed);
                let first_cleanup_finished = Rc::clone(&first_cleanup_finished);
                let second_abort_observed = Rc::clone(&second_abort_observed);
                let dropped_unexpectedly = Rc::clone(&dropped_unexpectedly);
                let release_rx = Rc::clone(&release_rx);
                session.test_watch_hook = Some(Rc::new(move |_stream_id, abort| {
                    let attempt = attempts.get() + 1;
                    attempts.set(attempt);
                    let first_abort_observed = Rc::clone(&first_abort_observed);
                    let first_cleanup_finished = Rc::clone(&first_cleanup_finished);
                    let second_abort_observed = Rc::clone(&second_abort_observed);
                    let dropped_unexpectedly = Rc::clone(&dropped_unexpectedly);
                    let release_rx = Rc::clone(&release_rx);
                    Box::pin(async move {
                        let mut guard = CancelDropGuard(dropped_unexpectedly, false);
                        abort.wait_for_abort().await;
                        if attempt == 1 {
                            first_abort_observed.set(true);
                            let rx = release_rx.borrow_mut().take();
                            if let Some(rx) = rx {
                                let _ = rx.await;
                            }
                            first_cleanup_finished.set(true);
                        } else {
                            second_abort_observed.set(true);
                        }
                        guard.1 = true;
                        Err(StreamError::Aborted)
                    })
                }));
            }

            // 第一次发起 watch 进入 Joining 阶段。
            actor.join_stream("s1".into(), 2).expect("first join");
            tokio::task::yield_now().await;
            assert_eq!(attempts.get(), 1);

            // 通过 LeaveStream 取消 Joining：Actor 立即返回不阻塞，且只触发 abort.abort() 而不强杀 Future。
            let (leave_tx, mut leave_rx) = oneshot::channel();
            actor
                .handle(SessionCommand::LeaveStream {
                    stream_id: "s1".into(),
                    reply: leave_tx,
                })
                .await;
            assert!(
                actor
                    .stream_session
                    .as_ref()
                    .is_some_and(|session| session.watch.is_none())
            );
            tokio::task::yield_now().await;
            assert!(first_abort_observed.get());
            assert!(!first_cleanup_finished.get());
            assert!(!dropped_unexpectedly.get());
            assert!(leave_rx.try_recv().is_err());

            // 前一次 watch 仍在收尾时立即重看同一流：能立刻受理并排队等待前次清理完成。
            actor
                .join_stream("s1".into(), 2)
                .expect("immediate rewatch should not hit already-watching");
            tokio::task::yield_now().await;
            assert_eq!(attempts.get(), 1);

            // 放行第一次 watch 的 is_remove=1 清理收尾后，第二次 watch 自动继续执行且 LeaveStream 回执完成。
            let _ = release_tx.send(());
            for _ in 0..6 {
                tokio::task::yield_now().await;
            }
            while let Ok(sig) = actor.signal_rx.try_recv() {
                actor.handle_signal(sig).await;
            }
            assert!(leave_rx.await.expect("leave reply").is_ok());
            assert!(first_cleanup_finished.get());
            assert_eq!(attempts.get(), 2);

            // 切频道触发 end_active_watch_best_effort 时同样优雅取消 Joining。
            actor.on_stream_self_channel_changed(5, 9);
            for _ in 0..4 {
                tokio::task::yield_now().await;
            }
            assert!(second_abort_observed.get());
            assert!(!dropped_unexpectedly.get());
        })
        .await;
    }

    #[tokio::test]
    async fn peer_moved_and_client_updated_refresh_missing_streams() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.init_stream_session(&client);
            if let Some(session) = &mut actor.stream_session {
                session
                    .test_infos
                    .insert("s3".into(), stream_info("s3", 3, "Existing"));
            }
            let mut events = actor.events.subscribe();
            let epoch = actor.connection_epoch;

            // 客户端 2 移入当前频道且 Streams 尚无其流信息时，补查 requeststreaminfo。
            actor
                .handle_signal(SessionSignal::ClientMoved {
                    epoch,
                    id: 2,
                    channel_id: 5,
                })
                .await;
            // 客户端 3 已有缓存流 "s3"，切入当前频道不应重复补查，且投影到当前频道流列表。
            actor
                .handle_signal(SessionSignal::ClientMoved {
                    epoch,
                    id: 3,
                    channel_id: 5,
                })
                .await;
            // 客户端 2 移入其他频道不应补查。
            actor
                .handle_signal(SessionSignal::ClientMoved {
                    epoch,
                    id: 2,
                    channel_id: 9,
                })
                .await;

            assert_eq!(
                actor
                    .stream_session
                    .as_ref()
                    .unwrap()
                    .test_refreshed_clids
                    .borrow()
                    .as_slice(),
                &[2]
            );
            assert_eq!(actor.last_streams_state.0.len(), 1);
            assert_eq!(actor.last_streams_state.0[0].id, "s3");

            // ClientUpdated 携带频道变更时应同步 client_channels、补查并刷新流视图。
            actor
                .handle_signal(SessionSignal::ClientUpdated {
                    epoch,
                    id: 2,
                    channel_id: 5,
                    input_muted: None,
                    output_muted: None,
                    away: None,
                    away_message: None,
                    server_groups: Vec::new(),
                })
                .await;
            assert_eq!(actor.client_channels.get(&2), Some(&5));
            assert_eq!(
                actor
                    .stream_session
                    .as_ref()
                    .unwrap()
                    .test_refreshed_clids
                    .borrow()
                    .as_slice(),
                &[2, 2]
            );

            actor
                .handle_signal(SessionSignal::ClientUpdated {
                    epoch,
                    id: 3,
                    channel_id: 8,
                    input_muted: None,
                    output_muted: None,
                    away: None,
                    away_message: None,
                    server_groups: Vec::new(),
                })
                .await;
            assert_eq!(actor.client_channels.get(&3), Some(&8));
            assert!(actor.last_streams_state.0.is_empty());
            assert!(drain_stream_events(&mut events).len() >= 2);
        })
        .await;
    }

    #[tokio::test]
    async fn stream_commands_do_not_block_actor_and_reject_stale_epochs() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.init_stream_session(&client);

            // StartScreenShare 同步返回，不阻塞 Actor 处理后续命令与事件。
            let (share_tx, share_rx) = oneshot::channel();
            actor
                .handle(SessionCommand::StartScreenShare {
                    name: "Screen".into(),
                    audio: true,
                    bitrate: 2_500_000,
                    viewer_limit: 0,
                    reply: share_tx,
                })
                .await;
            assert!(
                actor
                    .stream_session
                    .as_ref()
                    .is_some_and(|s| s.starting_publish.is_some())
            );

            let old_stream_epoch = actor.stream_epoch;
            let epoch = actor.connection_epoch;

            // 在开播结果回投前切频道：应立即推进 stream_epoch 并取消 starting_publish。
            actor.on_stream_self_channel_changed(5, 9);
            assert!(actor.stream_epoch != old_stream_epoch);
            assert!(
                actor
                    .stream_session
                    .as_ref()
                    .is_some_and(|s| s.starting_publish.is_none())
            );

            // 即使在异步命令等待期间，其他控制命令也可即时执行。
            let (mute_tx, mute_rx) = oneshot::channel();
            actor
                .handle(SessionCommand::SetMuted {
                    muted: true,
                    reply: mute_tx,
                })
                .await;
            assert!(mute_rx.await.expect("mute reply").is_ok());

            // 过期 stream_epoch 的异步回投不得污染新会话，并给调用方返回错误。
            let (cmd_tx, cmd_rx) = oneshot::channel();
            actor
                .handle_signal(SessionSignal::StreamCommandFinished {
                    epoch,
                    stream_epoch: old_stream_epoch,
                    require_matching_epoch: true,
                    outcome: Ok(()),
                    reply: cmd_tx,
                })
                .await;
            assert!(cmd_rx.await.expect("cmd reply").is_err());

            let (resp_tx, resp_rx) = oneshot::channel();
            actor
                .handle_signal(SessionSignal::StreamJoinResponseResolved(
                    StreamJoinResponse {
                        epoch,
                        stream_epoch: old_stream_epoch,
                        stream_id: "s1".into(),
                        viewer_clid: 2,
                        request_token: 1,
                        accept: true,
                        outcome: Ok(None),
                        reply: resp_tx,
                    },
                ))
                .await;
            assert!(resp_rx.await.expect("join response reply").is_err());

            // `require_matching_epoch: false` 的尽力收尾命令在同连接 epoch 下正常返回 Ok。
            let (leave_fin_tx, leave_fin_rx) = oneshot::channel();
            actor
                .handle_signal(SessionSignal::StreamCommandFinished {
                    epoch,
                    stream_epoch: old_stream_epoch,
                    require_matching_epoch: false,
                    outcome: Ok(()),
                    reply: leave_fin_tx,
                })
                .await;
            assert!(leave_fin_rx.await.expect("leave finish reply").is_ok());

            // 消化 StartScreenShareResolved 信号后，原调用应收到明确失败而非永久挂起。
            for _ in 0..4 {
                tokio::task::yield_now().await;
            }
            while let Ok(sig) = actor.signal_rx.try_recv() {
                if let SessionSignal::StartScreenShareResolved { .. } = sig {
                    actor.handle_signal(sig).await;
                }
            }
            assert!(share_rx.await.expect("share reply").is_err());
        })
        .await;
    }

    #[tokio::test]
    async fn client_joined_preserves_is_streaming() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.init_stream_session(&client);

            let mut events = actor.events.subscribe();
            let mut joined = ClientView::from(client_info(7, 5, "Streamer"));
            joined.is_streaming = true;
            actor
                .handle_signal(SessionSignal::ClientJoined {
                    epoch: actor.connection_epoch,
                    client: joined,
                })
                .await;

            assert_eq!(actor.client_channels.get(&7), Some(&5));
            let emitted = std::iter::from_fn(|| events.try_recv().ok())
                .find_map(|event| match event {
                    SessionEvent::ClientJoined(view) => Some(view),
                    _ => None,
                })
                .expect("expected ClientJoined event");
            assert_eq!(emitted.id, 7);
            assert!(emitted.is_streaming);
        })
        .await;
    }

    fn make_test_peer(stream_id: &str) -> (TestViewerPeer, mpsc::UnboundedSender<PeerEvent>) {
        let (tx, rx) = mpsc::unbounded_channel();
        let peer = TestViewerPeer {
            stream_id: stream_id.to_string(),
            closed: Arc::new(std::sync::atomic::AtomicBool::new(false)),
            events_rx: Arc::new(std::sync::Mutex::new(Some(rx))),
            sent_candidates: Arc::new(std::sync::Mutex::new(Vec::new())),
            send_candidate_error: Arc::new(std::sync::Mutex::new(None)),
        };
        (peer, tx)
    }

    fn make_test_request(
        viewer_clid: i32,
        accept_result: Result<TestViewerPeer, StreamError>,
    ) -> (JoinRequestHandle, TestJoinRequest) {
        let (_tx, rx) = mpsc::unbounded_channel();
        let req = TestJoinRequest {
            viewer_clid,
            state: Arc::new(std::sync::Mutex::new(JoinRequestState::Pending)),
            events_rx: Arc::new(std::sync::Mutex::new(Some(rx))),
            accept_result: Arc::new(std::sync::Mutex::new(Some(accept_result))),
            deny_result: Arc::new(std::sync::Mutex::new(Some(Ok(())))),
            offers_seen: Arc::new(std::sync::Mutex::new(Vec::new())),
        };
        (JoinRequestHandle::Test(req.clone()), req)
    }

    async fn pump_actor_signals(actor: &mut Actor) {
        for _ in 0..6 {
            tokio::task::yield_now().await;
            while let Ok(sig) = actor.signal_rx.try_recv() {
                actor.handle_signal(sig).await;
            }
        }
    }

    fn drain_all_events(rx: &mut broadcast::Receiver<SessionEvent>) -> Vec<SessionEvent> {
        std::iter::from_fn(|| rx.try_recv().ok()).collect()
    }

    #[tokio::test]
    async fn rejoining_accepted_viewer_without_left_cleans_old_viewer_and_ignores_late_closed() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.init_stream_session(&client);

            let (_pub_tx, pub_rx) = mpsc::unbounded_channel::<PublishedStreamEvent>();
            let pub_task = tokio::task::spawn_local(async move {
                let mut rx = pub_rx;
                let _ = rx.recv().await;
            });
            actor.stream_session.as_mut().unwrap().publish = Some(ActivePublish {
                stream: PublishedStreamHandle::Test {
                    id: "pub-reconn".into(),
                },
                requests: HashMap::new(),
                viewers: HashMap::new(),
                _task: PumpGuard(pub_task),
            });

            // 1. 观众 42 首次请求并被接受，成为已接受观众（进入 publish.viewers）。
            let (peer1, peer1_tx) = make_test_peer("pub-reconn");
            let (req1, _req1_handle) = make_test_request(42, Ok(peer1.clone()));
            actor.handle_published_stream_request("pub-reconn".into(), req1);

            let (reply_tx1, reply_rx1) = oneshot::channel();
            actor.respond_stream_join_request(
                42,
                true,
                "v=0\r\nm=video 9\r\na=ice-ufrag:offer1".into(),
                reply_tx1,
            );
            pump_actor_signals(&mut actor).await;
            assert!(reply_rx1.await.unwrap().is_ok());

            let old_peer_token = actor
                .stream_session
                .as_ref()
                .and_then(|s| s.publish.as_ref())
                .and_then(|p| p.viewers.get(&42))
                .expect("accepted viewer 1")
                .token;

            let mut events = actor.events.subscribe();

            // 2. 模拟旧 PeerEvent::Closed 还在队列里尚未处理时，同 viewer_clid 直接重新发起 JoinRequest。
            let (peer2, peer2_tx) = make_test_peer("pub-reconn");
            let (req2, req2_handle) = make_test_request(42, Ok(peer2.clone()));
            actor.handle_published_stream_request("pub-reconn".into(), req2);

            // 旧 AcceptedViewer 必须已被移除，新请求已注册。
            {
                let publish = actor
                    .stream_session
                    .as_ref()
                    .and_then(|s| s.publish.as_ref())
                    .unwrap();
                assert!(!publish.viewers.contains_key(&42));
                assert!(publish.requests.contains_key(&42));
            }

            // 验证事件顺序：先 StreamViewerLeft 清理旧会话，再 StreamViewerJoinRequested 重建新连接。
            let immediate_events = drain_all_events(&mut events);
            let left_pos = immediate_events
                .iter()
                .position(|ev| {
                    matches!(
                        ev,
                        SessionEvent::StreamViewerLeft { stream_id, viewer_clid: 42 }
                            if stream_id == "pub-reconn"
                    )
                })
                .expect("expected StreamViewerLeft before StreamViewerJoinRequested");
            let req_pos = immediate_events
                .iter()
                .position(|ev| {
                    matches!(
                        ev,
                        SessionEvent::StreamViewerJoinRequested { stream_id, viewer_clid: 42 }
                            if stream_id == "pub-reconn"
                    )
                })
                .expect("expected StreamViewerJoinRequested");
            assert!(left_pos < req_pos);
            assert!(immediate_events.iter().any(|ev| {
                matches!(
                    ev,
                    SessionEvent::Log { level, message }
                        if level == "info"
                            && message.contains("notifyjoinstreamrequest")
                            && message.contains("viewer_clid=42")
                )
            }));

            // 3. 随后旧 PeerEvent::Closed（无论来自通道还是直接进入队列）到达：不得误删新请求。
            let _ = peer1_tx.send(PeerEvent::Closed(tsclient_rs::stream::PeerClosed {
                cause: tsclient_rs::stream::PeerCloseCause::Left,
                reason: None,
            }));
            actor
                .handle_signal(SessionSignal::PublisherPeerEvent {
                    epoch: actor.connection_epoch,
                    stream_epoch: actor.stream_epoch,
                    stream_id: "pub-reconn".into(),
                    viewer_clid: 42,
                    token: old_peer_token,
                    event: PeerEvent::Closed(tsclient_rs::stream::PeerClosed {
                        cause: tsclient_rs::stream::PeerCloseCause::Left,
                        reason: None,
                    }),
                })
                .await;
            pump_actor_signals(&mut actor).await;

            assert!(
                actor
                    .stream_session
                    .as_ref()
                    .and_then(|s| s.publish.as_ref())
                    .is_some_and(|p| p.requests.contains_key(&42))
            );
            assert!(
                !drain_all_events(&mut events)
                    .iter()
                    .any(|ev| matches!(ev, SessionEvent::StreamViewerLeft { .. }))
            );

            // 4. 接受新请求，生成新的 AcceptedViewer。
            let (reply_tx2, reply_rx2) = oneshot::channel();
            actor.respond_stream_join_request(
                42,
                true,
                "v=0\r\nm=video 9\r\na=ice-ufrag:offer2".into(),
                reply_tx2,
            );
            pump_actor_signals(&mut actor).await;
            assert!(reply_rx2.await.unwrap().is_ok());
            assert_eq!(
                req2_handle.offers_seen.lock().unwrap().as_slice(),
                &["v=0\r\nm=video 9\r\na=ice-ufrag:offer2"]
            );

            let new_peer_token = actor
                .stream_session
                .as_ref()
                .and_then(|s| s.publish.as_ref())
                .and_then(|p| p.viewers.get(&42))
                .expect("accepted viewer 2")
                .token;
            assert_ne!(new_peer_token, old_peer_token);

            // 5. 迟到的旧 PeerEvent::Closed 与迟到的总线 ViewerLeft 不得误删新 AcceptedViewer。
            actor
                .handle_signal(SessionSignal::PublisherPeerEvent {
                    epoch: actor.connection_epoch,
                    stream_epoch: actor.stream_epoch,
                    stream_id: "pub-reconn".into(),
                    viewer_clid: 42,
                    token: old_peer_token,
                    event: PeerEvent::Closed(tsclient_rs::stream::PeerClosed {
                        cause: tsclient_rs::stream::PeerCloseCause::Left,
                        reason: None,
                    }),
                })
                .await;
            actor.handle_streams_bus_event(StreamsEvent::ViewerLeft(
                tsclient_rs::stream::StreamViewerEvent {
                    info: stream_info("pub-reconn", 1, "Screen"),
                    client_id: 42,
                },
            ));
            let late_events = drain_all_events(&mut events);
            assert!(
                !late_events
                    .iter()
                    .any(|ev| matches!(ev, SessionEvent::StreamViewerLeft { .. }))
            );
            assert!(
                actor
                    .stream_session
                    .as_ref()
                    .and_then(|s| s.publish.as_ref())
                    .is_some_and(|p| p.viewers.contains_key(&42))
            );

            // 6. 新会话的 Answer / ICE 双向信令正常流转到新 Peer。
            peer2_tx
                .send(PeerEvent::Answer(
                    "v=0\r\nm=video 9\r\na=ice-ufrag:answer2".into(),
                ))
                .unwrap();
            peer2_tx
                .send(PeerEvent::Candidate(IceCandidate {
                    candidate: "candidate:1 1 udp 2122260223 192.0.2.2 50000 typ host".into(),
                    sdp_mid: Some("0".into()),
                    sdp_m_line_index: Some(0),
                }))
                .unwrap();
            pump_actor_signals(&mut actor).await;

            let (ice_tx, ice_rx) = oneshot::channel();
            actor.send_publisher_ice_candidate(
                42,
                "candidate:2 1 udp 2122260223 198.51.100.3 50001 typ srflx".into(),
                Some("0".into()),
                Some(0),
                ice_tx,
            );
            pump_actor_signals(&mut actor).await;
            assert!(ice_rx.await.unwrap().is_ok());

            let signal_events = drain_all_events(&mut events);
            assert!(signal_events.iter().any(|ev| {
                matches!(
                    ev,
                    SessionEvent::PublisherSignalReceived {
                        viewer_clid: 42,
                        signal: PublisherSignal::Answer { .. },
                        ..
                    }
                )
            }));
            assert!(signal_events.iter().any(|ev| {
                matches!(
                    ev,
                    SessionEvent::PublisherSignalReceived {
                        viewer_clid: 42,
                        signal: PublisherSignal::IceCandidate { .. },
                        ..
                    }
                )
            }));
            assert!(peer1.sent_candidates.lock().unwrap().is_empty());
            assert_eq!(peer2.sent_candidates.lock().unwrap().len(), 1);
        })
        .await;
    }

    #[tokio::test]
    async fn publisher_signaling_logs_info_and_warn_without_full_sdp() {
        run_local(async {
            let mut actor = audio_actor();
            let client = make_client();
            client.mark_connected();
            actor.client = Some(Arc::clone(&client));
            actor.self_client_id = Some(1);
            actor.self_channel_id = 5;
            actor.init_stream_session(&client);

            let (_pub_tx, pub_rx) = mpsc::unbounded_channel::<PublishedStreamEvent>();
            let pub_task = tokio::task::spawn_local(async move {
                let mut rx = pub_rx;
                let _ = rx.recv().await;
            });
            actor.stream_session.as_mut().unwrap().publish = Some(ActivePublish {
                stream: PublishedStreamHandle::Test {
                    id: "pub-logs".into(),
                },
                requests: HashMap::new(),
                viewers: HashMap::new(),
                _task: PumpGuard(pub_task),
            });

            let mut events = actor.events.subscribe();
            let mut logs: Vec<(String, String)> = Vec::new();
            let collect_logs = |events: &mut broadcast::Receiver<SessionEvent>,
                                logs: &mut Vec<(String, String)>| {
                while let Ok(ev) = events.try_recv() {
                    if let SessionEvent::Log { level, message } = ev {
                        logs.push((level, message));
                    }
                }
            };

            // 1. notifyjoinstreamrequest + respondjoinstreamrequest 成功路径
            let (peer_ok, peer_ok_tx) = make_test_peer("pub-logs");
            let (req_ok, _req_ok_handle) = make_test_request(77, Ok(peer_ok.clone()));
            actor.handle_published_stream_request("pub-logs".into(), req_ok);
            collect_logs(&mut events, &mut logs);

            let offer_sdp = "v=0\r\nm=video 9\r\na=ice-ufrag:secret-offer-ufrag";
            let (resp_tx, resp_rx) = oneshot::channel();
            actor.respond_stream_join_request(77, true, offer_sdp.into(), resp_tx);
            pump_actor_signals(&mut actor).await;
            assert!(resp_rx.await.unwrap().is_ok());
            collect_logs(&mut events, &mut logs);

            // 2. 收到 Answer 与 iceCandidate + 发送 iceCandidate 成功与失败
            let answer_sdp = "v=0\r\nm=video 9\r\na=ice-ufrag:secret-answer-ufrag";
            peer_ok_tx
                .send(PeerEvent::Answer(answer_sdp.into()))
                .unwrap();
            peer_ok_tx
                .send(PeerEvent::Candidate(IceCandidate {
                    candidate: "candidate:recv 1 udp 1 192.0.2.1 5000 typ host".into(),
                    sdp_mid: Some("0".into()),
                    sdp_m_line_index: Some(0),
                }))
                .unwrap();
            pump_actor_signals(&mut actor).await;
            collect_logs(&mut events, &mut logs);

            let (ice_ok_tx, ice_ok_rx) = oneshot::channel();
            actor.send_publisher_ice_candidate(
                77,
                "candidate:send-ok 1 udp 1 192.0.2.2 5001 typ host".into(),
                Some("0".into()),
                Some(0),
                ice_ok_tx,
            );
            pump_actor_signals(&mut actor).await;
            assert!(ice_ok_rx.await.unwrap().is_ok());
            collect_logs(&mut events, &mut logs);

            *peer_ok.send_candidate_error.lock().unwrap() = Some(StreamError::NotConnected);
            let (ice_err_tx, ice_err_rx) = oneshot::channel();
            actor.send_publisher_ice_candidate(
                77,
                "candidate:send-err 1 udp 1 192.0.2.3 5002 typ host".into(),
                Some("0".into()),
                Some(0),
                ice_err_tx,
            );
            pump_actor_signals(&mut actor).await;
            assert!(ice_err_rx.await.unwrap().is_err());
            collect_logs(&mut events, &mut logs);

            // 3. respondjoinstreamrequest 失败路径（预校验失败 + 异步命令失败）
            let (missing_tx, missing_rx) = oneshot::channel();
            actor.respond_stream_join_request(99, true, "v=0\r\n".into(), missing_tx);
            assert!(missing_rx.await.unwrap().is_err());
            collect_logs(&mut events, &mut logs);

            let (req_fail, _) = make_test_request(88, Err(StreamError::NotConnected));
            actor.handle_published_stream_request("pub-logs".into(), req_fail);
            let (fail_tx, fail_rx) = oneshot::channel();
            actor.respond_stream_join_request(88, true, offer_sdp.into(), fail_tx);
            pump_actor_signals(&mut actor).await;
            assert!(fail_rx.await.unwrap().is_err());
            collect_logs(&mut events, &mut logs);

            // 4. 观看端 Answer 发送失败也记录 warn 日志且不打印完整 SDP
            let (view_ans_tx, view_ans_rx) = oneshot::channel();
            actor.send_stream_answer("missing-stream".into(), 55, answer_sdp.into(), view_ans_tx);
            assert!(view_ans_rx.await.unwrap().is_err());
            collect_logs(&mut events, &mut logs);

            // 任何日志都不得打印完整 SDP
            for (_, msg) in &logs {
                assert!(
                    !msg.contains("secret-offer-ufrag") && !msg.contains("secret-answer-ufrag"),
                    "log leaked full SDP: {msg}"
                );
            }

            assert!(logs.iter().any(|(lvl, msg)| {
                lvl == "info"
                    && msg.contains("notifyjoinstreamrequest")
                    && msg.contains("viewer_clid=77")
            }));
            assert!(logs.iter().any(|(lvl, msg)| {
                lvl == "info"
                    && msg.contains("respondjoinstreamrequest")
                    && msg.contains("viewer_clid=77")
            }));
            assert!(logs.iter().any(|(lvl, msg)| {
                lvl == "info" && msg.contains("Answer") && msg.contains("viewer_clid=77")
            }));
            assert!(logs.iter().any(|(lvl, msg)| {
                lvl == "info" && msg.contains("iceCandidate") && msg.contains("viewer_clid=77")
            }));
            assert!(logs.iter().any(|(lvl, msg)| {
                lvl == "warn" && msg.contains("iceCandidate") && msg.contains("viewer_clid=77")
            }));
            assert!(logs.iter().any(|(lvl, msg)| {
                lvl == "warn"
                    && msg.contains("respondjoinstreamrequest")
                    && msg.contains("viewer_clid=99")
            }));
            assert!(logs.iter().any(|(lvl, msg)| {
                lvl == "warn"
                    && msg.contains("respondjoinstreamrequest")
                    && msg.contains("viewer_clid=88")
            }));
            assert!(logs.iter().any(|(lvl, msg)| {
                lvl == "warn" && msg.contains("Answer") && msg.contains("target_clid=55")
            }));
        })
        .await;
    }
}
