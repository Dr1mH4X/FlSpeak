use super::*;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const DISCONNECT_TIMEOUT: Duration = Duration::from_secs(5);
/// 连续握手超时达到这个次数就尝试提升身份等级。
const IDENTITY_TIMEOUTS_BEFORE_UPGRADE: u32 = 3;
const IDENTITY_STEP: i32 = 5;
const IDENTITY_MAX_LEVEL: i32 = 29;
/// 首轮成功会话前最多重试次数；成功连上过之后不限次。
const STARTUP_RECONNECT_LIMIT: u32 = 5;

#[derive(Debug, Clone)]
pub(super) struct ConnectTarget {
    pub(super) id: String,
    pub(super) nickname: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ReconnectPlan {
    Skip,
    Exhausted,
    Schedule {
        attempt: u32,
        delay: Duration,
        generation: u64,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum IdentityUpgradeFinish {
    StaleGeneration,
    Succeeded,
    Failed,
}

/// 断线自动重连与握手超时触发的身份安全等级升级状态。
pub(super) struct ReconnectState {
    last_target: Option<ConnectTarget>,
    generation: u64,
    reconnect_attempt: u32,
    auto_reconnect: bool,
    ever_connected: bool,
    consecutive_timeouts: u32,
    identity_upgrade: Option<Arc<AbortSignal>>,
    identity_upgrading: bool,
}

impl Default for ReconnectState {
    fn default() -> Self {
        Self {
            last_target: None,
            generation: 0,
            reconnect_attempt: 0,
            auto_reconnect: true,
            ever_connected: false,
            consecutive_timeouts: 0,
            identity_upgrade: None,
            identity_upgrading: false,
        }
    }
}

impl ReconnectState {
    pub(super) fn begin_manual_connect(&mut self) {
        self.generation = self.generation.wrapping_add(1);
        if let Some(signal) = self.identity_upgrade.take() {
            signal.abort();
        }
        self.identity_upgrading = false;
        self.auto_reconnect = true;
        self.reconnect_attempt = 0;
        self.consecutive_timeouts = 0;
    }

    pub(super) fn retry_target_for_generation(&self, generation: u64) -> Option<ConnectTarget> {
        (self.generation == generation)
            .then(|| self.last_target.clone())
            .flatten()
    }

    pub(super) fn on_connected(&mut self, id: &str, nickname: &str) {
        self.last_target = Some(ConnectTarget {
            id: id.to_string(),
            nickname: nickname.to_string(),
        });
        self.reconnect_attempt = 0;
        self.consecutive_timeouts = 0;
        self.ever_connected = true;
    }

    pub(super) fn on_connect_failed(&mut self) {
        self.consecutive_timeouts = 0;
    }

    pub(super) fn on_connect_timeout(&mut self) -> bool {
        self.consecutive_timeouts = self.consecutive_timeouts.saturating_add(1);
        self.consecutive_timeouts >= IDENTITY_TIMEOUTS_BEFORE_UPGRADE
    }

    pub(super) fn reset_on_disconnect(&mut self) {
        self.auto_reconnect = false;
        self.last_target = None;
        if let Some(signal) = self.identity_upgrade.take() {
            signal.abort();
        }
        self.identity_upgrading = false;
        self.reconnect_attempt = 0;
        self.consecutive_timeouts = 0;
        self.generation = self.generation.wrapping_add(1);
    }

    pub(super) fn disable_auto_reconnect(&mut self) {
        self.auto_reconnect = false;
    }

    pub(super) fn set_auto_reconnect(&mut self, enabled: bool) {
        self.auto_reconnect = enabled;
        self.generation = self.generation.wrapping_add(1);
        if enabled {
            self.reconnect_attempt = 0;
        }
    }

    pub(super) fn can_schedule_reconnect(&self, allow_reconnect: bool) -> bool {
        allow_reconnect
            && self.auto_reconnect
            && self.last_target.is_some()
            && !self.identity_upgrading
    }

    pub(super) fn plan_reconnect(&mut self) -> ReconnectPlan {
        if !self.auto_reconnect || self.last_target.is_none() || self.identity_upgrading {
            return ReconnectPlan::Skip;
        }
        if !self.ever_connected && self.reconnect_attempt >= STARTUP_RECONNECT_LIMIT {
            self.auto_reconnect = false;
            return ReconnectPlan::Exhausted;
        }
        self.reconnect_attempt = self.reconnect_attempt.saturating_add(1);
        ReconnectPlan::Schedule {
            attempt: self.reconnect_attempt,
            delay: reconnect_delay(self.reconnect_attempt),
            generation: self.generation,
        }
    }

    pub(super) fn is_identity_upgrading(&self) -> bool {
        self.identity_upgrading
    }

    pub(super) fn begin_identity_upgrade(&mut self) -> (Arc<AbortSignal>, u64) {
        let signal = Arc::new(AbortSignal::new());
        self.identity_upgrade = Some(Arc::clone(&signal));
        self.identity_upgrading = true;
        (signal, self.generation)
    }

    pub(super) fn abort_identity_upgrade_start(&mut self) {
        self.identity_upgrading = false;
        self.identity_upgrade = None;
    }

    pub(super) fn cancel_identity_upgrade(&self) {
        if let Some(signal) = self.identity_upgrade.as_ref() {
            signal.abort();
        }
    }

    pub(super) fn finish_identity_upgrade(
        &mut self,
        generation: u64,
        succeeded: bool,
    ) -> IdentityUpgradeFinish {
        self.identity_upgrading = false;
        self.identity_upgrade = None;
        if generation != self.generation {
            return IdentityUpgradeFinish::StaleGeneration;
        }
        if succeeded {
            self.consecutive_timeouts = 0;
            self.reconnect_attempt = 0;
            IdentityUpgradeFinish::Succeeded
        } else {
            IdentityUpgradeFinish::Failed
        }
    }

    pub(super) fn last_nickname(&self) -> Option<&str> {
        self.last_target
            .as_ref()
            .map(|target| target.nickname.as_str())
    }
}

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
        if self.media.remove_server(&self.store_path, &id) {
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
                "disconnect before changing the server address".into(),
            ));
        }
        SettingsManager::update(|settings| {
            settings.network.servers = registry.profiles().to_vec();
        })
        .map_err(SessionError::Storage)?;
        self.registry = registry;
        self.emit(SessionEvent::Servers(self.registry.profiles().to_vec()));
        if profile.id != id
            && let Some(bytes) = self.media.move_server(&self.store_path, &id, &profile.id)
        {
            self.emit(SessionEvent::ServerIconUpdated {
                server_id: id,
                bytes: None,
            });
            self.emit(SessionEvent::ServerIconUpdated {
                server_id: profile.id.clone(),
                bytes: Some(bytes),
            });
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
            return Err(SessionError::Protocol("already connected".into()));
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
                        message: crate::notices::SESSION_CONNECT_DENIED.into(),
                    });
                    self.schedule_reconnect();
                }
                return Err(err.into());
            }
        };

        let identity = store::load_identity(&identity_path(&self.store_path))
            .await
            .map_err(SessionError::Protocol)?;

        let resolved = match proto::resolve_target(&profile, &self.dns_resolver).await {
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
                            message: crate::notices::SESSION_CONNECT_DENIED.into(),
                        });
                    } else {
                        self.emit(SessionEvent::Failed {
                            message: crate::notices::SESSION_CONNECT_FAILED.into(),
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
                    "SRV {}:{} -> {}:{} ({})",
                    profile.host,
                    profile.port,
                    resolved.target.host,
                    resolved.target.port,
                    resolved.addr
                ),
            });
        } else if !server::is_ip_literal(&resolved.target.host) {
            self.emit(SessionEvent::Log {
                level: "info".into(),
                message: format!(
                    "DNS {}:{} -> {}",
                    resolved.target.host, resolved.target.port, resolved.addr
                ),
            });
        }
        let mut client = match proto::client(
            identity,
            &profile,
            &resolved,
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
                            message: crate::notices::SESSION_CONNECT_DENIED.into(),
                        });
                    } else {
                        self.emit(SessionEvent::Failed {
                            message: crate::notices::SESSION_CONNECT_FAILED.into(),
                        });
                    }
                    self.schedule_reconnect();
                }
                return Err(err.into());
            }
        };

        self.directory.reset_on_disconnect();
        self.media.reset_on_disconnect();
        self.streams
            .reset_on_disconnect(StreamEndReason::Disconnected, &self.events);
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
        self.init_stream_session(&client);
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
                self.transfer_target = Some(ServerTarget {
                    host: resolved.addr.ip().to_string(),
                    port: resolved.addr.port(),
                });
                self.self_client_id = Some(client_id);
                self.open_protocol.set_self_client_id(Some(client_id));
                self.self_channel_id = channel_id;
                self.active_server_id = Some(profile.id.clone());
                self.reconnect.on_connected(id, nickname);
                self.self_uid = None;
                self.voice_report.reset();
                self.voice_report
                    .mark_dirty(DIRTY_ALL, ReportInstant::now());
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
                        self.directory.set_self_server_groups(&me.server_groups);
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
                self.open_protocol_connected(client_id, self.self_channel_id);
                self.start_voice();
                // 服务器端自己的标志在（重）连后是重置过的，将本地权威语音状态上报。
                self.request_state_update().await;
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
                self.reconnect.on_connect_failed();
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "connect failed: target={}:{} addr={} via_srv={} reconnecting={reconnecting} error={err}",
                        resolved.target.host, resolved.target.port, resolved.addr, resolved.via_srv
                    ),
                });
                if !reconnecting {
                    self.set_state(SessionState::Disconnected);
                } else {
                    self.emit(SessionEvent::Failed {
                        message: crate::notices::SESSION_CONNECT_FAILED.into(),
                    });
                    self.schedule_reconnect();
                }
                Err(err)
            }
            Err(_) => {
                self.invalidate_handlers();
                let _ = client.disconnect().await;
                let should_upgrade_identity = self.reconnect.on_connect_timeout();
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!(
                        "connect timed out ({}s): target={}:{} addr={} via_srv={} reconnecting={reconnecting}",
                        CONNECT_TIMEOUT.as_secs(),
                        resolved.target.host,
                        resolved.target.port,
                        resolved.addr,
                        resolved.via_srv
                    ),
                });
                if !reconnecting {
                    self.set_state(SessionState::Disconnected);
                } else {
                    self.emit(SessionEvent::Failed {
                        message: crate::notices::SESSION_CONNECT_TIMEOUT.into(),
                    });
                }
                if should_upgrade_identity {
                    self.start_identity_upgrade().await;
                } else if reconnecting {
                    self.schedule_reconnect();
                }
                Err(SessionError::Timeout)
            }
        }
    }

    pub(super) async fn disconnect(&mut self) -> Result<(), SessionError> {
        self.reconnect.reset_on_disconnect();
        self.invalidate_handlers();
        self.current_codec = VOICE_CODEC;
        let Some(client) = self.client.take() else {
            self.active_server_id = None;
            self.self_client_id = None;
            self.self_channel_id = 0;
            self.stop_voice();
            self.set_state(SessionState::Disconnected);
            return Ok(());
        };
        self.sync_voice_gate();
        let outcome = tokio::time::timeout(DISCONNECT_TIMEOUT, client.disconnect()).await;
        self.active_server_id = None;
        self.self_client_id = None;
        self.self_channel_id = 0;
        self.stop_voice();
        self.set_state(SessionState::Disconnected);
        match outcome {
            Ok(Ok(())) => Ok(()),
            Ok(Err(err)) => Err(SessionError::Protocol(err.to_string())),
            Err(_) => Err(SessionError::Timeout),
        }
    }
    pub(super) async fn on_connection_lost(
        &mut self,
        notice: &'static str,
        detail: String,
        allow_reconnect: bool,
    ) {
        if self.client.is_none() {
            return;
        }
        crate::log_warn!(message = detail; "connection ended");
        self.invalidate_handlers();
        self.client = None;
        self.sync_voice_gate();
        self.active_server_id = None;
        self.self_client_id = None;
        self.self_channel_id = 0;
        self.current_codec = VOICE_CODEC;
        self.stop_voice();
        let will_reconnect = self.reconnect.can_schedule_reconnect(allow_reconnect);
        if will_reconnect {
            self.schedule_reconnect();
        } else {
            self.set_state(SessionState::Disconnected);
        }
        self.emit(SessionEvent::Failed {
            message: notice.into(),
        });
    }

    pub(super) async fn start_identity_upgrade(&mut self) {
        if self.reconnect.is_identity_upgrading() {
            return;
        }
        let path = identity_path(&self.store_path);
        let identity = match store::load_identity(&path).await {
            Ok(identity) => identity,
            Err(err) => {
                crate::log_warn!(error = err.to_string(); "failed to read identity");
                self.emit(SessionEvent::Failed {
                    message: crate::notices::SESSION_IDENTITY_READ_FAILED.into(),
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
        let (signal, generation) = self.reconnect.begin_identity_upgrade();
        self.emit(SessionEvent::IdentityUpgrade { from, to });

        let commands = self.commands.clone();
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
            self.reconnect.abort_identity_upgrade_start();
            crate::log_warn!(error = err.to_string(); "failed to start identity upgrade thread");
            self.emit(SessionEvent::Failed {
                message: crate::notices::SESSION_IDENTITY_THREAD_FAILED.into(),
            });
            self.schedule_reconnect();
        }
    }

    pub(super) fn schedule_reconnect(&mut self) {
        match self.reconnect.plan_reconnect() {
            ReconnectPlan::Skip => {}
            ReconnectPlan::Exhausted => {
                self.set_state(SessionState::Disconnected);
                self.emit(SessionEvent::Failed {
                    message: crate::notices::SESSION_RECONNECT_EXHAUSTED.into(),
                });
            }
            ReconnectPlan::Schedule {
                attempt,
                delay,
                generation,
            } => {
                self.set_state(SessionState::Reconnecting {
                    attempt,
                    delay_ms: delay.as_millis() as u64,
                });

                let commands = self.commands.clone();
                tokio::spawn(async move {
                    tokio::time::sleep(delay).await;
                    let _ = commands.send(SessionCommand::RetryConnect { generation });
                });
            }
        }
    }
    pub(super) async fn teardown(&mut self) {
        self.reconnect.reset_on_disconnect();
        self.invalidate_handlers();
        if let Some(client) = self.client.take() {
            let _ = tokio::time::timeout(DISCONNECT_TIMEOUT, client.disconnect()).await;
        }
        self.stop_voice();
        self.current_codec = VOICE_CODEC;
        self.set_state(SessionState::Disconnected);
    }
    pub(super) fn invalidate_handlers(&mut self) {
        self.media.reset_on_disconnect();
        self.audio_since = Instant::now();
        self.voice.set_meter_epoch(None);
        self.levels.set_epoch(None);
        self.transfer_target = None;
        self.last_network_sample_error = None;
        self.open_protocol.reset(Instant::now());
        self.open_protocol_flood_halted = false;
        self.voice_report.reset();
        self.directory.reset_on_disconnect();
        self.self_uid = None;
        self.streams
            .reset_on_disconnect(StreamEndReason::Disconnected, &self.events);
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
            "server sent an invalid port: {port}"
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
                    from_self: false,
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
            let avatar_hash = info.avatar_hash.clone();
            let _ = channel.send(SessionSignal::ClientJoined {
                epoch,
                client: ClientView::from(info),
                avatar_hash,
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

    let updated = signals.clone();
    let live = Arc::clone(&current);
    client.on_client_updated(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::ClientUpdated(info) = event {
            let _ = updated.send(SessionSignal::ClientUpdated {
                epoch,
                id: info.id,
                uid: info.uid,
                channel_id: info.channel_id,
                input_muted: info.input_muted,
                output_muted: info.output_muted,
                away: info.away,
                away_message: info.away_message,
                server_groups: info.server_groups,
                avatar_hash: info.avatar_hash,
            });
        }
    }));

    let moved = signals.clone();
    let live = Arc::clone(&current);
    client.on_client_moved(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::ClientMoved(info) = event {
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
                .unwrap_or_else(|| "connection closed".to_string());
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
                message: format!("removed by the server: {reason}"),
            });
        }
    }));

    let channel = signals;
    let live = Arc::clone(&current);
    client.on_raw_notification(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::RawNotification { name, items } = event
            && name == "notifyconnectioninfo"
        {
            let _ = channel.send(SessionSignal::ConnectionInfo { epoch, items });
        }
    }));

    client.on_voice_data(Arc::new(move |event: ProtocolEvent| {
        if current.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::VoiceData(data) = event {
            let is_end_of_stream = data.data.is_empty();
            voice.send(VoiceFrame {
                client_id: data.client_id,
                codec: data.codec,
                seq: data.seq,
                received_at: data.received_at,
                is_end_of_stream,
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
        let _guard = crate::settings::manager::TEST_SETTINGS_LOCK.lock().await;
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

    #[test]
    fn reconnect_state_startup_limit_and_post_connect_unlimited() {
        let mut state = ReconnectState::default();
        assert!(state.auto_reconnect);
        assert!(!state.ever_connected);
        assert_eq!(state.plan_reconnect(), ReconnectPlan::Skip);

        state.last_target = Some(ConnectTarget {
            id: "srv1".into(),
            nickname: "Alice".into(),
        });
        for expected in 1..=STARTUP_RECONNECT_LIMIT {
            assert_eq!(
                state.plan_reconnect(),
                ReconnectPlan::Schedule {
                    attempt: expected,
                    delay: reconnect_delay(expected),
                    generation: 0,
                }
            );
        }
        assert_eq!(state.plan_reconnect(), ReconnectPlan::Exhausted);
        assert!(!state.auto_reconnect);
        assert_eq!(state.plan_reconnect(), ReconnectPlan::Skip);

        state.auto_reconnect = true;
        state.on_connected("srv1", "Alice");
        assert!(state.ever_connected);
        assert_eq!(state.reconnect_attempt, 0);
        assert_eq!(state.consecutive_timeouts, 0);
        assert_eq!(state.last_nickname(), Some("Alice"));

        for expected in 1..=10 {
            assert_eq!(
                state.plan_reconnect(),
                ReconnectPlan::Schedule {
                    attempt: expected,
                    delay: reconnect_delay(expected),
                    generation: 0,
                }
            );
        }
    }

    #[test]
    fn reconnect_state_timeout_threshold_and_identity_upgrade_lifecycle() {
        let mut state = ReconnectState::default();
        state.on_connected("srv1", "Alice");

        assert!(!state.on_connect_timeout());
        assert!(!state.on_connect_timeout());
        state.on_connect_failed();
        assert_eq!(state.consecutive_timeouts, 0);

        assert!(!state.on_connect_timeout());
        assert!(!state.on_connect_timeout());
        assert!(state.on_connect_timeout());

        let (signal, gen1) = state.begin_identity_upgrade();
        assert!(state.is_identity_upgrading());
        assert!(!state.can_schedule_reconnect(true));
        assert_eq!(state.plan_reconnect(), ReconnectPlan::Skip);

        state.cancel_identity_upgrade();
        assert!(signal.is_aborted());

        assert_eq!(
            state.finish_identity_upgrade(gen1 + 1, true),
            IdentityUpgradeFinish::StaleGeneration
        );
        assert!(!state.is_identity_upgrading());
        assert_eq!(state.consecutive_timeouts, IDENTITY_TIMEOUTS_BEFORE_UPGRADE);

        let (_signal2, gen2) = state.begin_identity_upgrade();
        assert_eq!(
            state.finish_identity_upgrade(gen2, false),
            IdentityUpgradeFinish::Failed
        );
        assert_eq!(state.consecutive_timeouts, IDENTITY_TIMEOUTS_BEFORE_UPGRADE);

        let (_signal3, gen3) = state.begin_identity_upgrade();
        state.reconnect_attempt = 3;
        assert_eq!(
            state.finish_identity_upgrade(gen3, true),
            IdentityUpgradeFinish::Succeeded
        );
        assert_eq!(state.consecutive_timeouts, 0);
        assert_eq!(state.reconnect_attempt, 0);
    }

    #[test]
    fn reconnect_state_reset_manual_connect_and_auto_reconnect() {
        let mut state = ReconnectState::default();
        state.on_connected("srv1", "Bob");
        state.on_connect_timeout();
        state.reconnect_attempt = 2;
        let (signal, old_gen) = state.begin_identity_upgrade();

        state.reset_on_disconnect();
        assert!(signal.is_aborted());
        assert!(!state.auto_reconnect);
        assert!(!state.is_identity_upgrading());
        assert_eq!(state.reconnect_attempt, 0);
        assert_eq!(state.consecutive_timeouts, 0);
        assert!(state.last_nickname().is_none());
        assert!(state.ever_connected);
        assert_ne!(state.generation, old_gen);
        assert!(!state.can_schedule_reconnect(true));

        let (manual_signal, _) = state.begin_identity_upgrade();
        state.reconnect_attempt = 4;
        state.on_connect_timeout();
        state.begin_manual_connect();
        assert!(manual_signal.is_aborted());
        assert!(state.auto_reconnect);
        assert!(!state.is_identity_upgrading());
        assert_eq!(state.reconnect_attempt, 0);
        assert_eq!(state.consecutive_timeouts, 0);

        state.on_connected("srv2", "Carol");
        state.reconnect_attempt = 3;
        let connected_gen = state.generation;
        assert!(state.retry_target_for_generation(connected_gen).is_some());

        state.set_auto_reconnect(false);
        assert!(!state.auto_reconnect);
        assert!(state.retry_target_for_generation(connected_gen).is_none());
        assert!(!state.can_schedule_reconnect(true));

        state.set_auto_reconnect(true);
        assert!(state.auto_reconnect);
        assert_eq!(state.reconnect_attempt, 0);
        assert!(state.can_schedule_reconnect(true));
        assert!(!state.can_schedule_reconnect(false));
    }
}
