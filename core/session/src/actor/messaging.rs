//! 含文本消息与频道移动/描述。

use super::*;

/// ServerQuery 单行消息上限。
#[allow(dead_code)]
const MAX_TEXT_MESSAGE_BYTES: usize = 8192;

impl Actor {
    pub(super) async fn send_text(
        &self,
        target_mode: i32,
        target_id: u64,
        message: String,
    ) -> Result<(), SessionError> {
        let client = self.connected()?;
        // 将 Markdown 转换为安全 BBCode，并在 Block 级别按转义后预算完成分片，
        // 杜绝 BBCode 标签跨包断开和 ServerQuery 转义膨胀导致的截断。
        let packets = crate::text_format::markdown_to_bbcode_packets(&message, 1024);
        for chunk in packets {
            client
                .exec_command(
                    &format!(
                        "sendtextmessage targetmode={target_mode} target={target_id} msg={}",
                        tsclient_rs::escape(&chunk).0
                    ),
                    5_000,
                )
                .await
                .map_err(protocol_error)?;
        }
        Ok(())
    }

    pub(super) async fn move_to_channel(
        &self,
        client_id: i32,
        channel_id: u64,
        password: Option<String>,
    ) -> Result<(), SessionError> {
        let client = self.connected()?;
        let password = crate::channel_tools::channel_password(&password.unwrap_or_default());
        tsclient_rs::clientMove(&client, client_id, channel_id, &password)
            .await
            .map_err(crate::channel_tools::protocol_error)
    }

    pub(super) async fn channel_description(
        &self,
        channel_id: u64,
    ) -> Result<String, SessionError> {
        let client = self.connected()?;
        let desc = match tsclient_rs::get_channel_description(&client, channel_id).await {
            Ok(desc) => desc,
            Err(_) => {
                let info = tsclient_rs::get_channel_info(&client, channel_id)
                    .await
                    .map_err(crate::channel_tools::protocol_error)?;
                info.description
            }
        };
        Ok(crate::text_format::bbcode_to_markdown(&desc))
    }

    pub(super) fn build_welcome_message(
        profile: &ServerProfile,
        welcome_message: &str,
        at: u64,
    ) -> Option<TextMessageView> {
        let trimmed = welcome_message.trim();
        if trimmed.is_empty() {
            return None;
        }
        let normalized = crate::text_format::bbcode_to_markdown(trimmed);
        let normalized = normalized.trim();
        if normalized.is_empty() {
            return None;
        }
        let label = profile.label.trim();
        let from = if label.is_empty() {
            profile.host.clone()
        } else {
            label.to_string()
        };
        Some(TextMessageView {
            from,
            from_uid: String::new(),
            from_id: 0,
            message: normalized.to_string(),
            target_mode: 3,
            target_id: 0,
            peer_uid: String::new(),
            at,
        })
    }

    pub(super) async fn emit_history(&self) {
        let Some(server_id) = &self.active_server_id else {
            return;
        };
        let path = store::history_path(&self.store_path);
        match store::load_history(&path, server_id, crate::HISTORY_LIMIT).await {
            Ok(messages) => self.emit(SessionEvent::History { messages }),
            Err(message) => self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("历史消息读取失败: {message}"),
            }),
        }
    }

    /// 私聊对端 UID：收到的是发送者；自己发出的回显按目标客户端 id 查当前快照。
    /// 频道与服务器广播没有单一对端，返回空串。
    pub(super) fn direct_peer_uid(&self, message: &TextMessageView) -> String {
        if message.target_mode != 1 {
            return String::new();
        }
        let own = self.self_client_id == Some(message.from_id);
        if !own {
            return message.from_uid.clone();
        }
        self.last_snapshot
            .as_ref()
            .and_then(|(_, clients)| {
                clients
                    .iter()
                    .find(|client| client.id as u64 == message.target_id)
                    .map(|client| client.uid.clone())
            })
            .or_else(|| {
                let snapshot = self.client.as_ref()?.directory_snapshot()?;
                snapshot
                    .clients
                    .into_iter()
                    .find(|client| client.id as u64 == message.target_id)
                    .map(|client| client.uid)
            })
            .unwrap_or_default()
    }
}

