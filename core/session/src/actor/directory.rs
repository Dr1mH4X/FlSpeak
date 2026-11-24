use super::snapshot::*;
use super::*;

pub(super) type SnapshotPair = (Vec<ChannelView>, Vec<ClientView>);

pub(super) struct SnapshotCommit {
    pub(super) emitted: Option<SnapshotPair>,
    pub(super) self_uid: Option<String>,
}

pub(super) struct ClientFlagsPatch<'a> {
    pub(super) channel_id: u64,
    pub(super) input_muted: Option<bool>,
    pub(super) output_muted: Option<bool>,
    pub(super) away: Option<bool>,
    pub(super) away_message: Option<&'a String>,
}

/// 目录快照、频道编解码与成员权限探测缓存状态。
#[derive(Default)]
pub(super) struct DirectoryState {
    last_snapshot: Option<(Vec<ChannelView>, Vec<ClientView>)>,
    known_clients: HashMap<i32, ClientView>,
    channel_codecs: HashMap<u64, i32>,
    channel_list_allowed: Option<bool>,
    channel_meta_allowed: Option<bool>,
    client_list_allowed: Option<bool>,
    subscribed_all_channels: bool,
    self_server_groups: Vec<String>,
    channel_tools: crate::channel_tools::ChannelTools,
}

impl DirectoryState {
    pub(super) fn reset_on_disconnect(&mut self) {
        self.last_snapshot = None;
        self.known_clients.clear();
        self.channel_codecs.clear();
        self.reset_permissions();
        self.subscribed_all_channels = false;
        self.self_server_groups.clear();
        self.channel_tools = Default::default();
    }

    pub(super) fn reset_on_channel_change(&mut self) {
        self.reset_permissions();
    }

    pub(super) fn reset_permissions(&mut self) {
        self.channel_list_allowed = None;
        self.channel_meta_allowed = None;
        self.client_list_allowed = None;
    }

    pub(super) fn channel_list_allowed(&self) -> Option<bool> {
        self.channel_list_allowed
    }

    pub(super) fn set_channel_list_allowed(&mut self, allowed: bool) {
        self.channel_list_allowed = Some(allowed);
    }

    pub(super) fn channel_meta_allowed(&self) -> Option<bool> {
        self.channel_meta_allowed
    }

    pub(super) fn set_channel_meta_allowed(&mut self, allowed: bool) {
        self.channel_meta_allowed = Some(allowed);
    }

    pub(super) fn client_list_allowed(&self) -> Option<bool> {
        self.client_list_allowed
    }

    pub(super) fn set_client_list_allowed(&mut self, allowed: bool) {
        self.client_list_allowed = Some(allowed);
    }

    pub(super) fn set_subscribed_all_channels(&mut self, subscribed: bool) {
        self.subscribed_all_channels = subscribed;
    }

    pub(super) fn should_prune_departed(&self, from_directory_only: bool) -> bool {
        !from_directory_only
            || self.subscribed_all_channels
            || self.client_list_allowed == Some(false)
    }

    pub(super) fn normalize_server_groups(groups: &[String]) -> Vec<String> {
        let mut normalized: Vec<String> =
            groups.iter().filter(|g| !g.is_empty()).cloned().collect();
        normalized.sort();
        normalized.dedup();
        normalized
    }

    pub(super) fn set_self_server_groups(&mut self, groups: &[String]) {
        self.self_server_groups = Self::normalize_server_groups(groups);
    }

    pub(super) fn sync_self_server_groups(&mut self, groups: &[String]) -> bool {
        let normalized = Self::normalize_server_groups(groups);
        if self.self_server_groups != normalized {
            self.self_server_groups = normalized;
            self.reset_permissions();
            true
        } else {
            false
        }
    }

    pub(super) fn channel_codec(&self, channel_id: u64) -> Option<i32> {
        self.channel_codecs.get(&channel_id).copied()
    }

    pub(super) fn set_channel_codec(&mut self, channel_id: u64, codec: i32) {
        self.channel_codecs.insert(channel_id, codec);
    }

    pub(super) fn replace_channel_codecs(&mut self, codecs: HashMap<u64, i32>) {
        self.channel_codecs = codecs;
    }

    pub(super) fn channel_codecs(&self) -> &HashMap<u64, i32> {
        &self.channel_codecs
    }

