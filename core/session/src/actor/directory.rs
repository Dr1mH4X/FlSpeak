use super::snapshot::*;
use super::*;

impl Actor {
    pub(super) async fn list_channels(&mut self) -> Result<Vec<ChannelView>, SessionError> {
        let client = self.connected()?;
        let directory = self.read_channel_directory(&client, false).await?;
        if let Some(err) = directory.metadata_error {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("读取频道标志失败: {err}"),
            });
        }
        Ok(directory.channels)
    }

    pub(super) async fn list_clients(&mut self) -> Result<Vec<ClientView>, SessionError> {
        let client = self.connected()?;
        let (mut rows, _) = self.read_clients(&client).await?;
        self.enrich_clients(&mut rows);
        rows.sort_by_key(|client| client.id);
        Ok(rows)
    }

    /// 成员列表 = clientlist 与欢迎目录快照的合并，再保证自己这一行可信。
    ///
    /// 部分 TS6 服务器的 clientlist 行缺 `cid`（解析成 0），而欢迎目录的
    /// `channelclientlist` 行频道是准的；反过来目录可能漏掉后来进出的成员。
    /// 两边按 id 合并：clientlist 的标志新，目录的频道准。
    /// 返回 `(成员列表, 是否仅来自内存目录快照)`。
    pub(super) async fn read_clients(
        &mut self,
        client: &Arc<Client>,
    ) -> Result<(Vec<ClientView>, bool), SessionError> {
        let directory = client.directory_snapshot().map(|snapshot| snapshot.clients);
        if self.client_list_allowed == Some(false) {
            let Some(directory) = directory else {
                return Err(SessionError::Protocol("成员目录尚未就绪".into()));
            };
            let mut rows: Vec<ClientView> = directory.into_iter().map(ClientView::from).collect();
            self.ensure_self_row(client, &mut rows).await;
            return Ok((rows, true));
        }

        let listed = tsclient_rs::listClients(client).await;
        let (mut rows, from_directory_only) = match listed {
            Ok(listed) => {
                self.client_list_allowed = Some(true);
                (merged_clients(listed, directory.unwrap_or_default()), false)
            }
            Err(err) => {
                if is_permission_denied(&err) {
                    self.client_list_allowed = Some(false);
                    let Some(directory) = directory else {
                        return Err(protocol_error(err));
                    };
                    (directory.into_iter().map(ClientView::from).collect(), true)
                } else {
                    let directory = directory.unwrap_or_default();
                    // 目录还没同步完（None 或空）时同样拿不到成员，回退到原错误。
                    if directory.is_empty() {
                        return Err(protocol_error(err));
                    }
                    (directory.into_iter().map(ClientView::from).collect(), true)
                }
            }
        };
        self.ensure_self_row(client, &mut rows).await;
        Ok((rows, from_directory_only))
    }

    /// 自身行修补：本地已知频道时无网补齐；首次未知用 `whoami` 学习。
    ///
    /// TS6 服务器对推送进来的自己的行缺省 `cid`（官方客户端从别的渠道知道
    /// 自己在哪），访客又常被拒 `clientinfo`；`whoami` 免权限且带
    /// `client_channel_id`。补全结果由 refresh 的交叉检查写回会话状态。
    async fn ensure_self_row(&mut self, client: &Arc<Client>, rows: &mut Vec<ClientView>) {
        let Some(self_id) = self.self_client_id else {
            return;
        };
        let known = rows.iter().find(|row| row.id == self_id);
        if known.is_some_and(|row| row.channel_id != 0) {
            self.patch_self_row(rows);
            return;
        }
        if self.self_channel_id != 0 {
            self.patch_self_row(rows);
            return;
        }
        let info = match client.exec_command_with_response("whoami", 5_000).await {
            Ok(rows) => rows.into_iter().next().unwrap_or_default(),
            Err(err) => {
                // 部分服务器禁 whoami 但允许查自己，回退 clientinfo。
                match tsclient_rs::getClientInfo(client, self_id).await {
                    Ok(info) => info,
                    Err(_) => {
                        self.emit(SessionEvent::Log {
                            level: "debug".into(),
                            message: format!("自身行补全失败: {err}"),
                        });
                        return;
                    }
                }
            }
        };
        // whoami 的键是 client_*（client_channel_id 即 cid）；clientinfo 用 cid。
        let channel_id = info
            .get("client_channel_id")
            .or_else(|| info.get("cid"))
            .and_then(|value| value.parse::<u64>().ok())
            .filter(|value| *value != 0);
        let Some(channel_id) = channel_id else {
            return;
        };
        let view = ClientView {
            id: self_id,
            nickname: info
                .get("client_nickname")
                .map(|value| unescape_text(value))
                .unwrap_or_default(),
            uid: info
                .get("client_unique_identifier")
                .cloned()
                .unwrap_or_default(),
            channel_id,
            input_muted: info
                .get("client_input_muted")
                .or_else(|| info.get("client_flag_input_muted"))
                .map(|value| value == "1"),
            output_muted: info
                .get("client_output_muted")
                .or_else(|| info.get("client_flag_output_muted"))
                .map(|value| value == "1"),
            away: info.get("client_away").map(|value| value == "1"),
            away_message: info
                .get("client_away_message")
                .filter(|value| !value.is_empty())
                .map(|value| unescape_text(value)),
            client_type: ClientType::FlSpeak,
            app_name: Some("FlSpeak".into()),
            app_version: Some(env!("CARGO_PKG_VERSION").into()),
            capabilities: self_capabilities(),
            bot_commands: None,
        };
        match rows.iter_mut().find(|row| row.id == self_id) {
            Some(row) => *row = view,
            None => rows.push(view),
        }
        self.patch_self_row(rows);
    }

    /// 已知自己频道时的无网修补：目录推送对 TS6 服务器永远给 0 频道的自己，
    /// 用会话状态里确认过的频道与本地语音状态按 dirty 掩码合并补齐，缺行则合成。
    fn patch_self_row(&mut self, rows: &mut Vec<ClientView>) {
        let Some(self_id) = self.self_client_id else {
            return;
        };
        let local = VoiceFlagsSnapshot::from_voice_state(&self.voice_state);
        match rows.iter_mut().find(|row| row.id == self_id) {
            Some(row) => {
                if row.channel_id == 0 {
                    row.channel_id = self.self_channel_id;
                }
                let resolved = self.voice_report.resolve_self_flags(
                    local,
                    row.input_muted,
                    row.output_muted,
                    row.away,
                );
                row.input_muted = Some(resolved.input_muted);
                row.output_muted = Some(resolved.output_muted);
                row.away = Some(resolved.away);
            }
            None => rows.push(ClientView {
                id: self_id,
                nickname: self
                    .last_target
                    .as_ref()
                    .map(|target| target.nickname.clone())
                    .unwrap_or_default(),
                uid: String::new(),
                channel_id: self.self_channel_id,
                input_muted: Some(local.input_muted),
                output_muted: Some(local.output_muted),
                away: Some(local.away),
                away_message: None,
                client_type: ClientType::FlSpeak,
                app_name: Some("FlSpeak".into()),
                app_version: Some(env!("CARGO_PKG_VERSION").into()),
                capabilities: self_capabilities(),
                bot_commands: None,
            }),
        }
    }

    pub(super) async fn refresh_snapshot(&mut self, force: bool) -> Result<(), SessionError> {
        let Some(client) = self.client.clone() else {
            return Ok(());
        };
        let mut failures = Vec::new();

        let incoming_channels = match self.read_channel_directory(&client, true).await {
            Ok(directory) => {
                if let Some(err) = directory.metadata_error {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("读取频道标志失败: {err}"),
                    });
                }
                Some((directory.channels, directory.codecs.unwrap_or_default()))
            }
            Err(err) => {
                failures.push(format!("频道目录: {err}"));
                None
            }
        };

        let incoming_clients = match self.read_clients(&client).await {
            Ok((clients, from_directory_only)) => Some((clients, from_directory_only)),
            Err(err) => {
                failures.push(format!("成员列表: {err}"));
                None
            }
        };

        if failures.len() == 2 {
            return Err(SessionError::Protocol(failures.join("; ")));
        }
        for failure in failures {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("刷新部分目录失败: {failure}"),
            });
        }

        let (channels, clients) = self.prepare_merged_snapshot(incoming_channels, incoming_clients);

        let mut self_codec = self.channel_codecs.get(&self.self_channel_id).copied();
        if self_codec.is_none() && self.self_channel_id != 0 {
            match fetch_channel_codec(&client, self.self_channel_id).await {
                Ok(found) => {
                    self_codec = found;
                    if let Some(found) = found {
                        self.channel_codecs.insert(self.self_channel_id, found);
                    }
                }
                Err(err) => self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("读取当前频道 codec 失败: {err}"),
                }),
            }
        }

        if let Some(self_id) = self.self_client_id
            && let Some(me) = clients.iter().find(|client| client.id == self_id)
        {
            // cid=0 的行说明这路数据没带频道，不能拿它重置自己的真实频道。
            if me.channel_id != 0 && me.channel_id != self.self_channel_id {
                self.apply_self_channel(me.channel_id, self_codec);
            } else {
                self.apply_channel_codec(self_codec);
            }
        }

        self.commit_snapshot(channels, clients, force);
        self.sync_stream_channel().await;
        Ok(())
    }

    pub(super) async fn subscribe_all_channels(&mut self) {
        let Ok(client) = self.connected() else {
            return;
        };
        match client.exec_command("channelsubscribeall", 5_000).await {
            Ok(()) => {
                self.subscribed_all_channels = true;
            }
            Err(err) => {
                self.subscribed_all_channels = false;
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("订阅全部频道失败，将只接收当前订阅范围内的成员事件: {err}"),
                });
            }
        }
    }

    pub(super) async fn wait_for_welcome_directory(&self, client: &Client) {
        // 上游 0.2.0 提供事件驱动的目录就绪等待（channellistfinished）；保留旧轮询
        // 实现的 500ms 上限，服务器迟迟不发目录时跳过等待，不阻塞连接后的初始化。
        let _ = tokio::time::timeout(
            Duration::from_millis(500),
            client.wait_directory_ready(None),
        )
        .await;
    }

    async fn read_channel_directory(
        &mut self,
        client: &Client,
        probe_whoami_on_skip: bool,
    ) -> Result<ChannelDirectory, SessionError> {
        if self.channel_list_allowed == Some(false) {
            if probe_whoami_on_skip && self.network_monitor.is_some() {
                let started = Instant::now();
                let probe = client.exec_command_with_response("whoami", 5_000).await;
                let reached = matches!(&probe, Ok(_) | Err(tsclient_rs::Error::ServerError { .. }));
                self.record_network_probe(started, reached);
            }
            let Some(snapshot) = client
                .directory_snapshot()
                .filter(|snapshot| !snapshot.channels.is_empty())
            else {
                return Err(SessionError::Protocol("频道目录尚未就绪".into()));
            };
            return Ok(directory_from_channels(snapshot.channels, None));
        }

        // 复用已有目录请求采样，避免额外探测占用语音发送所在的 actor。
        let started = Instant::now();
        let result = tsclient_rs::listChannels(client).await;
        // 权限拒绝也是服务器的有效回复，不能当作网络丢失。
        let reached = matches!(&result, Ok(_) | Err(tsclient_rs::Error::ServerError { .. }));
        self.record_network_probe(started, reached);

        let channels = match result {
            Ok(channels) => {
                self.channel_list_allowed = Some(true);
                channels
            }
            Err(err) => {
                if is_permission_denied(&err) {
                    self.channel_list_allowed = Some(false);
                }
                let Some(snapshot) = client
                    .directory_snapshot()
                    .filter(|snapshot| !snapshot.channels.is_empty())
                else {
                    return Err(protocol_error(err));
                };
                return Ok(directory_from_channels(snapshot.channels, None));
            }
        };

        if self.channel_meta_allowed == Some(false) {
            return Ok(directory_from_channels(channels, None));
        }

        match fetch_channel_metadata(client).await {
            Ok(metadata) => {
                self.channel_meta_allowed = Some(true);
                let mut codecs: HashMap<u64, i32> = metadata
                    .iter()
                    .filter_map(|(id, channel)| channel.codec.map(|codec| (*id, codec)))
                    .collect();
                codecs.extend(
                    channels
                        .iter()
                        .filter_map(|channel| channel.codec.map(|codec| (channel.id, codec))),
                );
                Ok(ChannelDirectory {
                    channels: channels
                        .into_iter()
                        .map(|channel| {
                            let id = channel.id;
                            channel_view(channel, metadata.get(&id))
                        })
                        .collect(),
                    codecs: (!codecs.is_empty()).then_some(codecs),
                    metadata_error: None,
                })
            }
            Err(err) => {
                if is_permission_denied(&err) {
                    self.channel_meta_allowed = Some(false);
                    Ok(directory_from_channels(channels, None))
                } else {
                    Ok(directory_from_channels(
                        channels,
                        Some(protocol_error(err).to_string()),
                    ))
                }
            }
        }
    }

    pub(super) async fn poll_snapshot(&mut self) {
        if !matches!(self.state, SessionState::Connected { .. }) {
            return;
        }
        if let Err(err) = self.refresh_snapshot(false).await {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("刷新频道/成员失败: {err}"),
            });
        }
    }

    pub(super) async fn on_self_moved(&mut self, channel_id: u64) {
        if self.self_channel_id == channel_id {
            return;
        }
        self.reset_directory_permissions();
        let mut codec = self.channel_codecs.get(&channel_id).copied();
        if codec.is_none()
            && channel_id != 0
            && let Some(client) = self.client.clone()
        {
            match fetch_channel_codec(&client, channel_id).await {
                Ok(found) => {
                    codec = found;
                    if let Some(found) = found {
                        self.channel_codecs.insert(channel_id, found);
                    }
                }
                Err(err) => self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("读取频道 {channel_id} codec 失败: {err}"),
                }),
            }
        }
        self.apply_self_channel(channel_id, codec);
        if channel_id != 0 {
            self.maybe_announce_identity().await;
        }
    }

    pub(super) fn reset_directory_permissions(&mut self) {
        self.channel_list_allowed = None;
        self.channel_meta_allowed = None;
        self.client_list_allowed = None;
    }

    pub(super) fn normalize_server_groups(groups: &[String]) -> Vec<String> {
        let mut normalized: Vec<String> =
            groups.iter().filter(|g| !g.is_empty()).cloned().collect();
        normalized.sort();
        normalized.dedup();
        normalized
    }

    pub(super) fn sync_self_server_groups(&mut self, groups: &[String]) {
        let normalized = Self::normalize_server_groups(groups);
        if self.self_server_groups != normalized {
            self.self_server_groups = normalized;
            self.reset_directory_permissions();
        }
    }

    pub(super) fn handle_directory_snapshot(&mut self, snapshot: tsclient_rs::DirectorySnapshot) {
        if let Some(self_id) = self.self_client_id
            && let Some(me) = snapshot.clients.iter().find(|c| c.id == self_id)
        {
            self.sync_self_server_groups(&me.server_groups);
        }
        let incoming_codecs: HashMap<u64, i32> = snapshot
            .channels
            .iter()
            .filter_map(|channel| channel.codec.map(|codec| (channel.id, codec)))
            .collect();
        let incoming_channels: Vec<ChannelView> = snapshot
            .channels
            .into_iter()
            .map(|channel| channel_view(channel, None))
            .collect();
        let incoming_clients: Vec<ClientView> =
            snapshot.clients.into_iter().map(ClientView::from).collect();
        let (channels, clients) = self.prepare_merged_snapshot(
            Some((incoming_channels, incoming_codecs)),
            Some((incoming_clients, true)),
        );
        if self.self_channel_id != 0
            && let Some(codec) = self.channel_codecs.get(&self.self_channel_id).copied()
            && codec != self.current_codec
        {
            self.apply_channel_codec(Some(codec));
        }
        self.commit_snapshot(channels, clients, false);
    }

    fn prepare_merged_snapshot(
        &mut self,
        incoming_channels: Option<(Vec<ChannelView>, HashMap<u64, i32>)>,
        incoming_clients: Option<(Vec<ClientView>, bool)>,
    ) -> (Vec<ChannelView>, Vec<ClientView>) {
        let (prev_channels, prev_clients) = self
            .last_snapshot
            .as_ref()
            .map(|(channels, clients)| (channels.as_slice(), clients.as_slice()))
            .unwrap_or((&[], &[]));

        let channels = match incoming_channels {
            Some((raw_channels, raw_codecs)) => {
                let (merged_channels, merged_codecs) = merge_channels(
                    raw_channels,
                    raw_codecs,
                    prev_channels,
                    &self.channel_codecs,
                );
                self.channel_codecs = merged_codecs;
                merged_channels
            }
            None => prev_channels.to_vec(),
        };

        let mut clients = match incoming_clients {
            Some((raw_clients, from_directory_only)) => {
                let prune_departed = !from_directory_only
                    || self.subscribed_all_channels
                    || self.client_list_allowed == Some(false);
                merge_clients(
                    raw_clients,
                    prev_clients,
                    prune_departed,
                    self.self_channel_id,
                )
            }
            None => prev_clients.to_vec(),
        };
        // TS6 服务器推给自己的行永远缺频道，用会话状态补齐后再统一补充身份信息。
        self.patch_self_row(&mut clients);
        self.enrich_clients(&mut clients);
        clients.sort_by_key(|client| client.id);
        (channels, clients)
    }

    pub(super) fn commit_snapshot(
        &mut self,
        channels: Vec<ChannelView>,
        clients: Vec<ClientView>,
        force: bool,
    ) {
        let changed = force
            || self
                .last_snapshot
                .as_ref()
                .is_none_or(|(old_channels, old_clients)| {
                    old_channels != &channels || old_clients != &clients
                });
        if changed {
            self.last_snapshot = Some((channels.clone(), clients.clone()));
            self.emit(SessionEvent::Snapshot { channels, clients });
        }
    }
}

