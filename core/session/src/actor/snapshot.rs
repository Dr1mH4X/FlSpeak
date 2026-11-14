use super::*;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(super) struct ChannelMetadata {
    pub(super) order: Option<u64>,
    pub(super) description: Option<String>,
    pub(super) codec: Option<i32>,
    pub(super) max_clients: Option<u16>,
    pub(super) max_clients_limited: Option<bool>,
    pub(super) password_protected: Option<bool>,
}

#[derive(Debug)]
pub(super) struct ChannelDirectory {
    pub(super) channels: Vec<ChannelView>,
    pub(super) codecs: Option<HashMap<u64, i32>>,
    pub(super) metadata_error: Option<String>,
}

pub(super) fn directory_from_channels(
    channels: Vec<ChannelInfo>,
    metadata_error: Option<String>,
) -> ChannelDirectory {
    let codecs: HashMap<u64, i32> = channels
        .iter()
        .filter_map(|channel| channel.codec.map(|codec| (channel.id, codec)))
        .collect();
    ChannelDirectory {
        channels: channels
            .into_iter()
            .map(|channel| channel_view(channel, None))
            .collect(),
        codecs: (!codecs.is_empty()).then_some(codecs),
        metadata_error,
    }
}

pub(super) fn merge_channels(
    incoming_channels: Vec<ChannelView>,
    incoming_codecs: HashMap<u64, i32>,
    previous_channels: &[ChannelView],
    existing_codecs: &HashMap<u64, i32>,
) -> (Vec<ChannelView>, HashMap<u64, i32>) {
    let prev_by_id: HashMap<u64, &ChannelView> = previous_channels
        .iter()
        .map(|channel| (channel.id, channel))
        .collect();
    let mut merged_channels = Vec::with_capacity(incoming_channels.len());
    let mut merged_codecs = HashMap::new();

    for mut channel in incoming_channels {
        if let Some(prev) = prev_by_id.get(&channel.id) {
            channel.order = channel.order.or(prev.order);
            channel.icon_id = channel.icon_id.or(prev.icon_id);
            channel.max_clients = channel.max_clients.or(prev.max_clients);
            channel.max_clients_limited = channel.max_clients_limited.or(prev.max_clients_limited);
            channel.password_protected = channel.password_protected.or(prev.password_protected);
        }
        if let Some(codec) = incoming_codecs
            .get(&channel.id)
            .copied()
            .or_else(|| existing_codecs.get(&channel.id).copied())
        {
            merged_codecs.insert(channel.id, codec);
        }
        merged_channels.push(channel);
    }

    (merged_channels, merged_codecs)
}

pub(super) fn merge_clients(
    incoming_clients: Vec<ClientView>,
    previous_clients: &[ClientView],
    prune_departed: bool,
    self_channel_id: u64,
) -> Vec<ClientView> {
    let prev_by_id: HashMap<i32, &ClientView> = previous_clients
        .iter()
        .map(|client| (client.id, client))
        .collect();
    let mut merged = Vec::with_capacity(incoming_clients.len());
    let mut seen = HashSet::with_capacity(incoming_clients.len());

    for mut client in incoming_clients {
        seen.insert(client.id);
        if let Some(prev) = prev_by_id.get(&client.id) {
            if client.nickname.is_empty() && !prev.nickname.is_empty() {
                client.nickname = prev.nickname.clone();
            }
            if client.uid.is_empty() && !prev.uid.is_empty() {
                client.uid = prev.uid.clone();
            }
            if client.channel_id == 0 && prev.channel_id != 0 {
                client.channel_id = prev.channel_id;
            }
            client.input_muted = client.input_muted.or(prev.input_muted);
            client.output_muted = client.output_muted.or(prev.output_muted);
            client.away = client.away.or(prev.away);
            if client.away != Some(false) {
                client.away_message = client.away_message.or_else(|| prev.away_message.clone());
            }
        }
        merged.push(client);
    }

    if !prune_departed {
        for prev in previous_clients {
            if !seen.contains(&prev.id)
                && prev.channel_id != self_channel_id
                && prev.channel_id != 0
            {
                merged.push(prev.clone());
            }
        }
    }

    merged
}

