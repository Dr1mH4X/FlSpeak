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
pub(super) fn split_text_message(message: &str, max_bytes: usize) -> Vec<String> {
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
