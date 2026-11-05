//! TS6 屏幕共享观看端：当前频道的流目录与观看状态机。
//!
//! TeamSpeak 服务器只转交信令，媒体由 Flutter 侧的 WebRTC 点对点收发。这里不碰
//! 网络：actor 把原始通知喂进来，拿回要广播的 [`SessionEvent`]；下行命令发出前
//! 先经这里校验，Dart 不能对未加入的流或非来源客户端发信令。
//!
//! 流目录只属于一个频道（[`StreamCoordinator::channel`]）。自己换频道或断线时整张
//! 目录作废，由 actor 在新频道里重新发现。

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
}

/// 只有这些通知会被 actor 转进来。
pub(crate) fn is_stream_notification(name: &str) -> bool {
    matches!(
        name,
        "notifystreamstarted"
            | "notifystreaminfo"
            | "notifystreamstopped"
            | "notifystreamclientleft"
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

    /// 作废整张目录并切到 `channel_id`。正在观看的流以 `reason` 结束。
    pub(crate) fn reset(&mut self, channel_id: u64, reason: StreamEndReason) -> Vec<SessionEvent> {
        self.channel_id = channel_id;
        let mut out = Vec::new();
        let ended = self.end_watching(reason, &mut out);
        let had_streams = !self.streams.is_empty();
        self.streams.clear();
        if ended || had_streams {
            out.push(self.list_event());
        }
        out
    }

    /// 推流者离开服务器。
    pub(crate) fn client_left(&mut self, clid: i32) -> Vec<SessionEvent> {
        self.drop_source(clid, StreamEndReason::SourceLeft)
    }

    /// 其他客户端换了频道；推流者离开本频道时它的流作废。
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
                // 自己推的流不进观看目录。
                if Some(clid) == self_clid || self.channel_id == 0 {
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
            "notifystreamstopped" => {
                let removed = self.streams.remove(&stream_id).is_some();
                let ended =
                    self.end_watching_if(&stream_id, StreamEndReason::SourceStopped, &mut out);
                if removed || ended {
                    out.push(self.list_event());
                }
            }
            "notifystreamclientleft" => {
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
    [
        ("id", stream_id.to_string()),
        ("clid", self_clid.to_string()),
        ("reason", "1".into()),
    ]
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
}