/// 按 UTF-8 字节上限切分文本消息。
///
/// 优先在空白处断开；找不到合适空白时退到字符边界。单个字符本身超过上限时
/// 独占一片，不切断 UTF-8。片与片之间的空白会被丢弃，语义与 TeamSpeakClaw 一致。
#[allow(dead_code)]
fn split_text_message(message: &str, max_bytes: usize) -> Vec<String> {
    assert!(max_bytes > 0, "max_bytes must be > 0");
    if message.len() <= max_bytes {
        return vec![message.to_string()];
    }

    let mut chunks = Vec::new();
    let mut start = 0;
    let len = message.len();

    while start < len {
        let mut end = (start + max_bytes).min(len);
        if end == len {
            chunks.push(message[start..].to_string());
            break;
        }

        while !message.is_char_boundary(end) {
            end -= 1;
        }
        if end == start {
            end = start + 1;
            while !message.is_char_boundary(end) {
                end += 1;
            }
        }

        // 只在最近 256 字节里找空白，避免为了一个空格把整片缩得太短。
        let lookback_start = end.saturating_sub(256).max(start);
        if lookback_start < end
            && let Some(relative) = message[lookback_start..end].rfind(char::is_whitespace)
        {
            let whitespace = lookback_start + relative;
            if whitespace > start {
                chunks.push(message[start..whitespace].to_string());
                let width = message[whitespace..]
                    .chars()
                    .next()
                    .map(char::len_utf8)
                    .unwrap_or(1);
                start = whitespace + width;
                continue;
            }
        }

        chunks.push(message[start..end].to_string());
        start = end;
    }

    chunks
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::test_support::*;

    #[test]
    fn direct_peer_uid_uses_the_sender_or_resolves_the_echo_target() {
        let mut actor = audio_actor();
        actor.self_client_id = Some(7);
        actor.last_snapshot = Some((
            Vec::new(),
            vec![
                ClientView {
                    id: 7,
                    nickname: "Self".into(),
                    uid: "self".into(),
                    channel_id: 5,
                    input_muted: None,
                    output_muted: None,
                    away: None,
                    away_message: None,
                    client_type: ClientType::FlSpeak,
                    app_name: Some("FlSpeak".into()),
                    app_version: Some("0.1.12".into()),
                    capabilities: Vec::new(),
                    bot_commands: None,
                },
                ClientView {
                    id: 9,
                    nickname: "Peer".into(),
                    uid: "peer".into(),
                    channel_id: 5,
                    input_muted: None,
                    output_muted: None,
                    away: None,
                    away_message: None,
                    client_type: ClientType::Standard,
                    app_name: None,
                    app_version: None,
                    capabilities: Vec::new(),
                    bot_commands: None,
                },
            ],
        ));

        let incoming = TextMessageView {
            from: "Peer".into(),
            from_uid: "peer".into(),
            from_id: 9,
            message: "hi".into(),
            target_mode: 1,
            target_id: 7,
            peer_uid: String::new(),
            at: 1,
        };
        assert_eq!(actor.direct_peer_uid(&incoming), "peer");

        let echo = TextMessageView {
            from: "Self".into(),
            from_uid: "self".into(),
            from_id: 7,
            message: "hello".into(),
            target_mode: 1,
            target_id: 9,
            peer_uid: String::new(),
            at: 2,
        };
        assert_eq!(actor.direct_peer_uid(&echo), "peer");

        let broadcast = TextMessageView {
            target_mode: 3,
            target_id: 0,
            ..echo
        };
        assert_eq!(actor.direct_peer_uid(&broadcast), "");
    }

    #[test]
    fn short_text_message_is_sent_as_one_chunk() {
        assert_eq!(split_text_message("hello", 8192), vec!["hello"]);
        assert_eq!(split_text_message("hello", 5), vec!["hello"]);
    }

    #[test]
    fn long_text_message_splits_on_utf8_boundaries() {
        let message = "a".repeat(10_000);
        let chunks = split_text_message(&message, 8192);
        assert_eq!(chunks.len(), 2);
        assert!(chunks.iter().all(|chunk| chunk.len() <= 8192));
        assert_eq!(chunks.concat(), message);
    }

    #[test]
    fn split_text_message_prefers_whitespace_and_preserves_text() {
        let chunks = split_text_message("hello world foo bar", 10);
        assert!(chunks.iter().all(|chunk| chunk.len() <= 10));
        let stripped: String = chunks
            .concat()
            .chars()
            .filter(|ch| !ch.is_whitespace())
            .collect();
        assert_eq!(stripped, "helloworldfoobar");
    }

    #[test]
    fn split_text_message_keeps_emoji_whole() {
        let chunks = split_text_message("a🥴bc", 2);
        assert_eq!(chunks, vec!["a", "🥴", "bc"]);
    }

    #[test]
    fn split_text_message_handles_fullwidth_space() {
        let message = "a\u{3000}b\u{3000}c";
        let chunks = split_text_message(message, 3);
        assert!(chunks.iter().all(|chunk| !chunk.is_empty()));
        assert_eq!(chunks.concat(), message);
    }

    #[test]
    fn build_welcome_message_uses_label_or_host_and_skips_blank() {
        let labeled = ServerProfile {
            id: "ts.example.com:9987".into(),
            label: " My Community ".into(),
            host: "ts.example.com".into(),
            port: 9987,
            server_password: None,
            default_channel: None,
            default_channel_password: None,
        };
        let message = Actor::build_welcome_message(&labeled, "  Welcome to TS!  ", 42).unwrap();
        assert_eq!(message.from, "My Community");
        assert_eq!(message.from_uid, "");
        assert_eq!(message.from_id, 0);
        assert_eq!(message.message, "Welcome to TS!");
        assert_eq!(message.target_mode, 3);
        assert_eq!(message.target_id, 0);
        assert_eq!(message.at, 42);

        let unlabeled = ServerProfile {
            label: "   ".into(),
            ..labeled.clone()
        };
        let fallback = Actor::build_welcome_message(&unlabeled, "Hello", 99).unwrap();
        assert_eq!(fallback.from, "ts.example.com");

        assert!(Actor::build_welcome_message(&labeled, "  \n\t ", 100).is_none());
        assert!(Actor::build_welcome_message(&labeled, "[center]   [/center]", 101).is_none());

        let bbcode_welcome = concat!(
            "[COLOR=#ff55ff][I]Welcome notice[/I][/COLOR] ",
            "Portal [URL]https://portal.example.com/[/URL] ",
            "[COLOR=#FFD700][B]Client guide[/B] ",
            "[URL=https://docs.example.com/guide]Open guide [/URL][/COLOR]",
        );
        let converted = Actor::build_welcome_message(&labeled, bbcode_welcome, 102).unwrap();
        assert_eq!(
            converted.message,
            concat!(
                r##"<color hex="#ff55ff">*Welcome notice*</color> "##,
                "Portal [https://portal.example.com/](https://portal.example.com/) ",
                r##"<color hex="#ffd700">**Client guide** "##,
                "[Open guide ](https://docs.example.com/guide)</color>",
            )
        );
    }
}
