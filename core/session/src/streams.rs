//! TS6 屏幕共享会话视图类型与协议映射辅助函数。
//!
//! 底层信令交互、全服流缓存与 `joinstreamrequest` / `streamsignaling` 命令构造均由
//! `tsclient_rs::stream::Streams` 负责；本模块将上游事件和 `StreamInfo` 投影为
//! 面向前端与 FFI 的 [`StreamView`]、[`StreamEndReason`] 和 [`PublisherSignal`]。

use tsclient_rs::stream::{
    IceCandidate, PeerCloseCause, PublishOptions, StreamAccessibility, StreamError, StreamInfo,
    StreamSource,
};

use crate::SessionError;

/// 当前频道内一路可观看的屏幕共享。
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

/// 将 `tsclient-rs` 的全服流描述转换为 UI 视图。
pub(crate) fn stream_view(info: &StreamInfo) -> StreamView {
    StreamView {
        id: info.id.clone(),
        client_id: info.client_id,
        name: info.name.clone(),
        has_audio: info.audio,
    }
}

/// 从全服已发现的流中投影出当前所在频道的可观看流，按 `id` 确定性排序并排除自己。
pub(crate) fn project_channel_streams<F>(
    infos: &[StreamInfo],
    self_channel_id: u64,
    self_client_id: Option<i32>,
    mut channel_of: F,
) -> Vec<StreamView>
where
    F: FnMut(i32) -> Option<u64>,
{
    if self_channel_id == 0 {
        return Vec::new();
    }
    let mut views: Vec<StreamView> = infos
        .iter()
        .filter(|info| Some(info.client_id) != self_client_id)
        .filter(|info| channel_of(info.client_id) == Some(self_channel_id))
        .map(stream_view)
        .collect();
    views.sort_by(|left, right| left.id.cmp(&right.id));
    views
}

/// 构造屏幕共享发布参数。
pub(crate) fn publish_options(
    name: &str,
    audio: bool,
    bitrate: u32,
    viewer_limit: u32,
) -> Result<PublishOptions, SessionError> {
    if name.trim().is_empty() {
        return Err(SessionError::Stream("share name must not be empty".into()));
    }
    if bitrate == 0 {
        return Err(SessionError::Stream(
            "share bitrate must be greater than 0".into(),
        ));
    }
    Ok(PublishOptions {
        name: name.to_string(),
        source: StreamSource::Window,
        audio,
        bitrate,
        accessibility: StreamAccessibility::Public,
        viewer_limit: u16::try_from(viewer_limit).unwrap_or(u16::MAX),
        timeout_ms: None,
        abort: None,
    })
}

/// 构造透传给 `tsclient-rs` 的 WebRTC ICE 候选载荷。
pub(crate) fn ice_candidate(
    sdp: String,
    mid: Option<String>,
    m_line: Option<i32>,
) -> Result<IceCandidate, SessionError> {
    if sdp.trim().is_empty() {
        return Err(SessionError::Stream(
            "ICE candidate must not be empty".into(),
        ));
    }
    let sdp_m_line_index = m_line
        .map(|idx| {
            u16::try_from(idx).map_err(|_| SessionError::Stream(format!("invalid m_line: {idx}")))
        })
        .transpose()?;
    Ok(IceCandidate {
        candidate: sdp,
        sdp_mid: mid,
        sdp_m_line_index,
    })
}

/// 将对端句柄关闭原因映射为会话层 [`StreamEndReason`]。
pub(crate) fn peer_close_reason(cause: PeerCloseCause) -> StreamEndReason {
    match cause {
        PeerCloseCause::Left => StreamEndReason::Removed,
        PeerCloseCause::Stopped => StreamEndReason::SourceStopped,
        PeerCloseCause::Disconnected => StreamEndReason::Disconnected,
        PeerCloseCause::Closed | PeerCloseCause::Disposed => StreamEndReason::Left,
    }
}

/// 将异步 `Streams::watch` 失败原因映射为会话层 [`StreamEndReason`]。
pub(crate) fn watch_error_reason(error: &StreamError) -> StreamEndReason {
    match error {
        StreamError::JoinDenied(_) => StreamEndReason::Rejected,
        StreamError::Ended(_) => StreamEndReason::SourceStopped,
        StreamError::NotConnected | StreamError::Disposed => StreamEndReason::Disconnected,
        _ => StreamEndReason::Left,
    }
}

