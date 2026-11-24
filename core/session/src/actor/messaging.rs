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
            from_self: false,
            at,
        })
    }

    pub(super) async fn emit_history(&self) {
        let Some(server_id) = &self.active_server_id else {
            return;
        };
        let path = store::history_path(&self.store_path);
        match store::load_history(&path, server_id, crate::HISTORY_LIMIT).await {
            Ok(mut messages) => {
                self.resolve_history_messages(&mut messages);
                self.emit(SessionEvent::History { messages });
            }
            Err(message) => self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("failed to read message history: {message}"),
            }),
        }
    }

    pub(super) fn resolve_self_uid(&self) -> String {
        if let Some(uid) = &self.self_uid
            && !uid.is_empty()
        {
            return uid.clone();
        }
        let Some(self_id) = self.self_client_id else {
            return String::new();
        };
        self.directory
            .find_non_empty_client_uid(self_id)
            .or_else(|| {
                let snapshot = self.client.as_ref()?.directory_snapshot()?;
                snapshot
                    .clients
                    .into_iter()
                    .find(|client| client.id == self_id && !client.uid.is_empty())
                    .map(|client| client.uid)
            })
            .unwrap_or_default()
    }

    pub(super) fn is_own_text_message(&self, message: &TextMessageView) -> bool {
        if message.from_self {
            return true;
        }
        if message.from_id > 0
            && let Some(self_id) = self.self_client_id
        {
            return message.from_id == self_id;
        }
        if message.target_mode == 1
            && message.target_id > 0
            && let Some(self_id) = self.self_client_id
        {
            return message.target_id != self_id as u64;
        }
        let self_uid = self.resolve_self_uid();
        !self_uid.is_empty() && message.from_uid == self_uid
    }

    pub(super) fn resolve_history_messages(&self, messages: &mut [TextMessageView]) {
        let self_uid = self.resolve_self_uid();
        for message in messages {
            if message.from_self {
                continue;
            }
            if message.target_mode == 1
                && !message.peer_uid.is_empty()
                && !message.from_uid.is_empty()
                && message.peer_uid != message.from_uid
            {
                message.from_self = true;
                continue;
            }
            if !self_uid.is_empty() {
                message.from_self = message.from_uid == self_uid;
            } else {
                message.from_self = self.is_own_text_message(message);
            }
        }
    }

    /// 补齐收到文本消息的路由归属：
    /// TeamSpeak 的 `notifytextmessage` 在频道消息（`target_mode == 2`）下不携带 `target`，
    /// `tsclient-rs` 会将其解析为 0；由于客户端只接收当前所在频道的消息，这里用 `self_channel_id` 补齐。
    pub(super) fn resolve_text_message_routing(&self, message: &mut TextMessageView) {
        if message.target_mode == 2 && message.target_id == 0 && self.self_channel_id != 0 {
            message.target_id = self.self_channel_id;
        }
        message.from_self = self.is_own_text_message(message);
        message.peer_uid = self.direct_peer_uid(message);
    }

    /// 私聊对端 UID：收到的是发送者；自己发出的回显按目标客户端 id 查当前快照。
    /// 频道与服务器广播没有单一对端，返回空串。
    pub(super) fn direct_peer_uid(&self, message: &TextMessageView) -> String {
        if message.target_mode != 1 {
            return String::new();
        }
        if !self.is_own_text_message(message) {
            return message.from_uid.clone();
        }
        self.directory
            .find_client_uid_by_u64(message.target_id)
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
        actor.directory.set_snapshot_for_test(
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
                    is_streaming: false,
                    client_type: ClientType::FlSpeak,
                    app_name: Some("FlSpeak".into()),
                    app_version: Some("0.1.12".into()),
                    capabilities: Vec::new(),
                    bot_commands: Vec::new(),
                    bot_commands_loaded: false,
                    bot_command_prefix: None,
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
                    is_streaming: false,
                    client_type: ClientType::Standard,
                    app_name: None,
                    app_version: None,
                    capabilities: Vec::new(),
                    bot_commands: Vec::new(),
                    bot_commands_loaded: false,
                    bot_command_prefix: None,
                },
            ],
        );

        let incoming = TextMessageView {
            from: "Peer".into(),
            from_uid: "peer".into(),
            from_id: 9,
            message: "hi".into(),
            target_mode: 1,
            target_id: 7,
            peer_uid: String::new(),
            from_self: false,
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
            from_self: false,
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
    fn resolve_text_message_routing_fills_channel_id_when_missing() {
        let mut actor = audio_actor();
        actor.self_channel_id = 5;

        let mut channel_msg = TextMessageView {
            from: "Self".into(),
            from_uid: "self".into(),
            from_id: 1,
            message: "hello channel".into(),
            target_mode: 2,
            target_id: 0,
            peer_uid: String::new(),
            from_self: false,
            at: 10,
        };
        actor.resolve_text_message_routing(&mut channel_msg);
        assert_eq!(channel_msg.target_id, 5);
        assert_eq!(channel_msg.peer_uid, "");

        let mut explicit_channel_msg = TextMessageView {
            target_id: 9,
            ..channel_msg.clone()
        };
        actor.resolve_text_message_routing(&mut explicit_channel_msg);
        assert_eq!(explicit_channel_msg.target_id, 9);

        let mut server_msg = TextMessageView {
            target_mode: 3,
            target_id: 0,
            ..channel_msg
        };
        actor.resolve_text_message_routing(&mut server_msg);
        assert_eq!(server_msg.target_id, 0);
    }

    #[tokio::test]
    async fn handle_signal_channel_text_message_persists_and_emits_channel_id() {
        let dir = std::env::temp_dir().join("flspeak-session-channel-msg-routing-test");
        let _ = tokio::fs::remove_dir_all(&dir).await;

        let mut actor = audio_actor();
        actor.store_path = dir.join("preferences.json");
        actor.active_server_id = Some("ts.example.com:9987".into());
        actor.self_channel_id = 42;
        let mut events = actor.events.subscribe();

        actor
            .handle_signal(SessionSignal::TextMessage {
                epoch: actor.connection_epoch,
                message: TextMessageView {
                    from: "Self".into(),
                    from_uid: "self".into(),
                    from_id: 1,
                    message: "test".into(),
                    target_mode: 2,
                    target_id: 0,
                    peer_uid: String::new(),
                    from_self: false,
                    at: 100,
                },
            })
            .await;

        let event = events.recv().await.unwrap();
        match event {
            SessionEvent::TextMessage(msg) => {
                assert_eq!(msg.target_mode, 2);
                assert_eq!(msg.target_id, 42);
            }
            other => panic!("expected TextMessage, got {other:?}"),
        }

        let history_path = store::history_path(&actor.store_path);
        let loaded = store::load_history(&history_path, "ts.example.com:9987", 10)
            .await
            .unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].target_mode, 2);
        assert_eq!(loaded[0].target_id, 42);

        let _ = tokio::fs::remove_dir_all(&dir).await;
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
        assert!(!converted.from_self);
    }

    #[test]
    fn resolve_routing_and_history_compute_from_self_for_live_dm_and_legacy_records() {
        let mut actor = audio_actor();
        actor.self_client_id = Some(7);
        actor.self_channel_id = 42;
        actor.self_uid = Some("self-uid".into());
        actor.directory.insert_known_client_for_test(ClientView {
            id: 9,
            nickname: "Peer".into(),
            uid: "peer-uid".into(),
            channel_id: 42,
            input_muted: None,
            output_muted: None,
            away: None,
            away_message: None,
            is_streaming: false,
            client_type: ClientType::Standard,
            app_name: None,
            app_version: None,
            capabilities: Vec::new(),
            bot_commands: Vec::new(),
            bot_commands_loaded: false,
            bot_command_prefix: None,
        });

        let mut own_channel = TextMessageView {
            from: "Self".into(),
            from_uid: "self-uid".into(),
            from_id: 7,
            message: "my channel msg".into(),
            target_mode: 2,
            target_id: 0,
            peer_uid: String::new(),
            from_self: false,
            at: 1,
        };
        actor.resolve_text_message_routing(&mut own_channel);
        assert!(own_channel.from_self);
        assert_eq!(own_channel.target_id, 42);
        assert_eq!(own_channel.peer_uid, "");

        let mut incoming_dm = TextMessageView {
            from: "Peer".into(),
            from_uid: "peer-uid".into(),
            from_id: 9,
            message: "hi".into(),
            target_mode: 1,
            target_id: 7,
            peer_uid: String::new(),
            from_self: false,
            at: 2,
        };
        actor.resolve_text_message_routing(&mut incoming_dm);
        assert!(!incoming_dm.from_self);
        assert_eq!(incoming_dm.peer_uid, "peer-uid");

        let mut dm_echo = TextMessageView {
            from: "Self".into(),
            from_uid: "self-uid".into(),
            from_id: 7,
            message: "echo".into(),
            target_mode: 1,
            target_id: 9,
            peer_uid: String::new(),
            from_self: false,
            at: 3,
        };
        actor.resolve_text_message_routing(&mut dm_echo);
        assert!(dm_echo.from_self);
        assert_eq!(dm_echo.peer_uid, "peer-uid");

        let mut history = vec![
            TextMessageView {
                from: "Peer".into(),
                from_uid: "peer-uid".into(),
                from_id: 0,
                message: "legacy incoming dm".into(),
                target_mode: 1,
                target_id: 7,
                peer_uid: String::new(),
                from_self: false,
                at: 4,
            },
            TextMessageView {
                from: "Self".into(),
                from_uid: "self-uid".into(),
                from_id: 0,
                message: "legacy own channel".into(),
                target_mode: 2,
                target_id: 42,
                peer_uid: String::new(),
                from_self: false,
                at: 5,
            },
            TextMessageView {
                from: "Self".into(),
                from_uid: "other-slot".into(),
                from_id: 0,
                message: "outgoing dm history".into(),
                target_mode: 1,
                target_id: 9,
                peer_uid: "peer-uid".into(),
                from_self: false,
                at: 6,
            },
        ];
        actor.resolve_history_messages(&mut history);
        assert!(!history[0].from_self);
        assert!(history[1].from_self);
        assert!(history[2].from_self);
    }
}