pub(super) fn parse_channel_metadata(
    rows: &[HashMap<String, String>],
) -> HashMap<u64, ChannelMetadata> {
    let mut channels = HashMap::new();
    for row in rows {
        let Some(cid) = row.get("cid").and_then(|value| value.parse::<u64>().ok()) else {
            continue;
        };
        let max_clients_limited = match row
            .get("channel_flag_maxclients_unlimited")
            .map(String::as_str)
        {
            Some("0") => Some(true),
            Some("1") => Some(false),
            _ => None,
        };
        let password_protected = match row.get("channel_flag_password").map(String::as_str) {
            Some("0") => Some(false),
            Some("1") => Some(true),
            _ => None,
        };
        channels.insert(
            cid,
            ChannelMetadata {
                order: row
                    .get("channel_order")
                    .and_then(|value| value.parse::<u64>().ok()),
                description: row
                    .get("channel_description")
                    .or_else(|| row.get("channel_topic"))
                    .cloned(),
                codec: row
                    .get("channel_codec")
                    .and_then(|value| value.parse::<i32>().ok()),
                max_clients: row
                    .get("channel_maxclients")
                    .and_then(|value| value.parse::<u16>().ok()),
                max_clients_limited,
                password_protected,
            },
        );
    }
    channels
}

pub(super) fn channel_view(
    channel: ChannelInfo,
    metadata: Option<&ChannelMetadata>,
) -> ChannelView {
    let metadata = metadata.cloned().unwrap_or_default();
    ChannelView {
        icon_id: channel.icon_id,
        id: channel.id,
        parent_id: channel.parent_id,
        order: metadata.order.or(Some(channel.order)),
        name: channel.name,
        description: crate::text_format::bbcode_to_markdown(
            metadata
                .description
                .as_deref()
                .unwrap_or(&channel.description),
        ),
        max_clients: metadata.max_clients.or(channel.max_clients),
        max_clients_limited: metadata.max_clients_limited.or(channel.max_clients_limited),
        password_protected: metadata.password_protected.or(channel.password_protected),
    }
}

/// clientlist 与欢迎目录快照按 id 合并：clientlist 的标志更新，目录的
/// 频道更准（clientlist 在部分 TS6 服务器上缺 `cid`）。两边都有的成员
/// 用 clientlist 行、频道取目录；只在目录里的成员原样保留。
pub(super) fn merged_clients(
    listed: Vec<ClientInfo>,
    directory: Vec<ClientInfo>,
) -> Vec<ClientView> {
    let mut directory_channels: HashMap<i32, u64> = directory
        .iter()
        .filter(|info| info.channel_id != 0)
        .map(|info| (info.id, info.channel_id))
        .collect();
    let mut rows: Vec<ClientView> = listed.into_iter().map(ClientView::from).collect();
    for row in &mut rows {
        if row.channel_id == 0
            && let Some(channel_id) = directory_channels.remove(&row.id)
        {
            row.channel_id = channel_id;
        }
    }
    let mut seen: HashSet<i32> = rows.iter().map(|row| row.id).collect();
    for info in directory {
        if seen.insert(info.id) {
            rows.push(ClientView::from(info));
        }
    }
    rows
}