/// 将 `tsclient-rs` 流错误转换为 [`SessionError`]。
pub(crate) fn stream_error(error: StreamError) -> SessionError {
    match error {
        StreamError::NotConnected | StreamError::Disposed => SessionError::NotConnected,
        StreamError::Client(err) => match crate::channel_tools::protocol_error(err) {
            SessionError::Protocol(message) => SessionError::Stream(message),
            other => other,
        },
        other => SessionError::Stream(other.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use tsclient_rs::Error;
    use tsclient_rs::stream::{StreamEndedError, StreamJoinDeniedError};

    fn info(id: &str, client_id: i32, name: &str, audio: bool) -> StreamInfo {
        StreamInfo {
            id: id.to_string(),
            client_id,
            name: name.to_string(),
            source: Some(StreamSource::Window),
            audio,
            bitrate: Some(2_500_000),
            accessibility: Some(StreamAccessibility::Public),
            transport: None,
            viewer_limit: Some(0),
            viewers: None,
        }
    }

    #[test]
    fn project_channel_streams_filters_by_channel_excludes_self_and_sorts() {
        let channels = HashMap::from([(10, 5), (11, 5), (12, 9), (1, 5)]);
        let infos = vec![
            info("s-z", 11, "Peer Z", true),
            info("s-other", 12, "Other", false),
            info("s-self", 1, "Self", true),
            info("s-a", 10, "Peer A", false),
            info("s-unknown", 99, "Unknown", false),
        ];

        assert!(
            project_channel_streams(&infos, 0, Some(1), |clid| channels.get(&clid).copied())
                .is_empty()
        );

        let projected =
            project_channel_streams(&infos, 5, Some(1), |clid| channels.get(&clid).copied());
        assert_eq!(
            projected,
            vec![
                StreamView {
                    id: "s-a".into(),
                    client_id: 10,
                    name: "Peer A".into(),
                    has_audio: false,
                },
                StreamView {
                    id: "s-z".into(),
                    client_id: 11,
                    name: "Peer Z".into(),
                    has_audio: true,
                },
            ]
        );
    }

    #[test]
    fn ice_candidate_validates_sdp_and_mline_range() {
        assert!(ice_candidate("   ".into(), None, None).is_err());
        assert!(ice_candidate("candidate:1".into(), Some("0".into()), Some(-1)).is_err());
        assert!(ice_candidate("candidate:1".into(), Some("0".into()), Some(70_000)).is_err());

        let cand = ice_candidate("candidate:1".into(), Some("0".into()), Some(1)).unwrap();
        assert_eq!(cand.candidate, "candidate:1");
        assert_eq!(cand.sdp_mid.as_deref(), Some("0"));
        assert_eq!(cand.sdp_m_line_index, Some(1));
    }

    #[test]
    fn publish_options_validates_fields_and_saturates_viewer_limit() {
        assert!(publish_options("   ", true, 1_500_000, 0).is_err());
        assert!(publish_options("Screen", false, 0, 0).is_err());

        let opts = publish_options("Game", true, 4_000_000, 100_000).unwrap();
        assert_eq!(opts.name, "Game");
        assert_eq!(opts.source, StreamSource::Window);
        assert!(opts.audio);
        assert_eq!(opts.bitrate, 4_000_000);
        assert_eq!(opts.accessibility, StreamAccessibility::Public);
        assert_eq!(opts.viewer_limit, u16::MAX);
    }

    #[test]
    fn error_and_close_reason_mappings_preserve_semantics() {
        assert_eq!(
            peer_close_reason(PeerCloseCause::Left),
            StreamEndReason::Removed
        );
        assert_eq!(
            peer_close_reason(PeerCloseCause::Stopped),
            StreamEndReason::SourceStopped
        );
        assert_eq!(
            peer_close_reason(PeerCloseCause::Disconnected),
            StreamEndReason::Disconnected
        );
        assert_eq!(
            peer_close_reason(PeerCloseCause::Closed),
            StreamEndReason::Left
        );

        assert_eq!(
            watch_error_reason(&StreamError::JoinDenied(StreamJoinDeniedError {
                stream_id: "s1".into(),
                server_message: "no".into(),
            })),
            StreamEndReason::Rejected
        );
        assert_eq!(
            watch_error_reason(&StreamError::Ended(StreamEndedError {
                stream_id: "s1".into(),
                cause: None,
            })),
            StreamEndReason::SourceStopped
        );
        assert_eq!(
            watch_error_reason(&StreamError::NotConnected),
            StreamEndReason::Disconnected
        );

        assert!(matches!(
            stream_error(StreamError::NotConnected),
            SessionError::NotConnected
        ));
        assert!(matches!(
            stream_error(StreamError::Disposed),
            SessionError::NotConnected
        ));
        assert!(matches!(
            stream_error(StreamError::Client(Error::CommandTimeout {
                command: "setupstream".into(),
            })),
            SessionError::Timeout
        ));
    }
}
