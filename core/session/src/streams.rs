//! TS6 屏幕共享观看端与推流端：当前频道的流目录、观看状态机与本地推流状态机。
//!
//! TeamSpeak 服务器只转交信令，媒体由 Flutter 侧的 WebRTC 点对点收发。这里不碰
//! 网络：actor 把原始通知喂进来，拿回要广播的 [`SessionEvent`]；下行命令发出前
//! 先经这里校验，Dart 不能对未加入的流、非来源客户端或未登记的观众发信令。
//!
//! 流目录与本地推流都只属于一个频道（[`StreamCoordinator::channel`]）。自己换频道
//! 或断线时整张目录与本地推流一并作废，由 actor 在新频道里重新发现。

use std::collections::{BTreeMap, HashMap};

use serde_json::{Map, Value};

use crate::{SessionError, SessionEvent};

/// 频道里一路可观看的屏幕共享。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StreamView {
    pub id: String,
    /// 推流者的客户端 id；加入与信令都以它为目标。
    pub client_id: i32,
    pub name: String,
    pub has_audio: bool,
}

/// 正在观看的流为什么结束。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StreamEndReason {
    /// 推流者停止了共享。
    SourceStopped,
    /// 推流者离开了服务器。
    SourceLeft,
    /// 推流者去了别的频道。
    SourceMoved,
    /// 自己换了频道。
    SelfMoved,
    /// 连接断开。
    Disconnected,
    /// 被推流者或服务器移出观看。
    Removed,
    /// 推流者拒绝了加入请求。
    Rejected,
    /// 本地主动离开。
    Left,
}

/// 本地推流中单个观看者的协商状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViewerPeerState {
    Requested,
    Accepted,
}

/// 本地屏幕共享推流三态状态机。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum LocalPublishState {
    #[default]
    Idle,
    Starting {
        name: String,
        has_audio: bool,
    },
    Active {
        stream_id: String,
        name: String,
        has_audio: bool,
        viewers: HashMap<i32, ViewerPeerState>,
    },
}

