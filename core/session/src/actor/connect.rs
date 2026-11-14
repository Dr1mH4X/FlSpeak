use super::*;
use crate::streams;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const DISCONNECT_TIMEOUT: Duration = Duration::from_secs(5);
/// 连续握手超时达到这个次数就尝试提升身份等级。
const IDENTITY_TIMEOUTS_BEFORE_UPGRADE: u32 = 3;
const IDENTITY_STEP: i32 = 5;
const IDENTITY_MAX_LEVEL: i32 = 29;
/// 首轮成功会话前最多重试次数；成功连上过之后不限次。
const STARTUP_RECONNECT_LIMIT: u32 = 5;

impl Actor {
    pub(super) async fn register(
        &mut self,
        label: String,
        address: String,
    ) -> Result<ServerProfile, SessionError> {
        let mut registry = self.registry.clone();
        let profile = registry.register(&label, &address)?;
        SettingsManager::update(|settings| {
            settings.network.servers = registry.profiles().to_vec();
        })
        .map_err(SessionError::Storage)?;
        self.registry = registry;
        self.emit(SessionEvent::Servers(self.registry.profiles().to_vec()));
        Ok(profile)
    }

    pub(super) async fn remove(&mut self, id: String) -> Result<(), SessionError> {
        let mut registry = self.registry.clone();
        if !registry.remove(&id) {
            return Err(ServerError::NotRegistered(id).into());
        }
        SettingsManager::update(|settings| {
            settings.network.servers = registry.profiles().to_vec();
        })
        .map_err(SessionError::Storage)?;
        self.registry = registry;
        self.emit(SessionEvent::Servers(self.registry.profiles().to_vec()));
        crate::channel_icons::remove_server(&self.store_path, &id);
        if crate::server_icons::remove(&self.store_path, &mut self.server_icons, &id)
            .unwrap_or(false)
        {
            self.emit(SessionEvent::ServerIconUpdated {
                server_id: id,
                bytes: None,
            });
        }
        Ok(())
    }

    pub(super) fn update_server(
        &mut self,
        id: String,
        label: String,
        address: String,
    ) -> Result<ServerProfile, SessionError> {
        let mut registry = self.registry.clone();
        let profile = registry.update(&id, &label, &address)?;
        if profile.id != id
            && self.active_server_id.as_deref() == Some(&id)
            && !matches!(self.state, SessionState::Disconnected)
        {
            return Err(SessionError::Protocol(
                "修改服务器地址前请先断开连接".into(),
            ));
        }
        SettingsManager::update(|settings| {
            settings.network.servers = registry.profiles().to_vec();
        })
        .map_err(SessionError::Storage)?;
        self.registry = registry;
        self.emit(SessionEvent::Servers(self.registry.profiles().to_vec()));
        if profile.id != id {
            crate::channel_icons::move_server(&self.store_path, &id, &profile.id);
            if let Ok(Some(entry)) = crate::server_icons::move_entry(
                &self.store_path,
                &mut self.server_icons,
                &id,
                &profile.id,
            ) {
                self.emit(SessionEvent::ServerIconUpdated {
                    server_id: id,
                    bytes: None,
                });
                self.emit(SessionEvent::ServerIconUpdated {
                    server_id: profile.id.clone(),
                    bytes: Some(entry.bytes),
                });
            }
        }
        Ok(profile)
    }