    pub(super) fn channel_tools_mut(&mut self) -> &mut crate::channel_tools::ChannelTools {
        &mut self.channel_tools
    }

    pub(super) fn snapshot_slices(&self) -> (&[ChannelView], &[ClientView]) {
        self.last_snapshot
            .as_ref()
            .map(|(channels, clients)| (channels.as_slice(), clients.as_slice()))
            .unwrap_or((&[], &[]))
    }

    pub(super) fn snapshot_clone(&self) -> Option<SnapshotPair> {
        self.last_snapshot.clone()
    }

    pub(super) fn known_client_row(&self, id: i32) -> Option<ClientView> {
        self.known_clients.get(&id).cloned().or_else(|| {
            self.last_snapshot
                .as_ref()
                .and_then(|(_, clients)| clients.iter().find(|client| client.id == id).cloned())
        })
    }

    pub(super) fn upsert_client(&mut self, client: ClientView) {
        self.known_clients.insert(client.id, client.clone());
        if let Some((_, clients)) = &mut self.last_snapshot {
            match clients.iter_mut().find(|existing| existing.id == client.id) {
                Some(existing) => *existing = client,
                None => {
                    clients.push(client);
                    clients.sort_by_key(|existing| existing.id);
                }
            }
        }
    }

    pub(super) fn remove_client(&mut self, id: i32) {
        self.known_clients.remove(&id);
        if let Some((_, clients)) = &mut self.last_snapshot {
            clients.retain(|client| client.id != id);
        }
    }

    pub(super) fn update_client_flags(
        &mut self,
        id: i32,
        self_client_id: Option<i32>,
        patch: ClientFlagsPatch<'_>,
    ) {
        let apply = |row: &mut ClientView| {
            if patch.channel_id != 0 && (Some(id) != self_client_id || row.channel_id == 0) {
                row.channel_id = patch.channel_id;
            }
            if let Some(value) = patch.input_muted {
                row.input_muted = Some(value);
            }
            if let Some(value) = patch.output_muted {
                row.output_muted = Some(value);
            }
            if let Some(value) = patch.away {
                row.away = Some(value);
            }
            if let Some(value) = patch.away_message {
                row.away_message = Some(value.clone());
            }
        };
        if let Some(row) = self.known_clients.get_mut(&id) {
            apply(row);
        }
        if let Some((_, clients)) = &mut self.last_snapshot
            && let Some(row) = clients.iter_mut().find(|client| client.id == id)
        {
            apply(row);
        }
    }

    pub(super) fn snapshot_client_uid(&self, id: i32) -> Option<String> {
        self.last_snapshot.as_ref().and_then(|(_, clients)| {
            clients
                .iter()
                .find(|client| client.id == id && !client.uid.is_empty())
                .map(|client| client.uid.clone())
        })
    }

    pub(super) fn find_non_empty_client_uid(&self, id: i32) -> Option<String> {
        self.snapshot_client_uid(id).or_else(|| {
            self.known_clients
                .get(&id)
                .filter(|client| !client.uid.is_empty())
                .map(|client| client.uid.clone())
        })
    }

    pub(super) fn find_client_uid_by_u64(&self, target_id: u64) -> Option<String> {
        self.last_snapshot
            .as_ref()
            .and_then(|(_, clients)| {
                clients
                    .iter()
                    .find(|client| client.id as u64 == target_id)
                    .map(|client| client.uid.clone())
            })
            .or_else(|| {
                i32::try_from(target_id)
                    .ok()
                    .and_then(|id| self.known_clients.get(&id))
                    .map(|client| client.uid.clone())
            })
    }

    pub(super) fn snapshot_client_channel(&self, clid: i32) -> Option<u64> {
        self.last_snapshot
            .as_ref()
            .and_then(|(_, clients)| clients.iter().find(|c| c.id == clid))
            .map(|client| client.channel_id)
            .filter(|channel| *channel != 0)
    }

    fn sync_clients_cache(
        &mut self,
        clients: &[ClientView],
        self_client_id: Option<i32>,
    ) -> Option<String> {
        self.known_clients = clients
            .iter()
            .map(|client| (client.id, client.clone()))
            .collect();
        self_client_id
            .and_then(|self_id| self.known_clients.get(&self_id))
            .filter(|me| !me.uid.is_empty())
            .map(|me| me.uid.clone())
    }