/// TeamSpeak 转义的常用子集；上游没导出 `unescape`，clientinfo 的原始行需要它。
pub(super) fn unescape_text(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut chars = raw.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('s') => out.push(' '),
            Some('p') => out.push('|'),
            Some('/') => out.push('/'),
            Some('\\') => out.push('\\'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

impl From<ClientInfo> for ClientView {
    fn from(info: ClientInfo) -> Self {
        Self {
            id: info.id,
            nickname: info.nickname,
            uid: info.uid,
            channel_id: info.channel_id,
            input_muted: info.input_muted,
            output_muted: info.output_muted,
            away: info.away,
            away_message: info.away_message,
            client_type: ClientType::Standard,
            app_name: None,
            app_version: None,
            capabilities: Vec::new(),
            bot_commands: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::test_support::*;

    #[test]
    fn merged_clients_prefers_listed_flags_but_directory_channels() {
        let listed = vec![client_info(55, 0, "x414"), client_info(61, 0, "probe")];
        let directory = vec![client_info(55, 770, "x414")];
        let rows = merged_clients(listed, directory);
        assert_eq!(rows.len(), 2);
        let x414 = rows.iter().find(|row| row.id == 55).unwrap();
        assert_eq!(x414.channel_id, 770);
        // 目录里没有的自己这行也保留，等 clientinfo 补频道。
        assert_eq!(rows.iter().find(|row| row.id == 61).unwrap().channel_id, 0);
    }

    #[test]
    fn merged_clients_keeps_directory_only_members() {
        let directory = vec![client_info(55, 770, "x414")];
        let rows = merged_clients(Vec::new(), directory);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].channel_id, 770);
    }

    #[test]
    fn unescape_text_handles_common_teamseek_escapes() {
        assert_eq!(unescape_text("Fl\\sSpeak"), "Fl Speak");
        // \| 不是转义序列（管道走 \p），按未知转义原样保留。
        assert_eq!(unescape_text("a\\/b\\|c\\\\d"), "a/b\\|c\\d");
        assert_eq!(unescape_text("普通\\s名字"), "普通 名字");
        // 未知转义原样保留，尾部孤立反斜杠不吞字。
        assert_eq!(unescape_text("a\\qb"), "a\\qb");
        assert_eq!(unescape_text("tail\\"), "tail\\");
    }

    #[test]
    fn channel_flags_codec_and_public_metadata_are_parsed() {
        let mut first = HashMap::new();
        first.insert("cid".to_string(), "7".to_string());
        first.insert("channel_order".to_string(), "3".to_string());
        first.insert("channel_topic".to_string(), "Welcome".to_string());
        first.insert(
            "channel_description".to_string(),
            "Full description".to_string(),
        );
        first.insert("channel_maxclients".to_string(), "25".to_string());
        first.insert(
            "channel_flag_maxclients_unlimited".to_string(),
            "0".to_string(),
        );
        first.insert("channel_flag_password".to_string(), "1".to_string());
        first.insert("channel_codec".to_string(), "5".to_string());
        let mut second = HashMap::new();
        second.insert("cid".to_string(), "8".to_string());
        second.insert(
            "channel_flag_maxclients_unlimited".to_string(),
            "1".to_string(),
        );
        second.insert("channel_codec".to_string(), "not-a-number".to_string());
        let mut third = HashMap::new();
        third.insert("channel_codec".to_string(), "4".to_string());

        let metadata = parse_channel_metadata(&[first, second, third]);
        let first = metadata.get(&7).expect("first channel");
        assert_eq!(first.order, Some(3));
        assert_eq!(first.description.as_deref(), Some("Full description"));
        assert_eq!(first.codec, Some(5));
        assert_eq!(first.max_clients, Some(25));
        assert_eq!(first.max_clients_limited, Some(true));
        assert_eq!(first.password_protected, Some(true));

        let second = metadata.get(&8).expect("second channel");
        assert_eq!(second.codec, None);
        assert_eq!(second.max_clients_limited, Some(false));
        assert_eq!(metadata.len(), 2);
    }

    #[test]
    fn channel_view_merges_directory_rows_with_optional_flags() {
        let channel = ChannelInfo {
            icon_id: Some(3763318035),
            id: 9,
            parent_id: 2,
            order: 1,
            name: "Lobby".to_string(),
            description: String::new(),
            password_protected: None,
            max_clients: None,
            max_clients_limited: None,
            codec: None,
        };
        let metadata = ChannelMetadata {
            order: Some(12),
            description: Some("Public topic".to_string()),
            max_clients: Some(10),
            max_clients_limited: Some(true),
            password_protected: Some(false),
            ..ChannelMetadata::default()
        };

        let view = channel_view(channel.clone(), Some(&metadata));
        assert_eq!(view.icon_id, Some(3763318035));
        assert_eq!(view.order, Some(12));
        assert_eq!(view.description, "Public topic");
        assert_eq!(view.max_clients, Some(10));
        assert_eq!(view.max_clients_limited, Some(true));
        assert_eq!(view.password_protected, Some(false));

        let fallback = channel_view(channel, None);
        assert_eq!(fallback.order, Some(1));
        assert_eq!(fallback.password_protected, None);
    }
}
