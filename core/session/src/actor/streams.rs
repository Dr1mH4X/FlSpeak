//! Actor 与 `tsclient_rs::stream::Streams` 的桥接层。
//!
//! 连接期由单个 [`ActiveStreamSession`] 持有 `Streams`、当前观看句柄与本地推流句柄；
//! `Streams` 以全服维度缓存流信息，Actor 只负责按当前所在频道投影 `SessionView.streams`
//! 并将推拉流指令与信令经异步任务转发给 UI。

use std::collections::HashMap;

use tokio::task::JoinHandle;
use tsclient_rs::AbortSignal;
use tsclient_rs::stream::{
    JoinRequest, JoinRequestCloseCause, JoinRequestEvent, PeerEvent, PublishedStream,
    PublishedStreamEvent, StreamError, StreamInfo, StreamTransport, StreamView as TsStreamView,
    Streams, StreamsEvent, StreamsOptions, ViewerPeer, WatchOptions,
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

struct ActiveWatch {
    id: u64,
    stream_id: String,
    source_clid: i32,
    phase: WatchPhase,
}

enum WatchPhase {
    Joining {
        abort: AbortSignal,
        _task: PumpGuard,
    },
    Active {
        view: TsStreamView,
        _task: PumpGuard,
    },
}

struct PendingViewerRequest {
    request: JoinRequest,
    _task: PumpGuard,
}

struct AcceptedViewer {
    peer: ViewerPeer,
    _task: PumpGuard,
}

struct ActivePublish {
    stream: PublishedStream,
    requests: HashMap<i32, PendingViewerRequest>,
    viewers: HashMap<i32, AcceptedViewer>,
    _task: PumpGuard,
}

/// 单次连接生命周期内的屏幕共享会话状态。
pub(super) struct ActiveStreamSession {
    streams: Streams,
    watch: Option<ActiveWatch>,
    publish: Option<ActivePublish>,
    unsupported_logged: bool,
    _bus_task: PumpGuard,
    #[cfg(test)]
    test_infos: std::collections::BTreeMap<String, StreamInfo>,
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
}

fn spawn_best_effort_leave(view: TsStreamView, events: broadcast::Sender<SessionEvent>) {
    tokio::task::spawn_local(async move {
        if let Err(err) = view.leave().await
            && !err.is_not_connected()
        {
            emit(
                &events,
                SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("退出屏幕共享 {} 失败: {err}", view.stream_id()),
                },
            );
        }
    });
}