    pub(super) fn commit_snapshot(
        &mut self,
        channels: Vec<ChannelView>,
        clients: Vec<ClientView>,
        force: bool,
        self_client_id: Option<i32>,
    ) -> SnapshotCommit {
        let self_uid = self.sync_clients_cache(&clients, self_client_id);
        let changed = force
            || self
                .last_snapshot
                .as_ref()
                .is_none_or(|(old_channels, old_clients)| {
                    old_channels != &channels || old_clients != &clients
                });
        let emitted = if changed {
            self.last_snapshot = Some((channels.clone(), clients.clone()));
            Some((channels, clients))
        } else {
            None
        };
        SnapshotCommit { emitted, self_uid }
    }

    pub(super) fn update_snapshot_clients_if_changed(
        &mut self,
        clients: Vec<ClientView>,
        self_client_id: Option<i32>,
    ) -> SnapshotCommit {
        let Some((channels, old_clients)) = self.last_snapshot.as_ref() else {
            return SnapshotCommit {
                emitted: None,
                self_uid: None,
            };
        };
        if old_clients == &clients {
            return SnapshotCommit {
                emitted: None,
                self_uid: None,
            };
        }
        let channels = channels.clone();
        let self_uid = self.sync_clients_cache(&clients, self_client_id);
        self.last_snapshot = Some((channels.clone(), clients.clone()));
        SnapshotCommit {
            emitted: Some((channels, clients)),
            self_uid,
        }
    }

    #[cfg(test)]
    pub(super) fn set_snapshot_for_test(
        &mut self,
        channels: Vec<ChannelView>,
        clients: Vec<ClientView>,
    ) {
        self.last_snapshot = Some((channels, clients));
    }

    #[cfg(test)]
    pub(super) fn insert_known_client_for_test(&mut self, client: ClientView) {
        self.known_clients.insert(client.id, client);
    }

    #[cfg(test)]
    pub(super) fn subscribed_all_channels(&self) -> bool {
        self.subscribed_all_channels
    }

    #[cfg(test)]
    pub(super) fn self_server_groups(&self) -> &[String] {
        &self.self_server_groups
    }
}