/// 观看端发给本地推流端的 WebRTC 信令。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PublisherSignal {
    Answer {
        sdp: String,
    },
    IceCandidate {
        sdp: String,
        mid: Option<String>,
        m_line: Option<i32>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Watching {
    stream_id: String,
    source_clid: i32,
}

#[derive(Debug, Default)]
pub(crate) struct StreamCoordinator {
    channel_id: u64,
    streams: BTreeMap<String, StreamView>,
    watching: Option<Watching>,
    publish: LocalPublishState,
    orphan_streams: Vec<String>,
}

pub(crate) type StreamParams<const N: usize> = [(&'static str, String); N];

/// 只有这些通知会被 actor 转进来。
pub(crate) fn is_stream_notification(name: &str) -> bool {
    matches!(
        name,
        "notifystreamstarted"
            | "notifystreaminfo"
            | "notifystreamstopped"
            | "notifystreamclientleft"
            | "notifyjoinstreamrequest"
            | "notifyrespondjoinstreamrequest"
            | "notifystreamsignaling"
    )
}

impl StreamCoordinator {
    /// 目录所属的频道；0 表示还没同步过。
    pub(crate) fn channel(&self) -> u64 {
        self.channel_id
    }

    /// 正在观看的流与推流者。
    pub(crate) fn watching(&self) -> Option<(&str, i32)> {
        self.watching
            .as_ref()
            .map(|w| (w.stream_id.as_str(), w.source_clid))
    }

    /// 本地推流状态。
    #[cfg(test)]
    pub(crate) fn publish_state(&self) -> &LocalPublishState {
        &self.publish
    }

    /// 正在推流的服务器 `stream_id`（仅 `Active` 态有值）。
    pub(crate) fn published_stream_id(&self) -> Option<&str> {
        match &self.publish {
            LocalPublishState::Active { stream_id, .. } => Some(stream_id.as_str()),
            LocalPublishState::Idle | LocalPublishState::Starting { .. } => None,
        }
    }

    /// 取出需要自动执行 `stopstream` 清理的孤儿流 id 列表。
    pub(crate) fn take_orphan_streams(&mut self) -> Vec<String> {
        std::mem::take(&mut self.orphan_streams)
    }

    /// 作废整张目录并切到 `channel_id`。正在观看的流以 `reason` 结束，本地推流一并重置。
    pub(crate) fn reset(&mut self, channel_id: u64, reason: StreamEndReason) -> Vec<SessionEvent> {
        self.channel_id = channel_id;
        let mut out = Vec::new();
        let ended = self.end_watching(reason, &mut out);
        let had_streams = !self.streams.is_empty();
        self.streams.clear();
        if ended || had_streams {
            out.push(self.list_event());
        }
        if !matches!(self.publish, LocalPublishState::Idle) {
            self.publish = LocalPublishState::Idle;
            out.push(SessionEvent::ScreenShareStopped);
        }
        self.orphan_streams.clear();
        out
    }

    /// 远端客户端离开服务器。
    pub(crate) fn client_left(&mut self, clid: i32) -> Vec<SessionEvent> {
        self.drop_source(clid, StreamEndReason::SourceLeft)
    }

    /// 其他客户端换了频道；推流者离开本频道时它的流作废，观众离开本频道时从推流观众表移除。
    pub(crate) fn client_moved(&mut self, clid: i32, channel_id: u64) -> Vec<SessionEvent> {
        if channel_id == self.channel_id {
            return Vec::new();
        }
        self.drop_source(clid, StreamEndReason::SourceMoved)
    }

    /// 处理一行流通知。`source_channel` 查推流者当前所在频道，未知时返回 `None`。
    pub(crate) fn notification(
        &mut self,
        name: &str,
        params: &HashMap<String, String>,
        self_clid: Option<i32>,
        source_channel: impl Fn(i32) -> Option<u64>,
    ) -> Vec<SessionEvent> {
        let Some(stream_id) = param(params, "id").or_else(|| param(params, "stream_id")) else {
            return Vec::new();
        };
        let stream_id = stream_id.to_string();
        let mut out = Vec::new();
        match name {
            "notifystreamstarted" | "notifystreaminfo" => {
                let Some(clid) = parse_clid(params) else {
                    return out;
                };
                if Some(clid) == self_clid {
                    match &mut self.publish {
                        LocalPublishState::Starting { name, has_audio } => {
                            let name = std::mem::take(name);
                            let has_audio = *has_audio;
                            self.publish = LocalPublishState::Active {
                                stream_id: stream_id.clone(),
                                name,
                                has_audio,
                                viewers: HashMap::new(),
                            };
                            out.push(SessionEvent::ScreenSharePublished { stream_id });
                        }
                        LocalPublishState::Active {
                            stream_id: active_id,
                            ..
                        } if active_id == &stream_id => {}
                        LocalPublishState::Idle | LocalPublishState::Active { .. } => {
                            self.orphan_streams.push(stream_id);
                        }
                    }
                    return out;
                }
                if self.channel_id == 0 {
                    return out;
                }
                if source_channel(clid).is_some_and(|channel| channel != self.channel_id) {
                    return out;
                }
                let view = StreamView {
                    id: stream_id.clone(),
                    client_id: clid,
                    name: param(params, "name").unwrap_or_default().to_string(),
                    has_audio: param(params, "audio") == Some("1"),
                };
                if self.streams.get(&stream_id) != Some(&view) {
                    self.streams.insert(stream_id, view);
                    out.push(self.list_event());
                }
            }
            "notifyjoinstreamrequest" => {
                let Some(viewer_clid) = parse_clid(params) else {
                    return out;
                };
                if Some(viewer_clid) == self_clid {
                    return out;
                }
                if let LocalPublishState::Active {
                    stream_id: active_id,
                    viewers,
                    ..
                } = &mut self.publish
                    && active_id == &stream_id
                {
                    viewers.insert(viewer_clid, ViewerPeerState::Requested);
                    out.push(SessionEvent::StreamViewerJoinRequested {
                        stream_id,
                        viewer_clid,
                    });
                }
            }
            "notifystreamstopped" => {
                if matches!(
                    &self.publish,
                    LocalPublishState::Active {
                        stream_id: active_id,
                        ..
                    } if active_id == &stream_id
                ) {
                    self.publish = LocalPublishState::Idle;
                    out.push(SessionEvent::ScreenShareStopped);
                    return out;
                }
                let removed = self.streams.remove(&stream_id).is_some();
                let ended =
                    self.end_watching_if(&stream_id, StreamEndReason::SourceStopped, &mut out);
                if removed || ended {
                    out.push(self.list_event());
                }
            }
            "notifystreamclientleft" => {
                if let LocalPublishState::Active {
                    stream_id: active_id,
                    viewers,
                    ..
                } = &mut self.publish
                    && active_id == &stream_id
                {
                    if let Some(viewer_clid) = parse_clid(params)
                        && viewers.remove(&viewer_clid).is_some()
                    {
                        out.push(SessionEvent::StreamViewerLeft {
                            stream_id,
                            viewer_clid,
                        });
                    }
                    return out;
                }
                if self_clid.is_some()
                    && parse_clid(params) == self_clid
                    && self.end_watching_if(&stream_id, StreamEndReason::Removed, &mut out)
                {
                    out.push(self.list_event());
                }
            }
            "notifyrespondjoinstreamrequest" => {
                let Some(source_clid) = self.watched_source(&stream_id) else {
                    return out;
                };
                if matches!(param(params, "decision"), Some("0" | "false")) {
                    if self.end_watching_if(&stream_id, StreamEndReason::Rejected, &mut out) {
                        out.push(self.list_event());
                    }
                    return out;
                }
                if let Some(sdp) = param(params, "offer") {
                    out.push(SessionEvent::StreamOffer {
                        stream_id,
                        source_client_id: source_clid,
                        sdp: sdp.to_string(),
                    });
                }
            }
            "notifystreamsignaling" => {
                if let LocalPublishState::Active {
                    stream_id: active_id,
                    viewers,
                    ..
                } = &self.publish
                    && active_id == &stream_id
                {
                    let Some(viewer_clid) =
                        parse_clid(params).filter(|clid| viewers.contains_key(clid))
                    else {
                        return out;
                    };
                    let raw = param(params, "json").or_else(|| param(params, "data"));
                    let Some((cmd, args)) = raw.and_then(parse_signal) else {
                        return out;
                    };
                    if let Some(signal) = publisher_signal_kind(&cmd, &args) {
                        out.push(SessionEvent::PublisherSignalReceived {
                            stream_id,
                            viewer_clid,
                            signal,
                        });
                    }
                    return out;
                }
                let Some(source_clid) = self.watched_source(&stream_id) else {
                    return out;
                };
                let raw = param(params, "json").or_else(|| param(params, "data"));
                let Some((cmd, args)) = raw.and_then(parse_signal) else {
                    return out;
                };
                match signal_kind(&cmd, &args) {
                    Some(Signal::Offer(sdp)) => out.push(SessionEvent::StreamOffer {
                        stream_id,
                        source_client_id: source_clid,
                        sdp,
                    }),
                    Some(Signal::Ice { sdp, mid, m_line }) => {
                        out.push(SessionEvent::StreamIceCandidate {
                            stream_id,
                            source_client_id: source_clid,
                            sdp,
                            mid,
                            m_line,
                        })
                    }
                    Some(Signal::Rejected)
                        if self.end_watching_if(
                            &stream_id,
                            StreamEndReason::Rejected,
                            &mut out,
                        ) =>
                    {
                        out.push(self.list_event());
                    }
                    _ => {}
                }
            }
            _ => {}
        }
        out
    }

    /// 登记本地推流意图并生成 `setupstream` 参数；非 `Idle` 时拒绝。
    pub(crate) fn start_publish(
        &mut self,
        name: &str,
        has_audio: bool,
        bitrate: u32,
        viewer_limit: u32,
    ) -> Result<StreamParams<7>, SessionError> {
        if !matches!(self.publish, LocalPublishState::Idle) {
            return Err(SessionError::Stream("当前已在推流或正在启动推流".into()));
        }
        self.publish = LocalPublishState::Starting {
            name: name.to_string(),
            has_audio,
        };
        Ok(setup_stream_request(name, has_audio, bitrate, viewer_limit))
    }

    /// `setupstream` 命令发送失败时将状态从 `Starting` 回滚为 `Idle`。
    pub(crate) fn rollback_publish(&mut self) {
        if matches!(self.publish, LocalPublishState::Starting { .. }) {
            self.publish = LocalPublishState::Idle;
        }
    }

    /// 停止本地推流。返回需要发送 `stopstream` 的 `stream_id`（仅原状态为 `Active` 时有值）与待广播事件。
    pub(crate) fn stop_publish(&mut self) -> (Option<String>, Vec<SessionEvent>) {
        match std::mem::replace(&mut self.publish, LocalPublishState::Idle) {
            LocalPublishState::Idle => (None, Vec::new()),
            LocalPublishState::Starting { .. } => (None, vec![SessionEvent::ScreenShareStopped]),
            LocalPublishState::Active { stream_id, .. } => {
                (Some(stream_id), vec![SessionEvent::ScreenShareStopped])
            }
        }
    }

    /// 接受或拒绝观众的加入请求，并生成 `respondjoinstreamrequest` 参数。
    pub(crate) fn respond_viewer_join(
        &mut self,
        viewer_clid: i32,
        accept: bool,
        offer_sdp: &str,
    ) -> Result<StreamParams<5>, SessionError> {
        let LocalPublishState::Active {
            stream_id, viewers, ..
        } = &mut self.publish
        else {
            return Err(SessionError::Stream("当前没有活动的屏幕共享推流".into()));
        };
        if !viewers.contains_key(&viewer_clid) {
            return Err(SessionError::Stream("该客户端未请求观看屏幕共享".into()));
        }
        if accept {
            if offer_sdp.is_empty() {
                return Err(SessionError::Stream(
                    "接受观看请求必须提供 SDP Offer".into(),
                ));
            }
            viewers.insert(viewer_clid, ViewerPeerState::Accepted);
            Ok(respond_join_request(
                stream_id,
                viewer_clid,
                true,
                offer_sdp,
            ))
        } else {
            viewers.remove(&viewer_clid);
            Ok(respond_join_request(stream_id, viewer_clid, false, ""))
        }
    }

    /// 校验推流端向观众发送 ICE 候选的目标，返回当前活动推流的 `stream_id`。
    /// 仅当观众已通过 `respond_viewer_join` 接受（`ViewerPeerState::Accepted`）后才允许发信令。
    pub(crate) fn check_publisher_signal_target(
        &self,
        viewer_clid: i32,
    ) -> Result<&str, SessionError> {
        match &self.publish {
            LocalPublishState::Active {
                stream_id, viewers, ..
            } if matches!(viewers.get(&viewer_clid), Some(ViewerPeerState::Accepted)) => {
                Ok(stream_id.as_str())
            }
            LocalPublishState::Active { viewers, .. } if viewers.contains_key(&viewer_clid) => Err(
                SessionError::Stream("观众尚未完成加入应答，不能发送信令".into()),
            ),
            LocalPublishState::Active { .. } => {
                Err(SessionError::Stream("信令目标不是当前推流的观众".into()))
            }
            LocalPublishState::Idle | LocalPublishState::Starting { .. } => {
                Err(SessionError::Stream("当前没有活动的屏幕共享推流".into()))
            }
        }
    }

    /// 当 `respondjoinstreamrequest` 或下行信令在服务器端因观众已退出而失败时移除该观众。
    pub(crate) fn remove_viewer(&mut self, viewer_clid: i32) {
        if let LocalPublishState::Active { viewers, .. } = &mut self.publish {
            viewers.remove(&viewer_clid);
        }
    }

    /// 将指定观众移出当前推流，返回 `removeclientfromstream` 参数与 `StreamViewerLeft` 事件。
    pub(crate) fn kick_viewer(
        &mut self,
        viewer_clid: i32,
    ) -> Result<(StreamParams<3>, SessionEvent), SessionError> {
        let LocalPublishState::Active {
            stream_id, viewers, ..
        } = &mut self.publish
        else {
            return Err(SessionError::Stream("当前没有活动的屏幕共享推流".into()));
        };
        if viewers.remove(&viewer_clid).is_none() {
            return Err(SessionError::Stream("目标客户端不是当前推流的观众".into()));
        }
        let params = remove_client_request(stream_id, viewer_clid);
        let event = SessionEvent::StreamViewerLeft {
            stream_id: stream_id.clone(),
            viewer_clid,
        };
        Ok((params, event))
    }

    /// 校验并登记观看意图。返回需要先离开的旧流 id（不同于本次目标时）。
    pub(crate) fn begin_join(
        &mut self,
        stream_id: &str,
        source_clid: i32,
    ) -> Result<(Option<String>, Vec<SessionEvent>), SessionError> {
        let stream = self
            .streams
            .get(stream_id)
            .ok_or_else(|| SessionError::Stream("当前频道没有这路屏幕共享".into()))?;
        if stream.client_id != source_clid {
            return Err(SessionError::Stream("推流者与屏幕共享不匹配".into()));
        }
        let next = Watching {
            stream_id: stream_id.to_string(),
            source_clid,
        };
        if self.watching.as_ref() == Some(&next) {
            return Ok((None, Vec::new()));
        }
        let mut out = Vec::new();
        let previous = self.watching.as_ref().map(|w| w.stream_id.clone());
        self.end_watching(StreamEndReason::Left, &mut out);
        self.watching = Some(next);
        out.push(self.list_event());
        Ok((previous, out))
    }

    /// 加入请求失败时撤回观看意图；期间已经换成别的流时不动。
    pub(crate) fn abandon_join(&mut self, stream_id: &str) -> Vec<SessionEvent> {
        if self.watched_source(stream_id).is_none() {
            return Vec::new();
        }
        self.watching = None;
        vec![self.list_event()]
    }

    /// 本地主动离开。只能离开正在观看的那一路。
    pub(crate) fn leave(&mut self, stream_id: &str) -> Result<Vec<SessionEvent>, SessionError> {
        let mut out = Vec::new();
        if !self.end_watching_if(stream_id, StreamEndReason::Left, &mut out) {
            return Err(SessionError::Stream("没有在观看这路屏幕共享".into()));
        }
        out.push(self.list_event());
        Ok(out)
    }

    /// 下行信令只能发给正在观看的流的推流者。
    pub(crate) fn check_signal_target(
        &self,
        stream_id: &str,
        target_clid: i32,
    ) -> Result<(), SessionError> {
        match self.watched_source(stream_id) {
            Some(source) if source == target_clid => Ok(()),
            Some(_) => Err(SessionError::Stream("信令目标不是这路共享的推流者".into())),
            None => Err(SessionError::Stream("没有在观看这路屏幕共享".into())),
        }
    }

    fn drop_source(&mut self, clid: i32, reason: StreamEndReason) -> Vec<SessionEvent> {
        let before = self.streams.len();
        self.streams.retain(|_, stream| stream.client_id != clid);
        let mut out = Vec::new();
        let ended = self
            .watching
            .as_ref()
            .is_some_and(|w| w.source_clid == clid)
            && self.end_watching(reason, &mut out);
        if ended || self.streams.len() != before {
            out.push(self.list_event());
        }
        if let LocalPublishState::Active {
            stream_id, viewers, ..
        } = &mut self.publish
            && viewers.remove(&clid).is_some()
        {
            out.push(SessionEvent::StreamViewerLeft {
                stream_id: stream_id.clone(),
                viewer_clid: clid,
            });
        }
        out
    }

    fn watched_source(&self, stream_id: &str) -> Option<i32> {
        self.watching
            .as_ref()
            .filter(|w| w.stream_id == stream_id)
            .map(|w| w.source_clid)
    }

    fn end_watching_if(
        &mut self,
        stream_id: &str,
        reason: StreamEndReason,
        out: &mut Vec<SessionEvent>,
    ) -> bool {
        self.watched_source(stream_id).is_some() && self.end_watching(reason, out)
    }

    fn end_watching(&mut self, reason: StreamEndReason, out: &mut Vec<SessionEvent>) -> bool {
        let Some(watching) = self.watching.take() else {
            return false;
        };
        out.push(SessionEvent::StreamEnded {
            stream_id: watching.stream_id,
            reason,
        });
        true
    }

    fn list_event(&self) -> SessionEvent {
        SessionEvent::Streams {
            streams: self.streams.values().cloned().collect(),
            watching: self.watching.as_ref().map(|w| w.stream_id.clone()),
        }
    }
}

/// `setupstream`：向服务器注册本地屏幕共享流。
pub(crate) fn setup_stream_request(
    name: &str,
    audio: bool,
    bitrate: u32,
    viewer_limit: u32,
) -> [(&'static str, String); 7] {
    [
        ("name", name.to_string()),
        ("type", "3".into()),
        ("bitrate", bitrate.to_string()),
        ("accessibility", "1".into()),
        ("mode", "1".into()),
        ("viewer_limit", viewer_limit.to_string()),
        ("audio", if audio { "1" } else { "0" }.into()),
    ]
}

/// `stopstream`：停止服务器上的本地屏幕共享流。
pub(crate) fn stop_stream_request(stream_id: &str) -> [(&'static str, String); 2] {
    [("id", stream_id.to_string()), ("reason", "1".into())]
}

/// `respondjoinstreamrequest`：推流端回复观众的加入请求（附带 SDP Offer 或拒绝）。
pub(crate) fn respond_join_request(
    stream_id: &str,
    viewer_clid: i32,
    accept: bool,
    offer_sdp: &str,
) -> [(&'static str, String); 5] {
    [
        ("id", stream_id.to_string()),
        ("clid", viewer_clid.to_string()),
        ("msg", String::new()),
        (
            "offer",
            if accept {
                offer_sdp.to_string()
            } else {
                String::new()
            },
        ),
        ("decision", if accept { "1" } else { "0" }.into()),
    ]
}

/// `removeclientfromstream`：把指定客户端从流里移除（观众自己离开或推流端踢出观众）。
pub(crate) fn remove_client_request(stream_id: &str, clid: i32) -> [(&'static str, String); 3] {
    [
        ("id", stream_id.to_string()),
        ("clid", clid.to_string()),
        ("reason", "1".into()),
    ]
}

/// `joinstreamrequest`：向推流者申请观看。
pub(crate) fn join_request(stream_id: &str, source_clid: i32) -> [(&'static str, String); 7] {
    [
        ("id", stream_id.to_string()),
        ("clid", source_clid.to_string()),
        ("msg", String::new()),
        ("is_remove", "0".into()),
        ("muted", "0".into()),
        ("volume", "0".into()),
        ("hidden", "0".into()),
    ]
}

/// `removeclientfromstream`：把自己从流里移除。
pub(crate) fn leave_request(stream_id: &str, self_clid: i32) -> [(&'static str, String); 3] {
    remove_client_request(stream_id, self_clid)
}

/// `streamsignaling` 的 SDP Answer 载荷。
pub(crate) fn answer_payload(sdp: &str) -> String {
    serde_json::json!({ "cmd": "answer", "args": { "answer": sdp } }).to_string()
}

/// `streamsignaling` 的 ICE 候选载荷；`mid`/`mLine` 缺省时不写。
pub(crate) fn ice_payload(sdp: &str, mid: Option<&str>, m_line: Option<i32>) -> String {
    let mut args = Map::new();
    args.insert("sdp".into(), Value::from(sdp));
    if let Some(mid) = mid {
        args.insert("mid".into(), Value::from(mid));
    }
    if let Some(m_line) = m_line {
        args.insert("mLine".into(), Value::from(m_line));
    }
    serde_json::json!({ "cmd": "iceCandidate", "args": args }).to_string()
}

enum Signal {
    Offer(String),
    Ice {
        sdp: String,
        mid: Option<String>,
        m_line: Option<i32>,
    },
    Rejected,
}

fn param<'a>(params: &'a HashMap<String, String>, key: &str) -> Option<&'a str> {
    params
        .get(key)
        .map(String::as_str)
        .filter(|value| !value.is_empty())
}

fn parse_clid(params: &HashMap<String, String>) -> Option<i32> {
    param(params, "clid")?
        .parse::<i32>()
        .ok()
        .filter(|clid| *clid > 0)
}

fn parse_signal(raw: &str) -> Option<(String, Map<String, Value>)> {
    let Value::Object(mut root) = serde_json::from_str::<Value>(raw).ok()? else {
        return None;
    };
    let Value::String(cmd) = root.remove("cmd")? else {
        return None;
    };
    let Value::Object(args) = root.remove("args")? else {
        return None;
    };
    Some((cmd, args))
}

fn string_arg(args: &Map<String, Value>, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| args.get(*key).and_then(Value::as_str))
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn signal_kind(cmd: &str, args: &Map<String, Value>) -> Option<Signal> {
    match cmd {
        // 推流端接受加入请求后，首个 SDP 包在 joinResponse 里。
        "joinResponse" => {
            let rejected = matches!(args.get("decision"), Some(Value::Bool(false)))
                || args.get("decision").and_then(Value::as_i64) == Some(0)
                || args.get("decision").and_then(Value::as_str) == Some("0");
            if rejected {
                return Some(Signal::Rejected);
            }
            string_arg(args, &["offer", "sdp"]).map(Signal::Offer)
        }
        "offer" | "reconnectOffer" => string_arg(args, &["offer", "sdp"]).map(Signal::Offer),
        "iceCandidate" => Some(Signal::Ice {
            sdp: string_arg(args, &["sdp", "candidate"])?,
            mid: args.get("mid").and_then(Value::as_str).map(str::to_string),
            m_line: args
                .get("mLine")
                .and_then(Value::as_i64)
                .and_then(|value| i32::try_from(value).ok()),
        }),
        _ => None,
    }
}

fn publisher_signal_kind(cmd: &str, args: &Map<String, Value>) -> Option<PublisherSignal> {
    match cmd {
        "answer" => string_arg(args, &["answer", "sdp"]).map(|sdp| PublisherSignal::Answer { sdp }),
        "iceCandidate" => Some(PublisherSignal::IceCandidate {
            sdp: string_arg(args, &["sdp", "candidate"])?,
            mid: args.get("mid").and_then(Value::as_str).map(str::to_string),
            m_line: args
                .get("mLine")
                .and_then(Value::as_i64)
                .and_then(|value| i32::try_from(value).ok()),
        }),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CHANNEL: u64 = 7;
    const SELF: i32 = 1;
    const SOURCE: i32 = 42;

    fn params(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    fn in_channel(_: i32) -> Option<u64> {
        Some(CHANNEL)
    }

    fn started(coordinator: &mut StreamCoordinator) -> Vec<SessionEvent> {
        coordinator.notification(
            "notifystreamstarted",
            &params(&[
                ("id", "s1"),
                ("clid", "42"),
                ("name", "Desk"),
                ("audio", "1"),
            ]),
            Some(SELF),
            in_channel,
        )
    }

    fn watching_stream() -> StreamCoordinator {
        let mut coordinator = StreamCoordinator::default();
        coordinator.reset(CHANNEL, StreamEndReason::SelfMoved);
        started(&mut coordinator);
        coordinator.begin_join("s1", SOURCE).unwrap();
        coordinator
    }

    fn ended(events: &[SessionEvent]) -> Option<StreamEndReason> {
        events.iter().find_map(|event| match event {
            SessionEvent::StreamEnded { reason, .. } => Some(*reason),
            _ => None,
        })
    }

    #[test]
    fn started_and_info_populate_the_channel_list_once() {
        let mut coordinator = StreamCoordinator::default();
        coordinator.reset(CHANNEL, StreamEndReason::SelfMoved);
        let events = started(&mut coordinator);
        assert!(matches!(
            events.as_slice(),
            [SessionEvent::Streams { streams, watching: None }]
                if streams == &[StreamView { id: "s1".into(), client_id: SOURCE, name: "Desk".into(), has_audio: true }]
        ));
        let repeat = coordinator.notification(
            "notifystreaminfo",
            &params(&[
                ("stream_id", "s1"),
                ("clid", "42"),
                ("name", "Desk"),
                ("audio", "1"),
            ]),
            Some(SELF),
            in_channel,
        );
        assert!(repeat.is_empty());
    }

    #[test]
    fn foreign_channel_own_and_unsynced_streams_are_ignored() {
        let mut coordinator = StreamCoordinator::default();
        assert!(started(&mut coordinator).is_empty(), "未同步频道");
        coordinator.reset(CHANNEL, StreamEndReason::SelfMoved);
        let other = coordinator.notification(
            "notifystreamstarted",
            &params(&[("id", "s1"), ("clid", "42")]),
            Some(SELF),
            |_| Some(CHANNEL + 1),
        );
        assert!(other.is_empty());
        let own = coordinator.notification(
            "notifystreamstarted",
            &params(&[("id", "s2"), ("clid", "1")]),
            Some(SELF),
            in_channel,
        );
        assert!(own.is_empty());
    }

    #[test]
    fn join_requires_a_listed_stream_and_matching_source() {
        let mut coordinator = StreamCoordinator::default();
        coordinator.reset(CHANNEL, StreamEndReason::SelfMoved);
        assert!(coordinator.begin_join("s1", SOURCE).is_err());
        started(&mut coordinator);
        assert!(coordinator.begin_join("s1", SOURCE + 1).is_err());
        let (previous, events) = coordinator.begin_join("s1", SOURCE).unwrap();
        assert!(previous.is_none());
        assert!(
            matches!(events.as_slice(), [SessionEvent::Streams { watching: Some(id), .. }] if id == "s1")
        );
        assert_eq!(coordinator.watching(), Some(("s1", SOURCE)));
    }

    #[test]
    fn offer_and_ice_are_forwarded_only_for_the_watched_stream() {
        let mut coordinator = StreamCoordinator::default();
        coordinator.reset(CHANNEL, StreamEndReason::SelfMoved);
        started(&mut coordinator);
        let offer = params(&[("id", "s1"), ("offer", "v=0 sdp")]);
        assert!(
            coordinator
                .notification(
                    "notifyrespondjoinstreamrequest",
                    &offer,
                    Some(SELF),
                    in_channel
                )
                .is_empty(),
            "未加入时丢弃"
        );
        coordinator.begin_join("s1", SOURCE).unwrap();
        let events = coordinator.notification(
            "notifyrespondjoinstreamrequest",
            &offer,
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            events.as_slice(),
            [SessionEvent::StreamOffer { stream_id, source_client_id: SOURCE, sdp }]
                if stream_id == "s1" && sdp == "v=0 sdp"
        ));

        let ice = params(&[
            ("id", "s1"),
            ("clid", "42"),
            (
                "json",
                r#"{"cmd":"iceCandidate","args":{"sdp":"candidate:1","mid":"0","mLine":0}}"#,
            ),
        ]);
        let events =
            coordinator.notification("notifystreamsignaling", &ice, Some(SELF), in_channel);
        assert!(matches!(
            events.as_slice(),
            [SessionEvent::StreamIceCandidate { sdp, mid: Some(mid), m_line: Some(0), .. }]
                if sdp == "candidate:1" && mid == "0"
        ));
    }

    #[test]
    fn join_response_signal_carries_offer_or_rejection() {
        let mut coordinator = watching_stream();
        let accepted = params(&[
            ("id", "s1"),
            (
                "json",
                r#"{"cmd":"joinResponse","args":{"decision":true,"offer":"v=0"}}"#,
            ),
        ]);
        let events =
            coordinator.notification("notifystreamsignaling", &accepted, Some(SELF), in_channel);
        assert!(
            matches!(events.as_slice(), [SessionEvent::StreamOffer { sdp, .. }] if sdp == "v=0")
        );

        let rejected = params(&[
            ("id", "s1"),
            (
                "json",
                r#"{"cmd":"joinResponse","args":{"decision":false}}"#,
            ),
        ]);
        let events =
            coordinator.notification("notifystreamsignaling", &rejected, Some(SELF), in_channel);
        assert_eq!(ended(&events), Some(StreamEndReason::Rejected));
        assert_eq!(coordinator.watching(), None);
    }

    #[test]
    fn malformed_or_unknown_signaling_is_dropped() {
        let mut coordinator = watching_stream();
        for json in [
            "not json",
            r#"{"cmd":"answer","args":{"answer":"x"}}"#,
            r#"{"cmd":"offer"}"#,
        ] {
            let events = coordinator.notification(
                "notifystreamsignaling",
                &params(&[("id", "s1"), ("json", json)]),
                Some(SELF),
                in_channel,
            );
            assert!(events.is_empty(), "{json}");
        }
    }

    #[test]
    fn source_stop_leave_move_and_removal_end_the_watch() {
        let mut coordinator = watching_stream();
        let events = coordinator.notification(
            "notifystreamstopped",
            &params(&[("id", "s1")]),
            Some(SELF),
            in_channel,
        );
        assert_eq!(ended(&events), Some(StreamEndReason::SourceStopped));
        assert!(
            matches!(events.last(), Some(SessionEvent::Streams { streams, watching: None }) if streams.is_empty())
        );

        let mut coordinator = watching_stream();
        assert_eq!(
            ended(&coordinator.client_left(SOURCE)),
            Some(StreamEndReason::SourceLeft)
        );

        let mut coordinator = watching_stream();
        assert!(coordinator.client_moved(SOURCE, CHANNEL).is_empty());
        assert_eq!(
            ended(&coordinator.client_moved(SOURCE, CHANNEL + 1)),
            Some(StreamEndReason::SourceMoved)
        );

        let mut coordinator = watching_stream();
        let other_viewer = coordinator.notification(
            "notifystreamclientleft",
            &params(&[("id", "s1"), ("clid", "9")]),
            Some(SELF),
            in_channel,
        );
        assert!(other_viewer.is_empty());
        let events = coordinator.notification(
            "notifystreamclientleft",
            &params(&[("id", "s1"), ("clid", "1")]),
            Some(SELF),
            in_channel,
        );
        assert_eq!(ended(&events), Some(StreamEndReason::Removed));
        assert_eq!(coordinator.watching(), None);
    }

    #[test]
    fn reset_clears_the_directory_and_reports_the_reason() {
        let mut coordinator = watching_stream();
        let events = coordinator.reset(0, StreamEndReason::Disconnected);
        assert_eq!(ended(&events), Some(StreamEndReason::Disconnected));
        assert_eq!(coordinator.channel(), 0);
        assert!(
            coordinator
                .reset(0, StreamEndReason::Disconnected)
                .is_empty()
        );
    }

    #[test]
    fn leave_and_signal_targets_are_scoped_to_the_watched_source() {
        let mut coordinator = watching_stream();
        assert!(coordinator.check_signal_target("s1", SOURCE).is_ok());
        assert!(coordinator.check_signal_target("s1", SOURCE + 1).is_err());
        assert!(coordinator.check_signal_target("s2", SOURCE).is_err());
        assert!(coordinator.leave("s2").is_err());
        assert_eq!(
            ended(&coordinator.leave("s1").unwrap()),
            Some(StreamEndReason::Left)
        );
        assert!(coordinator.check_signal_target("s1", SOURCE).is_err());
    }

    #[test]
    fn abandon_only_reverts_the_same_pending_join() {
        let mut coordinator = watching_stream();
        assert!(coordinator.abandon_join("s2").is_empty());
        assert_eq!(coordinator.abandon_join("s1").len(), 1);
        assert_eq!(coordinator.watching(), None);
    }

    #[test]
    fn payloads_match_the_ts6_wire_shape() {
        let answer: Value = serde_json::from_str(&answer_payload("v=0")).unwrap();
        assert_eq!(
            answer,
            serde_json::json!({"cmd":"answer","args":{"answer":"v=0"}})
        );
        let full: Value = serde_json::from_str(&ice_payload("c", Some("0"), Some(1))).unwrap();
        assert_eq!(
            full,
            serde_json::json!({"cmd":"iceCandidate","args":{"sdp":"c","mid":"0","mLine":1}})
        );
        let bare: Value = serde_json::from_str(&ice_payload("c", None, None)).unwrap();
        assert_eq!(
            bare,
            serde_json::json!({"cmd":"iceCandidate","args":{"sdp":"c"}})
        );
    }

    fn build_escaped_command(cmd: &str, params: &[(&str, String)]) -> String {
        let mut parts = vec![tsclient_rs::escape(cmd).0];
        for (k, v) in params {
            parts.push(format!("{k}={}", tsclient_rs::escape(v).0));
        }
        parts.join(" ")
    }

    #[test]
    fn publisher_commands_escape_special_characters_properly() {
        let setup = setup_stream_request("My Screen | \"Dev\"\nLine2", true, 4608, 0);
        assert_eq!(
            build_escaped_command("setupstream", &setup),
            "setupstream name=My\\sScreen\\s\\p\\s\"Dev\"\\nLine2 type=3 bitrate=4608 accessibility=1 mode=1 viewer_limit=0 audio=1"
        );

        let stop = stop_stream_request("pub-1");
        assert_eq!(
            build_escaped_command("stopstream", &stop),
            "stopstream id=pub-1 reason=1"
        );

        let respond_accept =
            respond_join_request("pub-1", 88, true, "v=0\r\no=- 1 1 IN IP4 127.0.0.1");
        assert_eq!(
            build_escaped_command("respondjoinstreamrequest", &respond_accept),
            "respondjoinstreamrequest id=pub-1 clid=88 msg= offer=v=0\\r\\no=-\\s1\\s1\\sIN\\sIP4\\s127.0.0.1 decision=1"
        );

        let respond_reject = respond_join_request("pub-1", 88, false, "ignored");
        assert_eq!(
            build_escaped_command("respondjoinstreamrequest", &respond_reject),
            "respondjoinstreamrequest id=pub-1 clid=88 msg= offer= decision=0"
        );

        let remove = remove_client_request("pub-1", 88);
        assert_eq!(
            build_escaped_command("removeclientfromstream", &remove),
            "removeclientfromstream id=pub-1 clid=88 reason=1"
        );
    }

    #[test]
    fn publisher_full_lifecycle_from_starting_to_viewer_negotiation_and_stop() {
        let mut coordinator = StreamCoordinator::default();
        coordinator.reset(CHANNEL, StreamEndReason::SelfMoved);

        // 1. Idle -> Starting
        let setup_params = coordinator
            .start_publish("IDE Share", true, 4608, 0)
            .unwrap();
        assert_eq!(setup_params[0], ("name", "IDE Share".to_string()));
        assert_eq!(setup_params[6], ("audio", "1".to_string()));
        assert_eq!(
            coordinator.publish_state(),
            &LocalPublishState::Starting {
                name: "IDE Share".into(),
                has_audio: true,
            }
        );
        // 非 Idle 时重复调用 start_publish 拒绝
        assert!(
            coordinator
                .start_publish("Another", false, 2000, 0)
                .is_err()
        );

        // 2. 收到属于自己的 notifystreamstarted -> Active
        let events = coordinator.notification(
            "notifystreamstarted",
            &params(&[
                ("id", "pub-stream-1"),
                ("clid", "1"),
                ("name", "IDE Share"),
                ("audio", "1"),
            ]),
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            events.as_slice(),
            [SessionEvent::ScreenSharePublished { stream_id }] if stream_id == "pub-stream-1"
        ));
        assert!(coordinator.take_orphan_streams().is_empty());
        assert_eq!(coordinator.published_stream_id(), Some("pub-stream-1"));

        // 3. 观众 (clid=77) 请求加入
        let events = coordinator.notification(
            "notifyjoinstreamrequest",
            &params(&[("id", "pub-stream-1"), ("clid", "77")]),
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            events.as_slice(),
            [SessionEvent::StreamViewerJoinRequested { stream_id, viewer_clid: 77 }]
                if stream_id == "pub-stream-1"
        ));
        // 尚未调用 respond_viewer_join 前，不允许向 Requested 状态的观众提前发送 ICE 信令
        assert!(coordinator.check_publisher_signal_target(77).is_err());

        // 4. 回复 Offer 接受观众
        let respond = coordinator
            .respond_viewer_join(77, true, "v=0 offer-sdp")
            .unwrap();
        assert_eq!(respond[0], ("id", "pub-stream-1".to_string()));
        assert_eq!(respond[1], ("clid", "77".to_string()));
        assert_eq!(respond[3], ("offer", "v=0 offer-sdp".to_string()));
        assert_eq!(respond[4], ("decision", "1".to_string()));
        assert_eq!(
            coordinator.check_publisher_signal_target(77).unwrap(),
            "pub-stream-1"
        );
        assert!(coordinator.check_publisher_signal_target(99).is_err());

        // 5. 收到观众发来的 Answer 与 ICE Candidate
        let answer_events = coordinator.notification(
            "notifystreamsignaling",
            &params(&[
                ("id", "pub-stream-1"),
                ("clid", "77"),
                (
                    "json",
                    r#"{"cmd":"answer","args":{"answer":"v=0 answer-sdp"}}"#,
                ),
            ]),
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            answer_events.as_slice(),
            [SessionEvent::PublisherSignalReceived {
                stream_id,
                viewer_clid: 77,
                signal: PublisherSignal::Answer { sdp },
            }] if stream_id == "pub-stream-1" && sdp == "v=0 answer-sdp"
        ));

        let ice_events = coordinator.notification(
            "notifystreamsignaling",
            &params(&[
                ("id", "pub-stream-1"),
                ("clid", "77"),
                (
                    "json",
                    r#"{"cmd":"iceCandidate","args":{"sdp":"candidate:pub 1","mid":"0","mLine":0}}"#,
                ),
            ]),
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            ice_events.as_slice(),
            [SessionEvent::PublisherSignalReceived {
                stream_id,
                viewer_clid: 77,
                signal: PublisherSignal::IceCandidate {
                    sdp,
                    mid: Some(mid),
                    m_line: Some(0),
                },
            }] if stream_id == "pub-stream-1" && sdp == "candidate:pub 1" && mid == "0"
        ));

        // 6. 观众离开通知或主动踢出观众
        let left_events = coordinator.notification(
            "notifystreamclientleft",
            &params(&[("id", "pub-stream-1"), ("clid", "77")]),
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            left_events.as_slice(),
            [SessionEvent::StreamViewerLeft { stream_id, viewer_clid: 77 }]
                if stream_id == "pub-stream-1"
        ));
        assert!(coordinator.check_publisher_signal_target(77).is_err());

        // 7. 停止推流
        let (stop_id, stop_events) = coordinator.stop_publish();
        assert_eq!(stop_id.as_deref(), Some("pub-stream-1"));
        assert!(matches!(
            stop_events.as_slice(),
            [SessionEvent::ScreenShareStopped]
        ));
        assert_eq!(coordinator.publish_state(), &LocalPublishState::Idle);
    }

    #[test]
    fn stopping_during_starting_cleans_up_delayed_orphan_stream() {
        let mut coordinator = StreamCoordinator::default();
        coordinator.reset(CHANNEL, StreamEndReason::SelfMoved);

        coordinator
            .start_publish("Quick Share", false, 3000, 0)
            .unwrap();
        assert!(matches!(
            coordinator.publish_state(),
            LocalPublishState::Starting { .. }
        ));

        // 用户在等待 notifystreamstarted 期间提前停止推流
        let (stop_id, stop_events) = coordinator.stop_publish();
        assert!(stop_id.is_none());
        assert!(matches!(
            stop_events.as_slice(),
            [SessionEvent::ScreenShareStopped]
        ));
        assert_eq!(coordinator.publish_state(), &LocalPublishState::Idle);

        // 随后服务器的 notifystreamstarted 迟到下发 -> 触发孤儿流 stopstream 清理
        let events = coordinator.notification(
            "notifystreamstarted",
            &params(&[("id", "orphan-99"), ("clid", "1"), ("name", "Quick Share")]),
            Some(SELF),
            in_channel,
        );
        assert!(events.is_empty());
        assert_eq!(coordinator.publish_state(), &LocalPublishState::Idle);
        let orphans = coordinator.take_orphan_streams();
        assert_eq!(orphans, vec!["orphan-99".to_string()]);
        let stop_req = stop_stream_request(&orphans[0]);
        assert_eq!(
            stop_req,
            [("id", "orphan-99".to_string()), ("reason", "1".to_string())]
        );
    }

    #[test]
    fn simultaneous_publishing_and_watching_routes_signaling_by_stream_id() {
        let mut coordinator = watching_stream();
        // 同时启动本地推流并激活为 pub-self，且登记观众 88
        coordinator.start_publish("My Desk", true, 4608, 0).unwrap();
        let pub_events = coordinator.notification(
            "notifystreamstarted",
            &params(&[("id", "pub-self"), ("clid", "1"), ("name", "My Desk")]),
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            pub_events.as_slice(),
            [SessionEvent::ScreenSharePublished { stream_id }] if stream_id == "pub-self"
        ));
        coordinator.notification(
            "notifyjoinstreamrequest",
            &params(&[("id", "pub-self"), ("clid", "88")]),
            Some(SELF),
            in_channel,
        );
        coordinator
            .respond_viewer_join(88, true, "v=0 pub-offer")
            .unwrap();

        // 1. 收到来自观看流 s1 (clid=42) 的 ICE 候选 -> 路由至 Viewer 事件 StreamIceCandidate
        let viewer_ice = coordinator.notification(
            "notifystreamsignaling",
            &params(&[
                ("id", "s1"),
                ("clid", "42"),
                (
                    "json",
                    r#"{"cmd":"iceCandidate","args":{"sdp":"candidate:from-source","mid":"0","mLine":0}}"#,
                ),
            ]),
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            viewer_ice.as_slice(),
            [SessionEvent::StreamIceCandidate {
                stream_id,
                source_client_id: SOURCE,
                sdp,
                ..
            }] if stream_id == "s1" && sdp == "candidate:from-source"
        ));

        // 2. 收到来自推流观众 pub-self (clid=88) 的 Answer -> 路由至 Publisher 事件 PublisherSignalReceived
        let pub_answer = coordinator.notification(
            "notifystreamsignaling",
            &params(&[
                ("id", "pub-self"),
                ("clid", "88"),
                (
                    "json",
                    r#"{"cmd":"answer","args":{"answer":"v=0 viewer-answer"}}"#,
                ),
            ]),
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            pub_answer.as_slice(),
            [SessionEvent::PublisherSignalReceived {
                stream_id,
                viewer_clid: 88,
                signal: PublisherSignal::Answer { sdp },
            }] if stream_id == "pub-self" && sdp == "v=0 viewer-answer"
        ));

        // 3. 收到来自推流观众 pub-self (clid=88) 的 ICE -> 路由至 Publisher 事件 PublisherSignalReceived
        let pub_ice = coordinator.notification(
            "notifystreamsignaling",
            &params(&[
                ("id", "pub-self"),
                ("clid", "88"),
                (
                    "json",
                    r#"{"cmd":"iceCandidate","args":{"sdp":"candidate:from-viewer","mid":"1","mLine":1}}"#,
                ),
            ]),
            Some(SELF),
            in_channel,
        );
        assert!(matches!(
            pub_ice.as_slice(),
            [SessionEvent::PublisherSignalReceived {
                stream_id,
                viewer_clid: 88,
                signal: PublisherSignal::IceCandidate { sdp, .. },
            }] if stream_id == "pub-self" && sdp == "candidate:from-viewer"
        ));

        // Both watching and publishing remain intact
        assert_eq!(coordinator.watching(), Some(("s1", SOURCE)));
        assert_eq!(coordinator.published_stream_id(), Some("pub-self"));
    }

    #[test]
    fn publisher_guards_kick_remote_stop_and_channel_or_disconnect_reset() {
        let mut coordinator = StreamCoordinator::default();
        coordinator.reset(CHANNEL, StreamEndReason::SelfMoved);

        // Starting 状态下切换频道或断线会清理状态并发出 ScreenShareStopped
        coordinator.start_publish("Share", false, 2000, 0).unwrap();
        let reset_events = coordinator.reset(CHANNEL + 1, StreamEndReason::SelfMoved);
        assert!(matches!(
            reset_events.as_slice(),
            [SessionEvent::ScreenShareStopped]
        ));
        assert_eq!(coordinator.publish_state(), &LocalPublishState::Idle);

        // Active 状态下踢出观众与收到服务器 notifystreamstopped
        coordinator.start_publish("Share", true, 4608, 0).unwrap();
        coordinator.notification(
            "notifystreamstarted",
            &params(&[("id", "pub-2"), ("clid", "1")]),
            Some(SELF),
            |_| Some(CHANNEL + 1),
        );
        coordinator.notification(
            "notifyjoinstreamrequest",
            &params(&[("id", "pub-2"), ("clid", "55")]),
            Some(SELF),
            |_| Some(CHANNEL + 1),
        );
        let (kick_params, kick_event) = coordinator.kick_viewer(55).unwrap();
        assert_eq!(
            kick_params,
            [
                ("id", "pub-2".to_string()),
                ("clid", "55".to_string()),
                ("reason", "1".to_string()),
            ]
        );
        assert!(matches!(
            kick_event,
            SessionEvent::StreamViewerLeft { stream_id, viewer_clid: 55 } if stream_id == "pub-2"
        ));

        let stopped = coordinator.notification(
            "notifystreamstopped",
            &params(&[("id", "pub-2")]),
            Some(SELF),
            |_| Some(CHANNEL + 1),
        );
        assert!(matches!(
            stopped.as_slice(),
            [SessionEvent::ScreenShareStopped]
        ));
        assert_eq!(coordinator.publish_state(), &LocalPublishState::Idle);
    }
}