    pub(super) async fn connect(
        &mut self,
        id: &str,
        nickname: &str,
        reconnecting: bool,
    ) -> Result<(), SessionError> {
        if self.client.is_some() {
            return Err(SessionError::Protocol("已经连接".into()));
        }

        let profile = match self.registry.require(id) {
            Ok(profile) => profile.clone(),
            Err(err) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "connect denied: id={id} reconnecting={reconnecting} error={err}"
                    ),
                });
                if reconnecting {
                    self.emit(SessionEvent::Denied {
                        message: err.to_string(),
                    });
                    self.schedule_reconnect();
                }
                return Err(err.into());
            }
        };

        let identity = store::load_identity(&identity_path(&self.store_path))
            .await
            .map_err(SessionError::Protocol)?;

        let resolved = match proto::resolve_target(&profile, &proto::DnsSrvResolver).await {
            Ok(resolved) => resolved,
            Err(err) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "connect prepare failed: host={}:{} reconnecting={reconnecting} error={err}",
                        profile.host, profile.port
                    ),
                });
                if reconnecting {
                    if matches!(err, ConnectError::Address(_) | ConnectError::Blocked { .. }) {
                        self.emit(SessionEvent::Denied {
                            message: err.to_string(),
                        });
                    } else {
                        self.emit(SessionEvent::Failed {
                            message: err.to_string(),
                        });
                    }
                    self.schedule_reconnect();
                }
                return Err(err.into());
            }
        };
        if resolved.via_srv {
            self.emit(SessionEvent::Log {
                level: "info".into(),
                message: format!(
                    "SRV {}:{} -> {}:{}",
                    profile.host, profile.port, resolved.target.host, resolved.target.port
                ),
            });
        }
        if !server::is_ip_literal(&resolved.target.host) {
            match tokio::time::timeout(
                Duration::from_secs(2),
                tokio::net::lookup_host((resolved.target.host.as_str(), resolved.target.port)),
            )
            .await
            {
                Ok(Ok(addrs)) => {
                    let list: Vec<String> = addrs.map(|addr| addr.to_string()).collect();
                    self.emit(SessionEvent::Log {
                        level: "info".into(),
                        message: format!(
                            "DNS {}:{} -> [{}]",
                            resolved.target.host,
                            resolved.target.port,
                            list.join(", ")
                        ),
                    });
                }
                Ok(Err(err)) => {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!(
                            "DNS {}:{} lookup failed: {err}",
                            resolved.target.host, resolved.target.port
                        ),
                    });
                }
                Err(_) => {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!(
                            "DNS {}:{} lookup timed out",
                            resolved.target.host, resolved.target.port
                        ),
                    });
                }
            }
        }
        let mut client = match proto::client(
            identity,
            &profile,
            &resolved.target,
            nickname,
            Arc::clone(&self.logger),
        ) {
            Ok(client) => client,
            Err(err) => {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "connect prepare failed: target={}:{} via_srv={} reconnecting={reconnecting} error={err}",
                        resolved.target.host, resolved.target.port, resolved.via_srv
                    ),
                });
                if reconnecting {
                    if matches!(err, ConnectError::Address(_) | ConnectError::Blocked { .. }) {
                        self.emit(SessionEvent::Denied {
                            message: err.to_string(),
                        });
                    } else {
                        self.emit(SessionEvent::Failed {
                            message: err.to_string(),
                        });
                    }
                    self.schedule_reconnect();
                }
                return Err(err.into());
            }
        };

        self.reset_directory_permissions();
        self.subscribed_all_channels = false;
        self.self_server_groups.clear();
        self.connection_epoch = self.connection_epoch.wrapping_add(1);
        self.epoch.store(self.connection_epoch, Ordering::SeqCst);
        let _ = self.disconnect_tx.send(self.connection_epoch);
        register_handlers(
            &client,
            self.events.clone(),
            self.signals.clone(),
            self.voice.incoming_sender(),
            self.connection_epoch,
            Arc::clone(&self.epoch),
        );
        if !reconnecting {
            self.set_state(SessionState::Connecting);
        }

        let outcome = tokio::time::timeout(CONNECT_TIMEOUT, async {
            client
                .connect()
                .await
                .map_err(|err| SessionError::Protocol(err.to_string()))?;
            client
                .wait_connected(None)
                .await
                .map_err(|err| SessionError::Protocol(err.to_string()))
        })
        .await;

        match outcome {
            Ok(Ok(())) => {
                let client_id = client.client_id();
                let channel_id = client.channel_id();
                self.client = Some(Arc::new(client));
                self.network_monitor = Some(crate::network::NetworkMonitor::new());
                self.transfer_target = Some(resolved.target);
                self.self_client_id = Some(client_id);
                self.self_channel_id = channel_id;
                self.active_server_id = Some(profile.id.clone());
                self.last_target = Some(ConnectTarget {
                    id: id.to_string(),
                    nickname: nickname.to_string(),
                });
                self.reconnect_attempt = 0;
                self.consecutive_timeouts = 0;
                self.ever_connected = true;
                self.last_snapshot = None;
                self.channel_codecs.clear();
                self.streams_supported = true;
                self.set_state(SessionState::Connected {
                    client_id,
                    channel_id,
                });
                self.subscribe_all_channels().await;
                if let Some(client) = self.client.clone() {
                    self.wait_for_welcome_directory(&client).await;
                    if let Some(snapshot) = client.directory_snapshot()
                        && let Some(me) = snapshot.clients.iter().find(|c| c.id == client_id)
                    {
                        self.self_server_groups = Self::normalize_server_groups(&me.server_groups);
                    }
                }
                if let Err(err) = self.refresh_snapshot(true).await {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: err.to_string(),
                    });
                }
                let mut welcome_message = None;
                if let Some(client) = self.client.clone() {
                    let mut info = client.server_info();
                    let need_fetch = info
                        .as_ref()
                        .is_none_or(|i| i.icon_id.is_none() || i.welcome_message.is_empty());
                    if need_fetch && let Ok(fetched) = client.get_server_info().await {
                        info = Some(fetched);
                    }
                    let icon_id = info.as_ref().and_then(|i| i.icon_id);
                    if !reconnecting && let Some(info) = info.as_ref() {
                        welcome_message = Self::build_welcome_message(
                            &profile,
                            &info.welcome_message,
                            now_millis(),
                        );
                    }
                    self.sync_server_icon(profile.id.clone(), icon_id);
                }
                self.maybe_announce_identity().await;
                self.start_voice();
                // 服务器端自己的标志在（重）连后是重置过的，把本地状态重新同步。
                self.report_voice_flags().await;
                self.emit_voice_state();
                self.emit_history().await;
                if let Some(welcome) = welcome_message {
                    self.emit(SessionEvent::TextMessage(welcome));
                }
                Ok(())
            }
            Ok(Err(err)) => {
                self.invalidate_handlers();
                let _ = client.disconnect().await;
                self.consecutive_timeouts = 0;
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "connect failed: target={}:{} via_srv={} reconnecting={reconnecting} error={err}",
                        resolved.target.host, resolved.target.port, resolved.via_srv
                    ),
                });
                if !reconnecting {
                    self.set_state(SessionState::Disconnected);
                } else {
                    self.emit(SessionEvent::Failed {
                        message: err.to_string(),
                    });
                    self.schedule_reconnect();
                }
                Err(err)
            }
            Err(_) => {
                self.invalidate_handlers();
                let _ = client.disconnect().await;
                self.consecutive_timeouts = self.consecutive_timeouts.saturating_add(1);
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "connect timed out ({}s): target={}:{} via_srv={} reconnecting={reconnecting}",
                        CONNECT_TIMEOUT.as_secs(),
                        resolved.target.host,
                        resolved.target.port,
                        resolved.via_srv
                    ),
                });
                if !reconnecting {
                    self.set_state(SessionState::Disconnected);
                } else {
                    self.emit(SessionEvent::Failed {
                        message: SessionError::Timeout.to_string(),
                    });
                }
                if self.consecutive_timeouts >= IDENTITY_TIMEOUTS_BEFORE_UPGRADE {
                    self.start_identity_upgrade().await;
                } else if reconnecting {
                    self.schedule_reconnect();
                }
                Err(SessionError::Timeout)
            }
        }
    }

    pub(super) async fn disconnect(&mut self) -> Result<(), SessionError> {
        self.auto_reconnect = false;
        self.last_target = None;
        if let Some(signal) = self.identity_upgrade.take() {
            signal.abort();
        }
        self.identity_upgrading = false;
        self.generation = self.generation.wrapping_add(1);
        self.invalidate_handlers();
        self.channel_codecs.clear();
        self.current_codec = VOICE_CODEC;
        self.reset_streams(StreamEndReason::Disconnected);
        let Some(client) = self.client.take() else {
            self.active_server_id = None;
            self.self_client_id = None;
            self.self_channel_id = 0;
            self.stop_voice();
            self.set_state(SessionState::Disconnected);
            return Ok(());
        };
        let outcome = tokio::time::timeout(DISCONNECT_TIMEOUT, client.disconnect()).await;
        self.active_server_id = None;
        self.self_client_id = None;
        self.self_channel_id = 0;
        self.stop_voice();
        self.last_snapshot = None;
        self.set_state(SessionState::Disconnected);
        match outcome {
            Ok(Ok(())) => Ok(()),
            Ok(Err(err)) => Err(SessionError::Protocol(err.to_string())),
            Err(_) => Err(SessionError::Timeout),
        }
    }
    pub(super) async fn on_connection_lost(&mut self, message: String, allow_reconnect: bool) {
        if self.client.is_none() {
            return;
        }
        self.invalidate_handlers();
        self.client = None;
        self.active_server_id = None;
        self.self_client_id = None;
        self.self_channel_id = 0;
        self.channel_codecs.clear();
        self.current_codec = VOICE_CODEC;
        self.reset_streams(StreamEndReason::Disconnected);
        self.stop_voice();
        let will_reconnect = allow_reconnect
            && self.auto_reconnect
            && self.last_target.is_some()
            && !self.identity_upgrading;
        if will_reconnect {
            self.schedule_reconnect();
        } else {
            self.set_state(SessionState::Disconnected);
        }
        self.emit(SessionEvent::Failed { message });
    }

    pub(super) async fn start_identity_upgrade(&mut self) {
        if self.identity_upgrading {
            return;
        }
        let path = identity_path(&self.store_path);
        let identity = match store::load_identity(&path).await {
            Ok(identity) => identity,
            Err(err) => {
                self.emit(SessionEvent::Failed {
                    message: format!("读取身份失败: {err}"),
                });
                self.schedule_reconnect();
                return;
            }
        };
        let from = identity.security_level();
        if from >= IDENTITY_MAX_LEVEL {
            self.schedule_reconnect();
            return;
        }
        let to = (from + IDENTITY_STEP).min(IDENTITY_MAX_LEVEL);
        let signal = Arc::new(AbortSignal::new());
        self.identity_upgrade = Some(Arc::clone(&signal));
        self.identity_upgrading = true;
        self.emit(SessionEvent::IdentityUpgrade { from, to });

        let commands = self.commands.clone();
        let generation = self.generation;
        let spawn = std::thread::Builder::new()
            .name("identity-upgrade".into())
            .spawn(move || {
                let result = (|| -> Result<i32, String> {
                    let runtime = tokio::runtime::Builder::new_current_thread()
                        .enable_all()
                        .build()
                        .map_err(|err| err.to_string())?;
                    runtime.block_on(async move {
                        let mut identity = identity;
                        identity
                            .upgrade_to_level(to, Some(&signal))
                            .await
                            .map_err(|err| err.to_string())?;
                        store::save_identity_atomic(&path, &identity).await?;
                        Ok(identity.security_level())
                    })
                })();
                let (level, error) = match result {
                    Ok(level) => (Some(level), None),
                    Err(err) => (None, Some(err)),
                };
                let _ = commands.send(SessionCommand::IdentityUpgradeFinished {
                    generation,
                    level,
                    error,
                });
            });
        if let Err(err) = spawn {
            self.identity_upgrading = false;
            self.identity_upgrade = None;
            self.emit(SessionEvent::Failed {
                message: format!("身份提升线程启动失败: {err}"),
            });
            self.schedule_reconnect();
        }
    }

    pub(super) fn schedule_reconnect(&mut self) {
        if !self.auto_reconnect || self.last_target.is_none() || self.identity_upgrading {
            return;
        }
        if !self.ever_connected && self.reconnect_attempt >= STARTUP_RECONNECT_LIMIT {
            self.auto_reconnect = false;
            self.set_state(SessionState::Disconnected);
            self.emit(SessionEvent::Failed {
                message: "重连失败：已达到最大尝试次数".into(),
            });
            return;
        }

        self.reconnect_attempt = self.reconnect_attempt.saturating_add(1);
        let delay = reconnect_delay(self.reconnect_attempt);
        self.set_state(SessionState::Reconnecting {
            attempt: self.reconnect_attempt,
            delay_ms: delay.as_millis() as u64,
        });

        let generation = self.generation;
        let commands = self.commands.clone();
        tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            let _ = commands.send(SessionCommand::RetryConnect { generation });
        });
    }
    pub(super) async fn teardown(&mut self) {
        self.auto_reconnect = false;
        if let Some(signal) = self.identity_upgrade.take() {
            signal.abort();
        }
        self.identity_upgrading = false;
        self.invalidate_handlers();
        if let Some(client) = self.client.take() {
            let _ = tokio::time::timeout(DISCONNECT_TIMEOUT, client.disconnect()).await;
        }
        self.stop_voice();
        self.channel_codecs.clear();
        self.current_codec = VOICE_CODEC;
        self.reset_streams(StreamEndReason::Disconnected);
        self.set_state(SessionState::Disconnected);
    }
    pub(super) fn invalidate_handlers(&mut self) {
        self.cancel_active_image();
        for request in self.pending_images.drain(..) {
            let _ = request.reply.send(Err(SessionError::NotConnected));
        }
        for (_, waiters) in self.in_flight_channel_icons.drain() {
            for reply in waiters {
                let _ = reply.send(Err(SessionError::NotConnected));
            }
        }
        self.active_server_icon_id = None;
        self.fetching_server_icon = None;
        self.audio_since = Instant::now();
        self.voice.set_meter_epoch(None);
        self.levels.set_epoch(None);
        self.channel_tools = Default::default();
        self.transfer_target = None;
        self.last_network_sample_error = None;
        self.peer_identities.clear();
        self.peer_commands.clear();
        self.commands_fetching.clear();
        self.ack_limiter.reset(Instant::now());
        self.announce_state.reset();
        self.reset_directory_permissions();
        self.subscribed_all_channels = false;
        self.self_server_groups.clear();
        self.connection_epoch = self.connection_epoch.wrapping_add(1);
        self.epoch.store(self.connection_epoch, Ordering::SeqCst);
        let _ = self.disconnect_tx.send(self.connection_epoch);
    }
}