impl Actor {
    pub(super) async fn list_channels(&mut self) -> Result<Vec<ChannelView>, SessionError> {
        let client = self.connected()?;
        let directory = self.read_channel_directory(&client, false).await?;
        if let Some(err) = directory.metadata_error {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("failed to read channel flags: {err}"),
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
        if let Some(ref dir_clients) = directory {
            self.sync_avatar_hashes_from_clients(dir_clients);
        }
        if self.directory.client_list_allowed() == Some(false) {
            let Some(directory) = directory else {
                return Err(SessionError::Protocol(
                    "member directory is not ready".into(),
                ));
            };
            let mut rows: Vec<ClientView> = directory.into_iter().map(ClientView::from).collect();
            self.ensure_self_row(client, &mut rows).await;
            return Ok((rows, true));
        }

        let listed = tsclient_rs::listClients(client).await;
        let (mut rows, from_directory_only) = match listed {
            Ok(listed) => {
                self.directory.set_client_list_allowed(true);
                // clientlist 不请求头像标志（始终为 None）；仅在显式带回非空 hash 时补充记录，绝不用 None 覆盖目录状态。
                for info in &listed {
                    if let Some(ref hash) = info.avatar_hash
                        && !hash.is_empty()
                        && !info.uid.is_empty()
                    {
                        self.record_avatar_hash(&info.uid, Some(hash.clone()), false);
                    }
                }
                (merged_clients(listed, directory.unwrap_or_default()), false)
            }
            Err(err) => {
                if is_permission_denied(&err) {
                    self.directory.set_client_list_allowed(false);
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
                            message: format!("failed to complete the self row: {err}"),
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
        let uid = info
            .get("client_unique_identifier")
            .cloned()
            .unwrap_or_default();
        if !uid.is_empty()
            && let Some(raw_hash) = info.get("client_flag_avatar")
        {
            let hash = (!raw_hash.is_empty()).then(|| raw_hash.clone());
            self.record_avatar_hash(&uid, hash, false);
        }
        let view = ClientView {
            id: self_id,
            nickname: info
                .get("client_nickname")
                .map(|value| unescape_text(value))
                .unwrap_or_default(),
            uid,
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
            is_streaming: info
                .get("client_is_streaming")
                .is_some_and(|value| value == "1"),
            client_type: ClientType::FlSpeak,
            app_name: Some("FlSpeak".into()),
            app_version: Some(env!("CARGO_PKG_VERSION").into()),
            capabilities: self.open_protocol.effective_identity().capabilities,
            bot_commands: Vec::new(),
            bot_commands_loaded: false,
            bot_command_prefix: None,
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
                    .reconnect
                    .last_nickname()
                    .map(str::to_string)
                    .unwrap_or_default(),
                uid: String::new(),
                channel_id: self.self_channel_id,
                input_muted: Some(local.input_muted),
                output_muted: Some(local.output_muted),
                away: Some(local.away),
                away_message: None,
                is_streaming: false,
                client_type: ClientType::FlSpeak,
                app_name: Some("FlSpeak".into()),
                app_version: Some(env!("CARGO_PKG_VERSION").into()),
                capabilities: self.open_protocol.effective_identity().capabilities,
                bot_commands: Vec::new(),
                bot_commands_loaded: false,
                bot_command_prefix: None,
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
                        message: format!("failed to read channel flags: {err}"),
                    });
                }
                Some((directory.channels, directory.codecs.unwrap_or_default()))
            }
            Err(err) => {
                failures.push(format!("channel directory: {err}"));
                None
            }
        };

        let incoming_clients = match self.read_clients(&client).await {
            Ok((clients, from_directory_only)) => Some((clients, from_directory_only)),
            Err(err) => {
                failures.push(format!("member list: {err}"));
                None
            }
        };

        if failures.len() == 2 {
            return Err(SessionError::Protocol(failures.join("; ")));
        }
        for failure in failures {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("failed to refresh part of the directory: {failure}"),
            });
        }

        let (channels, clients) = self.prepare_merged_snapshot(incoming_channels, incoming_clients);

        let mut self_codec = self.directory.channel_codec(self.self_channel_id);
        if self_codec.is_none() && self.self_channel_id != 0 {
            match fetch_channel_codec(&client, self.self_channel_id).await {
                Ok(found) => {
                    self_codec = found;
                    if let Some(found) = found {
                        self.directory
                            .set_channel_codec(self.self_channel_id, found);
                    }
                }
                Err(err) => self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("failed to read the current channel codec: {err}"),
                }),
            }
        }

        if let Some(self_id) = self.self_client_id
            && let Some(me) = clients.iter().find(|client| client.id == self_id)
        {
            // cid=0 的行说明这路数据没带频道，不能拿它重置自己的真实频道。
            if me.channel_id != 0 && me.channel_id != self.self_channel_id {
                self.apply_self_channel(me.channel_id, self_codec);
                if self.open_protocol.self_channel_id() == 0 {
                    self.open_protocol_self_moved(me.channel_id);
                }
            } else {
                self.apply_channel_codec(self_codec);
            }
        }

        self.commit_snapshot(channels, clients, force);
        Ok(())
    }

    pub(super) async fn subscribe_all_channels(&mut self) {
        let Ok(client) = self.connected() else {
            return;
        };
        match client.exec_command("channelsubscribeall", 5_000).await {
            Ok(()) => {
                self.directory.set_subscribed_all_channels(true);
            }
            Err(err) => {
                self.directory.set_subscribed_all_channels(false);
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("failed to subscribe to all channels; only members in the current subscription scope will be received: {err}"),
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
        if self.directory.channel_list_allowed() == Some(false) {
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
                return Err(SessionError::Protocol(
                    "channel directory is not ready".into(),
                ));
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
                self.directory.set_channel_list_allowed(true);
                channels
            }
            Err(err) => {
                if is_permission_denied(&err) {
                    self.directory.set_channel_list_allowed(false);
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

        if self.directory.channel_meta_allowed() == Some(false) {
            return Ok(directory_from_channels(channels, None));
        }

        match fetch_channel_metadata(client).await {
            Ok(metadata) => {
                self.directory.set_channel_meta_allowed(true);
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
                    channels: order_channels(
                        channels
                            .into_iter()
                            .map(|channel| {
                                let id = channel.id;
                                channel_view(channel, metadata.get(&id))
                            })
                            .collect(),
                    ),
                    codecs: (!codecs.is_empty()).then_some(codecs),
                    metadata_error: None,
                })
            }
            Err(err) => {
                if is_permission_denied(&err) {
                    self.directory.set_channel_meta_allowed(false);
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
                message: format!("failed to refresh channels or members: {err}"),
            });
        }
    }

    pub(super) async fn on_self_moved(&mut self, channel_id: u64) {
        if self.self_channel_id == channel_id {
            return;
        }
        self.directory.reset_on_channel_change();
        let mut codec = self.directory.channel_codec(channel_id);
        if codec.is_none()
            && channel_id != 0
            && let Some(client) = self.client.clone()
        {
            match fetch_channel_codec(&client, channel_id).await {
                Ok(found) => {
                    codec = found;
                    if let Some(found) = found {
                        self.directory.set_channel_codec(channel_id, found);
                    }
                }
                Err(err) => self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("failed to read codec for channel {channel_id}: {err}"),
                }),
            }
        }
        self.apply_self_channel(channel_id, codec);
        if channel_id != 0 {
            self.open_protocol_self_moved(channel_id);
        }
    }

    pub(super) fn handle_directory_snapshot(&mut self, snapshot: tsclient_rs::DirectorySnapshot) {
        self.sync_avatar_hashes_from_clients(&snapshot.clients);
        let mut snapshot_self_channel = None;
        if let Some(self_id) = self.self_client_id
            && let Some(me) = snapshot.clients.iter().find(|c| c.id == self_id)
        {
            self.directory.sync_self_server_groups(&me.server_groups);
            if me.channel_id != 0 {
                snapshot_self_channel = Some(me.channel_id);
            }
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
        if self.self_channel_id == 0
            && let Some(channel_id) = snapshot_self_channel
        {
            let codec = self.directory.channel_codec(channel_id);
            self.apply_self_channel(channel_id, codec);
        } else if self.self_channel_id != 0
            && let Some(codec) = self.directory.channel_codec(self.self_channel_id)
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
        let (prev_channels, prev_clients) = self.directory.snapshot_slices();

        let channels = match incoming_channels {
            Some((raw_channels, raw_codecs)) => {
                let (merged_channels, merged_codecs) = merge_channels(
                    raw_channels,
                    raw_codecs,
                    prev_channels,
                    self.directory.channel_codecs(),
                );
                let prev_clients = prev_clients.to_vec();
                self.directory.replace_channel_codecs(merged_codecs);
                (merged_channels, prev_clients)
            }
            None => (prev_channels.to_vec(), prev_clients.to_vec()),
        };

        let (channels, prev_clients) = channels;
        let mut clients = match incoming_clients {
            Some((raw_clients, from_directory_only)) => {
                let prune_departed = self.directory.should_prune_departed(from_directory_only);
                merge_clients(
                    raw_clients,
                    &prev_clients,
                    prune_departed,
                    self.self_channel_id,
                )
            }
            None => prev_clients,
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
        self.open_protocol_sync_peers(&clients);
        self.sync_client_channels_from_snapshot(&clients);
        let commit = self
            .directory
            .commit_snapshot(channels, clients, force, self.self_client_id);
        if let Some(uid) = commit.self_uid {
            self.self_uid = Some(uid);
        }
        if let Some((channels, clients)) = commit.emitted {
            self.emit(SessionEvent::Snapshot { channels, clients });
        }
        self.sync_streams_view();
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
        actor.directory.subscribed_all_channels = true;
        actor.open_protocol.on_connected(1, 5, Instant::now());
        actor.open_protocol.on_plugin_command(
            &PluginCommandEvent {
                name: tsclient_rs::open_protocol::IDENTITY_PLUGIN.into(),
                data: serde_json::json!({
                    "v": 1,
                    "action": "announce_ack",
                    "client_type": "flspeak",
                    "app_name": "FlSpeak",
                    "app_version": "0.1.12",
                    "capabilities": ["chat"],
                })
                .to_string(),
                invoker_id: 2,
                invoker_name: "Peer".into(),
                invoker_uid: "peer-uid".into(),
            },
            None,
            Instant::now(),
        );
        actor.directory.channel_codecs.insert(5, 4);
        actor.directory.channel_codecs.insert(99, 5);
        actor.directory.last_snapshot = Some((
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
                    is_streaming: false,
                    client_type: ClientType::FlSpeak,
                    app_name: Some("FlSpeak".into()),
                    app_version: Some(env!("CARGO_PKG_VERSION").into()),
                    capabilities: Vec::new(),
                    bot_commands: Vec::new(),
                    bot_commands_loaded: false,
                    bot_command_prefix: None,
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
                    is_streaming: false,
                    client_type: ClientType::FlSpeak,
                    app_name: Some("FlSpeak".into()),
                    app_version: Some("0.1.12".into()),
                    capabilities: vec!["chat".into()],
                    bot_commands: Vec::new(),
                    bot_commands_loaded: false,
                    bot_command_prefix: None,
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
        assert!(!actor.directory.channel_codecs.contains_key(&99));
        assert_eq!(actor.directory.channel_codecs.get(&5), Some(&4));

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
        assert_eq!(actor.directory.channel_codecs.get(&8), Some(&5));
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
        actor.directory.subscribed_all_channels = false;
        actor.directory.client_list_allowed = Some(true);
        actor.directory.last_snapshot = Some((
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
        let (_, clients) = actor.directory.last_snapshot.as_ref().unwrap();
        assert_eq!(clients.iter().map(|c| c.id).collect::<Vec<_>>(), vec![1, 3]);

        // 当 clientlist 被禁用时，按目录快照裁剪所有不在快照里的成员。
        actor.directory.client_list_allowed = Some(false);
        actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
            channels: vec![
                channel_info(5, 0, 0, "Current"),
                channel_info(9, 0, 5, "Other"),
            ],
            clients: vec![client_info(1, 5, "Self")],
            truncated: false,
        });
        let (_, clients) = actor.directory.last_snapshot.as_ref().unwrap();
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
                assert_eq!(actor.directory.channel_list_allowed, Some(false));
                assert_eq!(actor.directory.client_list_allowed, Some(false));
                assert_eq!(actor.directory.channel_meta_allowed, None);

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

    #[test]
    fn snapshot_avatar_sync_folds_clones_and_keeps_some_hash() {
        let mut actor = audio_actor();
        actor.active_server_id = Some("a.example:9987".into());
        let mut events = actor.events.subscribe();

        actor.handle_directory_snapshot(tsclient_rs::DirectorySnapshot {
            channels: Vec::new(),
            clients: vec![
                ClientInfo {
                    uid: "shared-uid".into(),
                    avatar_hash: None,
                    ..client_info(2, 5, "CloneA")
                },
                ClientInfo {
                    uid: "shared-uid".into(),
                    avatar_hash: Some("clone_hash".into()),
                    ..client_info(3, 5, "CloneB")
                },
            ],
            truncated: false,
        });

        assert_eq!(
            actor.media.avatar_hash("shared-uid"),
            Some(&Some("clone_hash".to_string()))
        );
        assert!(matches!(
            events.try_recv(),
            Ok(SessionEvent::Snapshot { .. })
        ));
        assert!(events.try_recv().is_err());
    }

    #[test]
    fn directory_state_reset_on_disconnect_and_channel_change() {
        let mut state = DirectoryState::default();
        state.set_snapshot_for_test(
            Vec::new(),
            vec![ClientView::from(client_info(1, 5, "Self"))],
        );
        state.insert_known_client_for_test(ClientView::from(client_info(1, 5, "Self")));
        state.set_channel_codec(5, 4);
        state.set_channel_list_allowed(false);
        state.set_channel_meta_allowed(false);
        state.set_client_list_allowed(false);
        state.set_subscribed_all_channels(true);
        state.set_self_server_groups(&["6".into()]);

        state.reset_on_channel_change();
        assert_eq!(state.channel_list_allowed(), None);
        assert_eq!(state.channel_meta_allowed(), None);
        assert_eq!(state.client_list_allowed(), None);
        assert!(state.last_snapshot.is_some());
        assert!(!state.known_clients.is_empty());
        assert_eq!(state.channel_codec(5), Some(4));
        assert!(state.subscribed_all_channels());
        assert_eq!(state.self_server_groups(), &["6".to_string()]);

        state.reset_on_disconnect();
        assert!(state.last_snapshot.is_none());
        assert!(state.known_clients.is_empty());
        assert!(state.channel_codecs().is_empty());
        assert_eq!(state.channel_list_allowed(), None);
        assert_eq!(state.channel_meta_allowed(), None);
        assert_eq!(state.client_list_allowed(), None);
        assert!(!state.subscribed_all_channels());
        assert!(state.self_server_groups().is_empty());
    }

    #[test]
    fn directory_state_server_groups_normalization_and_conditional_reset() {
        let mut state = DirectoryState::default();
        state.set_channel_list_allowed(false);
        state.set_channel_meta_allowed(false);
        state.set_client_list_allowed(false);

        assert!(state.sync_self_server_groups(&[
            "8".into(),
            String::new(),
            "6".into(),
            "8".into(),
        ]));
        assert_eq!(
            state.self_server_groups(),
            &["6".to_string(), "8".to_string()]
        );
        assert_eq!(state.channel_list_allowed(), None);

        state.set_channel_list_allowed(false);
        state.set_channel_meta_allowed(true);
        state.set_client_list_allowed(false);
        assert!(!state.sync_self_server_groups(&["8".into(), "6".into()]));
        assert_eq!(state.channel_list_allowed(), Some(false));
        assert_eq!(state.channel_meta_allowed(), Some(true));
        assert_eq!(state.client_list_allowed(), Some(false));

        assert!(state.sync_self_server_groups(&["6".into(), "7".into(), "8".into()]));
        assert_eq!(state.channel_list_allowed(), None);
        assert_eq!(state.channel_meta_allowed(), None);
        assert_eq!(state.client_list_allowed(), None);
    }

    #[test]
    fn directory_state_snapshot_commit_client_cache_and_prune_matrix() {
        let mut state = DirectoryState::default();
        let mut self_client = ClientView::from(client_info(1, 5, "Self"));
        self_client.uid = "self-uid".into();
        let mut peer_client = ClientView::from(client_info(3, 5, "Peer3"));
        peer_client.uid = "peer3-uid".into();

        let commit = state.commit_snapshot(Vec::new(), vec![self_client.clone()], false, Some(1));
        assert!(commit.emitted.is_some());
        assert_eq!(commit.self_uid.as_deref(), Some("self-uid"));

        let commit_dup =
            state.commit_snapshot(Vec::new(), vec![self_client.clone()], false, Some(1));
        assert!(commit_dup.emitted.is_none());

        let commit_forced = state.commit_snapshot(Vec::new(), vec![self_client], true, Some(1));
        assert!(commit_forced.emitted.is_some());

        state.upsert_client(peer_client);
        let mut mid_client = ClientView::from(client_info(2, 5, "Peer2"));
        mid_client.uid = "peer2-uid".into();
        state.upsert_client(mid_client);
        let (_, clients) = state.snapshot_slices();
        assert_eq!(
            clients.iter().map(|c| c.id).collect::<Vec<_>>(),
            vec![1, 2, 3]
        );

        // 自身已有非零 channel_id 时，ClientUpdated 不得用新 channel_id 覆盖（需走 ClientMoved）。
        state.update_client_flags(
            1,
            Some(1),
            ClientFlagsPatch {
                channel_id: 99,
                input_muted: Some(true),
                output_muted: None,
                away: None,
                away_message: None,
            },
        );
        assert_eq!(state.snapshot_client_channel(1), Some(5));
        assert_eq!(
            state.known_client_row(1).and_then(|c| c.input_muted),
            Some(true)
        );

        state.update_client_flags(
            2,
            Some(1),
            ClientFlagsPatch {
                channel_id: 9,
                input_muted: None,
                output_muted: Some(true),
                away: Some(true),
                away_message: Some(&"brb".to_string()),
            },
        );
        assert_eq!(state.snapshot_client_channel(2), Some(9));
        assert_eq!(
            state.find_client_uid_by_u64(2).as_deref(),
            Some("peer2-uid")
        );

        state.remove_client(2);
        assert!(state.known_client_row(2).is_none());

        assert!(state.should_prune_departed(false));
        assert!(!state.should_prune_departed(true));
        state.set_subscribed_all_channels(true);
        assert!(state.should_prune_departed(true));
        state.set_subscribed_all_channels(false);
        state.set_client_list_allowed(false);
        assert!(state.should_prune_departed(true));
    }
}