async fn fetch_channel_metadata(
    client: &Client,
) -> Result<HashMap<u64, ChannelMetadata>, tsclient_rs::Error> {
    let rows = client
        .exec_command_with_response("channellist -flags -codec", 5_000)
        .await?;
    Ok(parse_channel_metadata(&rows))
}

fn is_permission_denied(err: &tsclient_rs::Error) -> bool {
    matches!(err, tsclient_rs::Error::ServerError { id, .. } if id == "2568")
}

async fn fetch_channel_codec(
    client: &Client,
    channel_id: u64,
) -> Result<Option<i32>, SessionError> {
    let rows = client
        .exec_command_with_response(&format!("channelinfo cid={channel_id}"), 5_000)
        .await
        .map_err(protocol_error)?;
    Ok(rows
        .first()
        .and_then(|row| row.get("channel_codec"))
        .and_then(|value| value.parse::<i32>().ok()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::test_support::*;

    fn channel_info(id: u64, parent_id: u64, order: u64, name: &str) -> ChannelInfo {
        ChannelInfo {
            id,
            parent_id,
            order,
            name: name.to_string(),
            description: String::new(),
            password_protected: None,
            max_clients: None,
            max_clients_limited: None,
            codec: None,
            icon_id: None,
        }
    }

    #[test]
    fn directory_snapshot_merges_channels_codecs_and_skips_unchanged_diff() {
        let mut actor = audio_actor();
        actor.self_client_id = Some(1);
        actor.self_channel_id = 5;
        actor.subscribed_all_channels = true;
        actor.peer_identities.insert(
            "peer-uid".into(),
            CachedPeerIdentity {
                client_type: ClientType::FlSpeak,
                app_name: "FlSpeak".into(),
                app_version: "0.1.12".into(),
                capabilities: vec!["chat".into()],
            },
        );
        actor.channel_codecs.insert(5, 4);
        actor.channel_codecs.insert(99, 5);
        actor.last_snapshot = Some((
            vec![
                ChannelView {
                    icon_id: Some(77),
                    id: 5,
                    parent_id: 0,
                    order: Some(0),
                    name: "Lobby".into(),
                    description: String::new(),
                    max_clients: Some(12),
                    max_clients_limited: Some(true),
                    password_protected: Some(true),
                },
                ChannelView {
                    icon_id: None,
                    id: 99,
                    parent_id: 0,
                    order: Some(5),
                    name: "Deleted".into(),
                    description: String::new(),
                    max_clients: None,
                    max_clients_limited: None,
                    password_protected: None,
                },
            ],
            vec![
                ClientView {
                    id: 1,
                    nickname: "Self".into(),
                    uid: "self-uid".into(),
                    channel_id: 5,
                    input_muted: None,
                    output_muted: None,
                    away: None,
                    away_message: None,
                    client_type: ClientType::FlSpeak,
                    app_name: Some("FlSpeak".into()),
                    app_version: Some(env!("CARGO_PKG_VERSION").into()),
                    capabilities: Vec::new(),
                    bot_commands: None,
                },
                ClientView {
                    id: 2,
                    nickname: "Peer".into(),
                    uid: "peer-uid".into(),
                    channel_id: 5,
                    input_muted: Some(false),
                    output_muted: Some(false),
                    away: Some(false),
                    away_message: None,
                    client_type: ClientType::FlSpeak,
                    app_name: Some("FlSpeak".into()),
                    app_version: Some("0.1.12".into()),
                    capabilities: vec!["chat".into()],
                    bot_commands: None,
                },
            ],
        ));
        let mut events = actor.events.subscribe();

        // 等价的 DirectorySnapshot（可选元数据为 None，TS6 自身 cid=0）：合并后无差异，不发事件。
        actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
            channels: vec![channel_info(5, 0, 0, "Lobby")],
            clients: vec![
                ClientInfo {
                    uid: "self-uid".into(),
                    ..client_info(1, 0, "Self")
                },
                ClientInfo {
                    uid: "peer-uid".into(),
                    input_muted: Some(false),
                    output_muted: Some(false),
                    away: Some(false),
                    ..client_info(2, 5, "Peer")
                },
            ],
            truncated: false,
        });
        assert!(events.try_recv().is_ok()); // 频道 99 被删除，触发一次更新
        assert!(!actor.channel_codecs.contains_key(&99));
        assert_eq!(actor.channel_codecs.get(&5), Some(&4));

        // 再次推送完全相同的快照，命中 Diff 跳过广播。
        actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
            channels: vec![channel_info(5, 0, 0, "Lobby")],
            clients: vec![
                ClientInfo {
                    uid: "self-uid".into(),
                    ..client_info(1, 0, "Self")
                },
                ClientInfo {
                    uid: "peer-uid".into(),
                    input_muted: Some(false),
                    output_muted: Some(false),
                    away: Some(false),
                    ..client_info(2, 5, "Peer")
                },
            ],
            truncated: false,
        });
        assert!(events.try_recv().is_err());

        // 频道改名 + 新建频道 + 保留既有 Some 扩展字段 + 保留 peer identity。
        actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
            channels: vec![
                channel_info(5, 0, 0, "Main Lobby"),
                ChannelInfo {
                    codec: Some(5),
                    password_protected: Some(true),
                    ..channel_info(8, 5, 0, "Sub")
                },
            ],
            clients: vec![
                ClientInfo {
                    uid: "self-uid".into(),
                    ..client_info(1, 0, "Self")
                },
                ClientInfo {
                    uid: "peer-uid".into(),
                    input_muted: Some(true),
                    ..client_info(2, 5, "Peer")
                },
            ],
            truncated: false,
        });
        let Some(SessionEvent::Snapshot { channels, clients }) = events.try_recv().ok() else {
            panic!("expected Snapshot event after real change");
        };
        assert_eq!(channels.len(), 2);
        assert_eq!(channels[0].name, "Main Lobby");
        assert_eq!(channels[0].icon_id, Some(77));
        assert_eq!(channels[0].max_clients, Some(12));
        assert_eq!(channels[0].max_clients_limited, Some(true));
        assert_eq!(channels[0].password_protected, Some(true));
        assert_eq!(channels[1].id, 8);
        assert_eq!(channels[1].password_protected, Some(true));
        assert_eq!(actor.channel_codecs.get(&8), Some(&5));
        let self_row = clients.iter().find(|c| c.id == 1).unwrap();
        assert_eq!(self_row.channel_id, 5);
        let peer_row = clients.iter().find(|c| c.id == 2).unwrap();
        assert_eq!(peer_row.input_muted, Some(true));
        assert_eq!(peer_row.app_name.as_deref(), Some("FlSpeak"));
    }

    #[test]
    fn directory_snapshot_preserves_unsubscribed_channels_only_when_clientlist_active() {
        let mut actor = audio_actor();
        actor.self_client_id = Some(1);
        actor.self_channel_id = 5;
        actor.subscribed_all_channels = false;
        actor.client_list_allowed = Some(true);
        actor.last_snapshot = Some((
            vec![
                ChannelView {
                    icon_id: None,
                    id: 5,
                    parent_id: 0,
                    order: Some(0),
                    name: "Current".into(),
                    description: String::new(),
                    max_clients: None,
                    max_clients_limited: None,
                    password_protected: None,
                },
                ChannelView {
                    icon_id: None,
                    id: 9,
                    parent_id: 0,
                    order: Some(5),
                    name: "Other".into(),
                    description: String::new(),
                    max_clients: None,
                    max_clients_limited: None,
                    password_protected: None,
                },
            ],
            vec![
                ClientView::from(client_info(1, 5, "Self")),
                ClientView::from(client_info(2, 5, "LeftCurrent")),
                ClientView::from(client_info(3, 9, "UnsubscribedPeer")),
            ],
        ));

        // channelsubscribeall 失败但 clientlist 可用时：当前频道离场者裁剪，未订阅频道成员保留。
        actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
            channels: vec![
                channel_info(5, 0, 0, "Current"),
                channel_info(9, 0, 5, "Other"),
            ],
            clients: vec![client_info(1, 5, "Self")],
            truncated: false,
        });
        let (_, clients) = actor.last_snapshot.as_ref().unwrap();
        assert_eq!(clients.iter().map(|c| c.id).collect::<Vec<_>>(), vec![1, 3]);

        // 当 clientlist 被禁用时，按目录快照裁剪所有不在快照里的成员。
        actor.client_list_allowed = Some(false);
        actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
            channels: vec![
                channel_info(5, 0, 0, "Current"),
                channel_info(9, 0, 5, "Other"),
            ],
            clients: vec![client_info(1, 5, "Self")],
            truncated: false,
        });
        let (_, clients) = actor.last_snapshot.as_ref().unwrap();
        assert_eq!(clients.iter().map(|c| c.id).collect::<Vec<_>>(), vec![1]);
    }

    struct SelectiveErrorMiddleware {
        calls: Arc<std::sync::Mutex<Vec<String>>>,
        deny_prefixes: Vec<&'static str>,
    }

    impl tsclient_rs::CommandMiddleware for SelectiveErrorMiddleware {
        fn wrap(&self, _: TestCommandHandler) -> TestCommandHandler {
            let calls = Arc::clone(&self.calls);
            let deny_prefixes = self.deny_prefixes.clone();
            Arc::new(move |command| {
                calls.lock().unwrap().push(command.clone());
                let denied = deny_prefixes
                    .iter()
                    .any(|prefix| command.starts_with(prefix));
                Box::pin(async move {
                    if denied {
                        Err(tsclient_rs::Error::ServerError {
                            id: "2568".into(),
                            server_message: "insufficient client permissions".into(),
                            extra_message: None,
                        })
                    } else {
                        // 用 ServerError 模拟服务器已应答但无数据行的探针，避免 5s 超时等待。
                        Err(tsclient_rs::Error::ServerError {
                            id: "0".into(),
                            server_message: "ok".into(),
                            extra_message: None,
                        })
                    }
                })
            })
        }
    }

    #[tokio::test]
    async fn permission_flags_skip_repeated_2568_queries_and_whoami_keeps_rtt_alive() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let calls = Arc::new(std::sync::Mutex::new(Vec::new()));
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(SelectiveErrorMiddleware {
                            calls: Arc::clone(&calls),
                            deny_prefixes: vec!["channellist ", "clientlist "],
                        })],
                        ..Default::default()
                    },
                );
                client.mark_connected();
                let mut actor = audio_actor();
                actor.client = Some(Arc::new(client));
                actor.self_client_id = Some(1);
                actor.network_monitor = Some(crate::network::NetworkMonitor::new());
                let mut events = actor.events.subscribe();

                // 首次拉取：channellist 与 clientlist 均被 2568 拒绝并独立标为 Some(false)。
                let client_ref = actor.client.clone().unwrap();
                let _ = actor.read_channel_directory(&client_ref, true).await;
                let _ = actor.read_clients(&client_ref).await;
                assert_eq!(actor.channel_list_allowed, Some(false));
                assert_eq!(actor.client_list_allowed, Some(false));
                assert_eq!(actor.channel_meta_allowed, None);

                // 清空记录，第二次轮询应跳过 channellist/clientlist，改用 whoami 测 RTT。
                calls.lock().unwrap().clear();
                let _ = actor.read_channel_directory(&client_ref, true).await;
                let _ = actor.read_clients(&client_ref).await;
                let second_round = calls.lock().unwrap().clone();
                assert_eq!(second_round.len(), 1);
                assert!(second_round[0].starts_with("whoami"));

                let mut network_events = Vec::new();
                let mut warn_logs = Vec::new();
                while let Ok(ev) = events.try_recv() {
                    match ev {
                        SessionEvent::Network(t) => network_events.push(t),
                        SessionEvent::Log { level, message } if level == "warn" => {
                            warn_logs.push(message);
                        }
                        _ => {}
                    }
                }
                assert!(warn_logs.is_empty());
                assert_eq!(network_events.len(), 2);
                assert_eq!(network_events[1].probes_sent, 2);
                assert_eq!(network_events[1].probes_failed, 0);
                assert!(network_events[1].round_trip_ms.is_some());
            })
            .await;
    }
}