pub(super) fn reconnect_delay(attempt: u32) -> Duration {
    match attempt {
        1 => Duration::from_secs(1),
        2 => Duration::from_secs(2),
        3 => Duration::from_secs(4),
        4 => Duration::from_secs(15),
        5 => Duration::from_secs(30),
        6 => Duration::from_secs(60),
        7 => Duration::from_secs(120),
        _ => Duration::from_secs(300),
    }
}
pub(super) fn validate_port(port: i32) -> Result<(), SessionError> {
    if (1..=u16::MAX as i32).contains(&port) {
        Ok(())
    } else {
        Err(SessionError::Transfer(format!(
            "服务器下发了非法端口: {port}"
        )))
    }
}
/// 每类事件只注册一个处理器：tsclient-rs 会为每个处理器、每个包 spawn 一个任务。
fn register_handlers(
    client: &Client,
    events: broadcast::Sender<SessionEvent>,
    signals: mpsc::UnboundedSender<SessionSignal>,
    voice: audio::engine::IncomingVoiceSender,
    epoch: u64,
    current: Arc<AtomicU64>,
) {
    let channel = signals.clone();
    let live = Arc::clone(&current);
    client.on_text_message(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::TextMessage(message) = event {
            let _ = channel.send(SessionSignal::TextMessage {
                epoch,
                message: TextMessageView {
                    from: message.invoker_name,
                    from_uid: message.invoker_uid,
                    from_id: message.invoker_id,
                    message: crate::text_format::bbcode_to_markdown(&message.message),
                    target_mode: message.target_mode,
                    target_id: message.target_id,
                    peer_uid: String::new(),
                    at: now_millis(),
                },
            });
        }
    }));

    let channel = events.clone();
    let live = Arc::clone(&current);
    client.on_own_permissions_changed(Arc::new(move |_| {
        if live.load(Ordering::Relaxed) == epoch {
            emit(&channel, SessionEvent::AccessChanged);
        }
    }));

    let channel = events.clone();
    let live = Arc::clone(&current);
    client.on_poked(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::Poked(poke) = event {
            emit(
                &channel,
                SessionEvent::Poked {
                    from: poke.invoker_name,
                    message: poke.message,
                },
            );
        }
    }));

    let channel = signals.clone();
    let live = Arc::clone(&current);
    client.on_client_enter(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::ClientEnter(info) = event {
            let _ = channel.send(SessionSignal::ClientJoined {
                epoch,
                client: ClientView::from(info),
            });
        }
    }));

    let channel = signals.clone();
    let live = Arc::clone(&current);
    client.on_plugin_command(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::PluginCommand(event) = event {
            let _ = channel.send(SessionSignal::PluginCommand { epoch, event });
        }
    }));

    let channel = events.clone();
    let left = signals.clone();
    let live = Arc::clone(&current);
    client.on_client_leave(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::ClientLeave(info) = event {
            emit(&channel, SessionEvent::ClientLeft { id: info.id });
            let _ = left.send(SessionSignal::ClientLeft { epoch, id: info.id });
        }
    }));

    let channel = events.clone();
    let updated = signals.clone();
    let live = Arc::clone(&current);
    client.on_client_updated(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::ClientUpdated(info) = event {
            emit(
                &channel,
                SessionEvent::ClientUpdated {
                    id: info.id,
                    input_muted: info.input_muted,
                    output_muted: info.output_muted,
                    away: info.away,
                    away_message: info.away_message,
                },
            );
            let _ = updated.send(SessionSignal::ClientUpdated {
                epoch,
                id: info.id,
                server_groups: info.server_groups,
            });
        }
    }));

    let channel = events.clone();
    let moved = signals.clone();
    let live = Arc::clone(&current);
    client.on_client_moved(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::ClientMoved(info) = event {
            emit(
                &channel,
                SessionEvent::ClientMoved {
                    id: info.id,
                    channel_id: info.target_channel_id,
                },
            );
            let _ = moved.send(SessionSignal::ClientMoved {
                epoch,
                id: info.id,
                channel_id: info.target_channel_id,
            });
        }
    }));

    let channel = signals.clone();
    let live = Arc::clone(&current);
    client.on_directory_snapshot(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::DirectorySnapshot(snapshot) = event {
            let _ = channel.send(SessionSignal::Snapshot { epoch, snapshot });
        }
    }));

    let channel = signals.clone();
    let live = Arc::clone(&current);
    client.on_server_info_updated(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::ServerInfoUpdated(info) = event {
            let _ = channel.send(SessionSignal::ServerInfoUpdated {
                epoch,
                icon_id: info.icon_id,
            });
        }
    }));

    let channel = signals.clone();
    let live = Arc::clone(&current);
    client.on_disconnected(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::Disconnected(err) = event {
            let message = err
                .map(|err| err.to_string())
                .unwrap_or_else(|| "连接已关闭".to_string());
            let _ = channel.send(SessionSignal::Disconnected { epoch, message });
        }
    }));

    let channel = signals.clone();
    let live = Arc::clone(&current);
    client.on_kicked(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::Kicked(reason) = event {
            let _ = channel.send(SessionSignal::Kicked {
                epoch,
                message: format!("被服务器移出: {reason}"),
            });
        }
    }));

    let channel = signals;
    let live = Arc::clone(&current);
    client.on_raw_notification(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        match event {
            ProtocolEvent::RawNotification { name, items } => {
                if streams::is_stream_notification(&name) {
                    let _ = channel.send(SessionSignal::StreamNotification { epoch, name, items });
                } else if name == "notifyconnectioninfo" {
                    let _ = channel.send(SessionSignal::ConnectionInfo { epoch, items });
                }
            }
            ProtocolEvent::NotificationOverflow { .. } => {
                let _ = channel.send(SessionSignal::StreamResync { epoch });
            }
            _ => {}
        }
    }));

    client.on_voice_data(Arc::new(move |event: ProtocolEvent| {
        if current.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::VoiceData(data) = event {
            voice.send(VoiceFrame {
                client_id: data.client_id,
                codec: data.codec,
                data: data.data.to_vec(),
            });
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::test_support::*;

    #[test]
    fn editing_an_active_address_requires_disconnect_before_persistence() {
        let mut actor = audio_actor();
        let original = actor
            .registry
            .register("Original", "a.example.com")
            .unwrap();
        actor.active_server_id = Some(original.id.clone());
        actor.state = SessionState::Connected {
            client_id: 1,
            channel_id: 1,
        };
        assert!(matches!(
            actor.update_server(original.id.clone(), "New".into(), "b.example.com".into()),
            Err(SessionError::Protocol(_))
        ));
        assert_eq!(actor.registry.profiles(), &[original]);
    }

    #[tokio::test]
    async fn failed_registry_writes_reject_the_operation_and_preserve_memory() {
        for operation in ["add", "remove", "edit"] {
            let root = std::env::temp_dir().join(format!(
                "flspeak-registry-operation-{:x}",
                rand::random::<u64>()
            ));
            let path = root.join("preferences.json");
            tokio::fs::create_dir_all(&path).await.unwrap();
            tokio::fs::write(path.join("keep"), b"preserve")
                .await
                .unwrap();
            let mut actor = audio_actor();
            let _ = SettingsManager::init(path.clone());
            actor.store_path = path;
            let original = actor
                .registry
                .register("Original", "a.example.com")
                .unwrap();
            let mut events = actor.events.subscribe();
            let rejected = match operation {
                "remove" => actor.remove(original.id.clone()).await.is_err(),
                "edit" => actor
                    .update_server(
                        original.id.clone(),
                        "Renamed".into(),
                        "b.example.com".into(),
                    )
                    .is_err(),
                _ => actor
                    .register("New".into(), "b.example.com".into())
                    .await
                    .is_err(),
            };
            let profiles = actor.registry.profiles().to_vec();
            let emitted = events.try_recv().is_ok();
            tokio::fs::remove_dir_all(&root).await.unwrap();
            assert!(rejected);
            assert_eq!(profiles, vec![original]);
            assert!(!emitted);
        }
    }

    #[test]
    fn reconnect_backoff_starts_fast_then_backs_off() {
        assert_eq!(reconnect_delay(1), Duration::from_secs(1));
        assert_eq!(reconnect_delay(2), Duration::from_secs(2));
        assert_eq!(reconnect_delay(3), Duration::from_secs(4));
        assert_eq!(reconnect_delay(4), Duration::from_secs(15));
        assert_eq!(reconnect_delay(5), Duration::from_secs(30));
        assert_eq!(reconnect_delay(6), Duration::from_secs(60));
        assert_eq!(reconnect_delay(7), Duration::from_secs(120));
        assert_eq!(reconnect_delay(20), Duration::from_secs(300));
    }
}
