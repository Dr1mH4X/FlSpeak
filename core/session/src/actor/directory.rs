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
    use super::super::messaging::split_text_message;
    use super::*;
    use crate::actor::test_support::*;

    struct RefusedDirectory {
        calls: Arc<std::sync::Mutex<Vec<String>>>,
    }

    impl tsclient_rs::CommandMiddleware for RefusedDirectory {
        fn wrap(&self, _: TestCommandHandler) -> TestCommandHandler {
            let calls = Arc::clone(&self.calls);
            Arc::new(move |command| {
                calls.lock().unwrap().push(command);
                Box::pin(async {
                    Err(tsclient_rs::Error::ServerError {
                        id: "2568".into(),
                        server_message: "insufficient client permissions".into(),
                        extra_message: None,
                    })
                })
            })
        }
    }

    #[tokio::test]
    async fn telemetry_only_samples_existing_directory_requests() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let calls = Arc::new(std::sync::Mutex::new(Vec::new()));
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(RefusedDirectory {
                            calls: Arc::clone(&calls),
                        })],
                        ..Default::default()
                    },
                );
                client.mark_connected();
                let mut actor = audio_actor();
                actor.client = Some(Arc::new(client));
                actor.state = SessionState::Connected {
                    client_id: 1,
                    channel_id: 1,
                };
                actor.network_monitor = Some(crate::network::NetworkMonitor::new());
                let mut events = actor.events.subscribe();
                let (commands, receiver) = mpsc::unbounded_channel();
                let task = tokio::task::spawn_local(async move {
                    actor.run(receiver).await;
                });
                tokio::time::sleep(Duration::from_millis(5_100)).await;
                let idle_calls = calls.lock().unwrap().clone();
                let (reply, result) = oneshot::channel();
                commands
                    .send(SessionCommand::ListChannels { reply })
                    .unwrap();
                assert!(result.await.unwrap().is_err());
                let telemetry = loop {
                    if let SessionEvent::Network(telemetry) = events.recv().await.unwrap() {
                        break telemetry;
                    }
                };
                let directory_calls = calls.lock().unwrap().clone();
                commands.send(SessionCommand::Shutdown).unwrap();
                task.await.unwrap();
                assert!(idle_calls.is_empty());
                assert_eq!(directory_calls.len(), 1);
                assert!(directory_calls[0].starts_with("channellist "));
                assert_eq!(telemetry.probes_sent, 1);
                assert_eq!(telemetry.probes_failed, 0);
                assert!(telemetry.round_trip_ms.is_some());
            })
            .await;
    }

    #[tokio::test]
    async fn network_sampling_sends_through_the_actor_queue() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let calls = Arc::new(std::sync::Mutex::new(Vec::new()));
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(RefusedDirectory {
                            calls: Arc::clone(&calls),
                        })],
                        ..Default::default()
                    },
                );
                client.mark_connected();
                let mut actor = audio_actor();
                actor.client = Some(Arc::new(client));
                actor.self_client_id = Some(7);
                let (commands, receiver) = mpsc::unbounded_channel();
                let task = tokio::task::spawn_local(async move {
                    actor.run(receiver).await;
                });

                let (reply, result) = oneshot::channel();
                commands
                    .send(SessionCommand::SampleNetwork { reply })
                    .unwrap();
                assert!(result.await.unwrap().is_err());
                assert_eq!(
                    calls.lock().unwrap().last().map(String::as_str),
                    Some("getconnectioninfo clid=7")
                );

                commands.send(SessionCommand::Shutdown).unwrap();
                task.await.unwrap();
            })
            .await;
    }

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