fn spawn_best_effort_stop(stream: PublishedStream, events: broadcast::Sender<SessionEvent>) {
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

impl Actor {
    /// 为新建立的 `Client` 挂接 `tsclient_rs::stream::Streams` 并开始转发流事件。
    pub(super) fn init_stream_session(&mut self, client: &Client) {
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
            publish: None,
            unsupported_logged: false,
            _bus_task: PumpGuard(bus_task),
            #[cfg(test)]
            test_infos: std::collections::BTreeMap::new(),
        });
        self.sync_streams_view();
    }

    /// 断线或重连前回收全部屏幕共享会话并清理缓存的成员频道。
    pub(super) fn reset_streams(&mut self, reason: StreamEndReason) {
        self.client_channels.clear();
        if let Some(mut session) = self.stream_session.take() {
            if let Some(watch) = session.watch.take() {
                if let WatchPhase::Joining { abort, .. } = &watch.phase {
                    abort.abort();
                }
                self.emit(SessionEvent::StreamEnded {
                    stream_id: watch.stream_id,
                    reason,
                });
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
            self.end_active_watch_best_effort(StreamEndReason::SelfMoved);
            if let Some(publish) = self
                .stream_session
                .as_mut()
                .and_then(|session| session.publish.take())
            {
                let events = self.events.clone();
                let stream = publish.stream.clone();
                drop(publish);
                self.emit(SessionEvent::ScreenShareStopped);
                spawn_best_effort_stop(stream, events);
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
        match watch.phase {
            WatchPhase::Joining { abort, _task } => {
                drop(_task);
                abort.abort();
            }
            WatchPhase::Active { view, _task } => {
                drop(_task);
                spawn_best_effort_leave(view, self.events.clone());
            }
        }
        self.emit(SessionEvent::StreamEnded { stream_id, reason });
    }

    pub(super) async fn join_stream(
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

        let streams = session.streams.clone();
        let previous = self
            .stream_session
            .as_mut()
            .and_then(|session| session.watch.take());
        if let Some(prev) = previous {
            self.emit(SessionEvent::StreamEnded {
                stream_id: prev.stream_id.clone(),
                reason: StreamEndReason::Left,
            });
            match prev.phase {
                WatchPhase::Joining { abort, _task } => {
                    drop(_task);
                    abort.abort();
                }
                WatchPhase::Active { view, _task } => {
                    drop(_task);
                    if let Err(err) = view.leave().await
                        && !err.is_not_connected()
                    {
                        self.emit(SessionEvent::Log {
                            level: "warn".into(),
                            message: format!("退出屏幕共享 {} 失败: {err}", prev.stream_id),
                        });
                    }
                }
            }
        }

        self.next_watch_id = self.next_watch_id.wrapping_add(1);
        let watch_id = self.next_watch_id;
        let abort = AbortSignal::new();
        let task_abort = abort.clone();
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let target_stream_id = stream_id.clone();
        let join_task = tokio::task::spawn_local(async move {
            let outcome = streams
                .watch(
                    &target_stream_id,
                    WatchOptions {
                        message: String::new(),
                        timeout_ms: None,
                        abort: Some(task_abort),
                    },
                )
                .await;
            let _ = signals.send(SessionSignal::WatchResolved {
                epoch,
                watch_id,
                stream_id: target_stream_id,
                outcome,
            });
        });

        let Some(session) = self.stream_session.as_mut() else {
            return Err(SessionError::NotConnected);
        };
        session.watch = Some(ActiveWatch {
            id: watch_id,
            stream_id,
            source_clid,
            phase: WatchPhase::Joining {
                abort,
                _task: PumpGuard(join_task),
            },
        });
        self.sync_streams_view();
        Ok(())
    }

    /// 先清理本地观看状态再通知服务端退出，命令失败也不会残留悬空观看。
    pub(super) async fn leave_stream(&mut self, stream_id: String) -> Result<(), SessionError> {
        let Some(session) = self.stream_session.as_mut() else {
            return Err(SessionError::Stream("没有在观看这路屏幕共享".into()));
        };
        if session
            .watch
            .as_ref()
            .is_none_or(|watch| watch.stream_id != stream_id)
        {
            return Err(SessionError::Stream("没有在观看这路屏幕共享".into()));
        }
        let watch = session.watch.take().unwrap();
        self.sync_streams_view();
        self.emit(SessionEvent::StreamEnded {
            stream_id: watch.stream_id,
            reason: StreamEndReason::Left,
        });
        match watch.phase {
            WatchPhase::Joining { abort, _task } => {
                drop(_task);
                abort.abort();
                Ok(())
            }
            WatchPhase::Active { view, _task } => {
                drop(_task);
                view.leave().await.map_err(stream_error)
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

    pub(super) async fn send_stream_answer(
        &self,
        stream_id: String,
        target_clid: i32,
        sdp: String,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let view = self.watched_active_view(&stream_id, target_clid)?;
        view.answer(&sdp).await.map_err(stream_error)
    }

    pub(super) async fn send_stream_ice_candidate(
        &self,
        stream_id: String,
        target_clid: i32,
        sdp: String,
        mid: Option<String>,
        m_line: Option<i32>,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let view = self.watched_active_view(&stream_id, target_clid)?;
        let cand = ice_candidate(sdp, mid, m_line)?;
        view.send_candidate(&cand).await.map_err(stream_error)
    }

    pub(super) async fn start_screen_share(
        &mut self,
        name: String,
        audio: bool,
        bitrate: u32,
        viewer_limit: u32,
    ) -> Result<(), SessionError> {
        self.connected()?;
        if self.self_channel_id == 0 {
            return Err(SessionError::NotInChannel);
        }
        let session = self
            .stream_session
            .as_ref()
            .ok_or(SessionError::NotConnected)?;
        if session.publish.is_some() {
            return Err(SessionError::Stream("当前已在推流或正在启动推流".into()));
        }
        let options = publish_options(&name, audio, bitrate, viewer_limit)?;
        let streams = session.streams.clone();
        let published = streams.publish(options).await.map_err(stream_error)?;

        let stream_id = published.id().to_string();
        let Some(session) = self.stream_session.as_mut() else {
            let _ = published.stop(0).await;
            return Err(SessionError::NotConnected);
        };
        if session.publish.is_some() {
            let _ = published.stop(0).await;
            return Err(SessionError::Stream("当前已在推流或正在启动推流".into()));
        }

        let mut sub = published.subscribe();
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let pub_stream_id = stream_id.clone();
        let pub_task = tokio::task::spawn_local(async move {
            while let Some(event) = sub.recv().await {
                if signals
                    .send(SessionSignal::PublishedStreamEvent {
                        epoch,
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
            stream: published,
            requests: HashMap::new(),
            viewers: HashMap::new(),
            _task: PumpGuard(pub_task),
        });
        self.emit(SessionEvent::ScreenSharePublished { stream_id });
        Ok(())
    }

    pub(super) async fn stop_screen_share(&mut self) -> Result<(), SessionError> {
        let Some(publish) = self
            .stream_session
            .as_mut()
            .and_then(|session| session.publish.take())
        else {
            return Ok(());
        };
        let stream = publish.stream.clone();
        drop(publish);
        self.emit(SessionEvent::ScreenShareStopped);
        if self.client.is_some() {
            stream.stop(0).await.map_err(stream_error)?;
        }
        Ok(())
    }

    pub(super) async fn respond_stream_join_request(
        &mut self,
        viewer_clid: i32,
        accept: bool,
        offer_sdp: String,
    ) -> Result<(), SessionError> {
        self.connected()?;
        if accept && offer_sdp.trim().is_empty() {
            return Err(SessionError::Stream(
                "接受观看请求必须提供 SDP Offer".into(),
            ));
        }
        let pending = {
            let publish = self
                .stream_session
                .as_mut()
                .and_then(|session| session.publish.as_mut())
                .ok_or_else(|| SessionError::Stream("当前没有活动的屏幕共享推流".into()))?;
            publish
                .requests
                .remove(&viewer_clid)
                .ok_or_else(|| SessionError::Stream("该客户端未请求观看屏幕共享".into()))?
        };
        drop(pending._task);
        self.emit(SessionEvent::Log {
            level: "debug".into(),
            message: format!(
                "发送 respondjoinstreamrequest: 观众={viewer_clid}, accept={accept}, offer_sdp_len={}",
                offer_sdp.len()
            ),
        });
        if !accept {
            return pending.request.deny("").await.map_err(stream_error);
        }

        let peer = pending
            .request
            .accept(&offer_sdp, "")
            .await
            .map_err(stream_error)?;
        let Some(publish) = self
            .stream_session
            .as_mut()
            .and_then(|session| session.publish.as_mut())
            .filter(|publish| publish.stream.id() == peer.stream_id())
        else {
            let _ = peer.close().await;
            return Ok(());
        };
        let mut sub = peer.subscribe();
        let signals = self.signals.clone();
        let epoch = self.connection_epoch;
        let stream_id = peer.stream_id().to_string();
        let peer_task = tokio::task::spawn_local(async move {
            while let Some(event) = sub.recv().await {
                if signals
                    .send(SessionSignal::PublisherPeerEvent {
                        epoch,
                        stream_id: stream_id.clone(),
                        viewer_clid,
                        event,
                    })
                    .is_err()
                {
                    break;
                }
            }
        });
        publish.viewers.insert(
            viewer_clid,
            AcceptedViewer {
                peer,
                _task: PumpGuard(peer_task),
            },
        );
        Ok(())
    }

    pub(super) async fn send_publisher_ice_candidate(
        &self,
        viewer_clid: i32,
        sdp: String,
        mid: Option<String>,
        m_line: Option<i32>,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let publish = self
            .stream_session
            .as_ref()
            .and_then(|session| session.publish.as_ref())
            .ok_or_else(|| SessionError::Stream("当前没有活动的屏幕共享推流".into()))?;
        let peer = match publish.viewers.get(&viewer_clid) {
            Some(accepted) => accepted.peer.clone(),
            None if publish.requests.contains_key(&viewer_clid) => {
                return Err(SessionError::Stream(
                    "观众尚未完成加入应答，不能发送信令".into(),
                ));
            }
            None => {
                return Err(SessionError::Stream("信令目标不是当前推流的观众".into()));
            }
        };
        let cand = ice_candidate(sdp, mid, m_line)?;
        peer.send_candidate(&cand).await.map_err(stream_error)
    }

    pub(super) async fn kick_stream_viewer(
        &mut self,
        viewer_clid: i32,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let publish = self
            .stream_session
            .as_mut()
            .and_then(|session| session.publish.as_mut())
            .ok_or_else(|| SessionError::Stream("当前没有活动的屏幕共享推流".into()))?;
        let stream_id = publish.stream.id().to_string();
        if let Some(accepted) = publish.viewers.remove(&viewer_clid) {
            drop(accepted._task);
            self.emit(SessionEvent::StreamViewerLeft {
                stream_id,
                viewer_clid,
            });
            return accepted.peer.close().await.map_err(stream_error);
        }
        if let Some(pending) = publish.requests.remove(&viewer_clid) {
            drop(pending._task);
            self.emit(SessionEvent::StreamViewerLeft {
                stream_id,
                viewer_clid,
            });
            return pending.request.deny("").await.map_err(stream_error);
        }
        Err(SessionError::Stream("目标客户端不是当前推流的观众".into()))
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
                    let removed = publish.requests.remove(&ev.client_id).is_some()
                        | publish.viewers.remove(&ev.client_id).is_some();
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
            if let Ok(view) = outcome {
                spawn_best_effort_leave(view, self.events.clone());
            }
            return;
        }

        match outcome {
            Ok(view) => {
                let mut sub = view.subscribe();
                let signals = self.signals.clone();
                let epoch = self.connection_epoch;
                let view_stream_id = view.stream_id().to_string();
                let source_client_id = view.client_id();
                let sdp = view.offer().to_string();
                let peer_task = tokio::task::spawn_local(async move {
                    while let Some(event) = sub.recv().await {
                        if signals
                            .send(SessionSignal::ViewerPeerEvent {
                                epoch,
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
        let is_current = self
            .stream_session
            .as_ref()
            .and_then(|session| session.publish.as_ref())
            .is_some_and(|publish| publish.stream.id() == stream_id);
        if !is_current {
            return;
        }

        match event {
            PublishedStreamEvent::Request(request) => {
                let viewer_clid = request.viewer().client_id;
                let mut sub = request.subscribe();
                let signals = self.signals.clone();
                let epoch = self.connection_epoch;
                let req_stream_id = stream_id.clone();
                let req_task = tokio::task::spawn_local(async move {
                    if let Some(JoinRequestEvent::Closed { cause }) = sub.recv().await {
                        let _ = signals.send(SessionSignal::JoinRequestClosed {
                            epoch,
                            stream_id: req_stream_id,
                            viewer_clid,
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
                            request,
                            _task: PumpGuard(req_task),
                        },
                    );
                    self.emit(SessionEvent::StreamViewerJoinRequested {
                        stream_id,
                        viewer_clid,
                    });
                }
            }
            PublishedStreamEvent::Ended(_) => {
                if let Some(session) = self.stream_session.as_mut() {
                    session.publish = None;
                }
                self.emit(SessionEvent::ScreenShareStopped);
            }
        }
    }

    pub(super) fn handle_join_request_closed(
        &mut self,
        stream_id: String,
        viewer_clid: i32,
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
        if publish.requests.remove(&viewer_clid).is_some() {
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
        if !publish.viewers.contains_key(&viewer_clid) {
            return;
        }
        match event {
            PeerEvent::Answer(sdp) => {
                self.emit(SessionEvent::PublisherSignalReceived {
                    stream_id,
                    viewer_clid,
                    signal: PublisherSignal::Answer { sdp },
                });
            }
            PeerEvent::Candidate(cand) => {
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
            PeerEvent::Closed(_) => {
                if publish.viewers.remove(&viewer_clid).is_some() {
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
                        is_streaming: true,
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
                        is_streaming: true,
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
                        is_streaming: true,
                        ..client_info(9, 8, "Ch8Streamer")
                    },
                    ClientInfo {
                        is_streaming: true,
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
                session.watch = Some(ActiveWatch {
                    id: 77,
                    stream_id: "s-ch5".into(),
                    source_clid: 50,
                    phase: WatchPhase::Joining {
                        abort: AbortSignal::new(),
                        _task: PumpGuard(tokio::task::spawn_local(async {})),
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
                        is_streaming: true,
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
                        is_streaming: true,
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
                .await
                .expect_err("unsupported server should reject join_stream");
            assert!(matches!(err, SessionError::Stream(_)));

            actor.handle_directory_snapshot(DirectorySnapshot {
                channels: Vec::new(),
                clients: vec![
                    client_info(1, 0, "Self"),
                    ClientInfo {
                        is_streaming: true,
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
                session.watch = Some(ActiveWatch {
                    id: 88,
                    stream_id: "s-denied".into(),
                    source_clid: 2,
                    phase: WatchPhase::Joining {
                        abort: AbortSignal::new(),
                        _task: PumpGuard(tokio::task::spawn_local(async {})),
                    },
                });
            }
            actor
                .handle_signal(SessionSignal::WatchResolved {
                    epoch: actor.connection_epoch,
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
}
