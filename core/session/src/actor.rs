//! 命令循环：所有协议操作在这里串行执行。

use std::collections::HashMap;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::task::{Context, Poll};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use audio::engine::{AudioEvent, AudioStage, VoiceEngine};
use audio::format::{VOICE_CODEC, is_supported_codec};
use audio::playback::VoiceFrame;
use proto::ConnectError;
use server::{ServerError, ServerProfile, ServerRegistry};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::{broadcast, mpsc};
use tsclient_rs::{
    AbortSignal, ChannelInfo, Client, ClientInfo, Event as ProtocolEvent, FileDownloadInfo, Logger,
};

use crate::store::{self, identity_path};
use crate::{
    AudioDeviceView, AudioDevicesView, ChannelView, ClientView, SessionCommand, SessionError,
    SessionEvent, SessionState, TextMessageView, TransferDirection, VoiceStateView,
};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const DISCONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const TRANSFER_PROGRESS_BYTES: u64 = 256 * 1024;
const TRANSFER_PROGRESS_INTERVAL: Duration = Duration::from_millis(200);
/// 连续握手超时达到这个次数就尝试提升身份等级。
const IDENTITY_TIMEOUTS_BEFORE_UPGRADE: u32 = 3;
const IDENTITY_STEP: i32 = 5;
const IDENTITY_MAX_LEVEL: i32 = 29;
/// 首轮成功会话前最多重试次数；成功连上过之后不限次。
const STARTUP_RECONNECT_LIMIT: u32 = 5;
/// TS 单个数据报上限 500 字节；扣掉 tag/头/语音头后 Opus 载荷约 484 字节。
const MAX_VOICE_PAYLOAD: usize = 484;
const _: () = assert!(MAX_VOICE_PAYLOAD < 500);

/// ServerQuery 单行消息上限。超过这个长度的文本必须分片发送。
const MAX_TEXT_MESSAGE_BYTES: usize = 8192;

/// 音频线程到 actor 的事件队列，溢出时丢的是语音包而不是协议命令。
pub(crate) const AUDIO_EVENT_CAPACITY: usize = 64;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct ChannelMetadata {
    order: Option<u64>,
    description: Option<String>,
    codec: Option<i32>,
    max_clients: Option<u16>,
    max_clients_limited: Option<bool>,
    password_protected: Option<bool>,
}

#[derive(Debug)]
struct ChannelDirectory {
    channels: Vec<ChannelView>,
    codecs: Option<HashMap<u64, i32>>,
    metadata_error: Option<String>,
}

#[derive(Debug, Clone)]
struct ConnectTarget {
    id: String,
    nickname: String,
}

#[derive(Debug)]
pub(crate) enum SessionSignal {
    TextMessage {
        epoch: u64,
        message: TextMessageView,
    },
    ClientMoved {
        epoch: u64,
        id: i32,
        channel_id: u64,
    },
    Disconnected {
        epoch: u64,
        message: String,
    },
    Kicked {
        epoch: u64,
        message: String,
    },
}

pub(crate) struct Actor {
    registry: ServerRegistry,
    store_path: PathBuf,
    events: broadcast::Sender<SessionEvent>,
    commands: mpsc::UnboundedSender<SessionCommand>,
    signals: mpsc::UnboundedSender<SessionSignal>,
    signal_rx: mpsc::UnboundedReceiver<SessionSignal>,
    audio_events: mpsc::Receiver<AudioEvent>,
    voice: VoiceEngine,
    logger: Arc<dyn Logger>,
    state: SessionState,
    client: Option<Arc<Client>>,
    self_client_id: Option<i32>,
    self_channel_id: u64,
    active_server_id: Option<String>,
    last_target: Option<ConnectTarget>,
    generation: u64,
    reconnect_attempt: u32,
    auto_reconnect: bool,
    voice_state: VoiceStateView,
    input_device: Option<String>,
    output_device: Option<String>,
    capture_active: bool,
    audio_enabled: bool,
    last_snapshot: Option<(Vec<ChannelView>, Vec<ClientView>)>,
    channel_codecs: HashMap<u64, i32>,
    current_codec: i32,
    ever_connected: bool,
    consecutive_timeouts: u32,
    identity_upgrade: Option<Arc<AbortSignal>>,
    identity_upgrading: bool,
    next_transfer_id: u64,
    connection_epoch: u64,
    epoch: Arc<AtomicU64>,
}

impl Actor {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        store_path: PathBuf,
        registry: ServerRegistry,
        events: broadcast::Sender<SessionEvent>,
        commands: mpsc::UnboundedSender<SessionCommand>,
        signals: mpsc::UnboundedSender<SessionSignal>,
        signal_rx: mpsc::UnboundedReceiver<SessionSignal>,
        voice: VoiceEngine,
        audio_events: mpsc::Receiver<AudioEvent>,
        audio_enabled: bool,
    ) -> Self {
        let logger: Arc<dyn Logger> = Arc::new(EventLogger {
            events: events.clone(),
        });
        Self {
            registry,
            store_path,
            events,
            commands,
            signals,
            signal_rx,
            audio_events,
            voice,
            logger,
            state: SessionState::Disconnected,
            client: None,
            self_client_id: None,
            self_channel_id: 0,
            active_server_id: None,
            last_target: None,
            generation: 0,
            reconnect_attempt: 0,
            auto_reconnect: true,
            voice_state: VoiceStateView::default(),
            input_device: None,
            output_device: None,
            capture_active: false,
            audio_enabled,
            last_snapshot: None,
            channel_codecs: HashMap::new(),
            current_codec: VOICE_CODEC,
            ever_connected: false,
            consecutive_timeouts: 0,
            identity_upgrade: None,
            identity_upgrading: false,
            next_transfer_id: 1,
            connection_epoch: 0,
            epoch: Arc::new(AtomicU64::new(0)),
        }
    }

    pub(crate) async fn run(&mut self, mut commands: mpsc::UnboundedReceiver<SessionCommand>) {
        let mut snapshots = tokio::time::interval(crate::SNAPSHOT_INTERVAL);
        snapshots.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        // interval 的第一次 tick 立即就绪；消费掉，避免刚启动就发空快照。
        snapshots.tick().await;

        loop {
            tokio::select! {
                biased;
                command = commands.recv() => {
                    match command {
                        Some(command) => {
                            if !self.handle(command).await {
                                break;
                            }
                        }
                        None => break,
                    }
                }
                signal = self.signal_rx.recv() => {
                    if let Some(signal) = signal {
                        self.handle_signal(signal).await;
                    }
                }
                audio = self.audio_events.recv() => {
                    if let Some(event) = audio {
                        self.handle_audio(event);
                    }
                }
                _ = snapshots.tick() => {
                    self.poll_snapshot().await;
                }
            }
        }
        self.teardown().await;
    }

    async fn handle(&mut self, command: SessionCommand) -> bool {
        match command {
            SessionCommand::Shutdown => return false,
            SessionCommand::RegisterServer {
                label,
                address,
                reply,
            } => {
                let _ = reply.send(self.register(label, address).await);
            }
            SessionCommand::RemoveServer { id, reply } => {
                let _ = reply.send(self.remove(id).await);
            }
            SessionCommand::ListServers { reply } => {
                let _ = reply.send(self.registry.profiles().to_vec());
            }
            SessionCommand::State { reply } => {
                let _ = reply.send(self.state.clone());
            }
            SessionCommand::Connect {
                id,
                nickname,
                reply,
            } => {
                self.generation = self.generation.wrapping_add(1);
                if let Some(signal) = self.identity_upgrade.take() {
                    signal.abort();
                }
                self.identity_upgrading = false;
                self.auto_reconnect = true;
                self.reconnect_attempt = 0;
                self.consecutive_timeouts = 0;
                let _ = reply.send(self.connect(&id, &nickname, false).await);
            }
            SessionCommand::RetryConnect { generation } => {
                if generation == self.generation
                    && self.client.is_none()
                    && let Some(target) = self.last_target.clone()
                {
                    let _ = self.connect(&target.id, &target.nickname, true).await;
                }
            }
            SessionCommand::Disconnect { reply } => {
                let _ = reply.send(self.disconnect().await);
            }
            SessionCommand::SendText {
                target_mode,
                target_id,
                message,
                reply,
            } => {
                let _ = reply.send(self.send_text(target_mode, target_id, message).await);
            }
            SessionCommand::Move {
                client_id,
                channel_id,
                password,
                reply,
            } => {
                let result = self.move_to_channel(client_id, channel_id, password).await;
                if result.is_ok() {
                    let _ = self.refresh_snapshot(true).await;
                }
                let _ = reply.send(result);
            }
            SessionCommand::ListChannels { reply } => {
                let _ = reply.send(self.list_channels().await);
            }
            SessionCommand::ListClients { reply } => {
                let _ = reply.send(self.list_clients().await);
            }
            SessionCommand::RequestSnapshot { reply } => {
                let _ = reply.send(self.refresh_snapshot(true).await);
            }
            SessionCommand::SetMuted { muted, reply } => {
                let _ = reply.send(self.set_muted(muted));
            }
            SessionCommand::SetDeafened { deafened, reply } => {
                let _ = reply.send(self.set_deafened(deafened));
            }
            SessionCommand::SetPttMode { enabled, reply } => {
                let _ = reply.send(self.set_ptt_mode(enabled));
            }
            SessionCommand::SetPttActive { active, reply } => {
                let _ = reply.send(self.set_ptt_active(active));
            }
            SessionCommand::CancelIdentityUpgrade { reply } => {
                if let Some(signal) = self.identity_upgrade.as_ref() {
                    signal.abort();
                }
                let _ = reply.send(Ok(()));
            }
            SessionCommand::IdentityUpgradeFinished {
                generation,
                level,
                error,
            } => {
                if generation != self.generation {
                    self.identity_upgrading = false;
                    self.identity_upgrade = None;
                    return true;
                }
                self.identity_upgrading = false;
                self.identity_upgrade = None;
                if let Some(level) = level {
                    self.consecutive_timeouts = 0;
                    self.reconnect_attempt = 0;
                    self.emit(SessionEvent::IdentityUpgraded { level });
                    self.schedule_reconnect();
                } else {
                    self.emit(SessionEvent::Failed {
                        message: error.unwrap_or_else(|| "身份等级提升失败".into()),
                    });
                    self.schedule_reconnect();
                }
            }
            SessionCommand::SetAutoReconnect { enabled, reply } => {
                self.auto_reconnect = enabled;
                self.generation = self.generation.wrapping_add(1);
                if enabled {
                    self.reconnect_attempt = 0;
                }
                let _ = reply.send(Ok(()));
            }
            SessionCommand::ListAudioDevices { reply } => {
                let _ = reply.send(list_audio_devices());
            }
            SessionCommand::SetAudioDevices {
                input,
                output,
                reply,
            } => {
                let _ = reply.send(self.set_audio_devices(input, output));
            }
            SessionCommand::UploadFile {
                local_path,
                remote_path,
                channel_id,
                password,
                overwrite,
                reply,
            } => {
                let _ = reply.send(
                    self.upload_file(local_path, remote_path, channel_id, password, overwrite)
                        .await,
                );
            }
            SessionCommand::DownloadFile {
                remote_path,
                local_path,
                channel_id,
                password,
                reply,
            } => {
                let _ = reply.send(
                    self.download_file(remote_path, local_path, channel_id, password)
                        .await,
                );
            }
        }
        true
    }

    async fn register(
        &mut self,
        label: String,
        address: String,
    ) -> Result<ServerProfile, ServerError> {
        let profile = self.registry.register(&label, &address)?;
        self.persist().await;
        self.emit(SessionEvent::Servers(self.registry.profiles().to_vec()));
        Ok(profile)
    }

    async fn remove(&mut self, id: String) -> Result<(), ServerError> {
        if !self.registry.remove(&id) {
            return Err(ServerError::NotRegistered(id));
        }
        self.persist().await;
        self.emit(SessionEvent::Servers(self.registry.profiles().to_vec()));
        Ok(())
    }

    async fn connect(
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
                self.emit(SessionEvent::Denied {
                    message: err.to_string(),
                });
                if reconnecting {
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
                if matches!(err, ConnectError::Address(_) | ConnectError::Blocked { .. }) {
                    self.emit(SessionEvent::Denied {
                        message: err.to_string(),
                    });
                }
                if reconnecting {
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
        let mut client = match proto::client(
            identity,
            &profile,
            &resolved.target,
            nickname,
            Arc::clone(&self.logger),
        ) {
            Ok(client) => client,
            Err(err) => {
                if matches!(err, ConnectError::Address(_) | ConnectError::Blocked { .. }) {
                    self.emit(SessionEvent::Denied {
                        message: err.to_string(),
                    });
                }
                if reconnecting {
                    self.schedule_reconnect();
                }
                return Err(err.into());
            }
        };

        self.connection_epoch = self.connection_epoch.wrapping_add(1);
        self.epoch.store(self.connection_epoch, Ordering::SeqCst);
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
                self.set_state(SessionState::Connected {
                    client_id,
                    channel_id,
                });
                self.subscribe_all_channels().await;
                if let Some(client) = self.client.clone() {
                    self.wait_for_welcome_directory(&client).await;
                }
                if let Err(err) = self.refresh_snapshot(true).await {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: err.to_string(),
                    });
                }
                self.start_voice();
                self.emit_voice_state();
                self.emit_history().await;
                Ok(())
            }
            Ok(Err(err)) => {
                self.invalidate_handlers();
                let _ = client.disconnect().await;
                self.consecutive_timeouts = 0;
                if !reconnecting {
                    self.set_state(SessionState::Disconnected);
                }
                self.emit(SessionEvent::Failed {
                    message: err.to_string(),
                });
                if reconnecting {
                    self.schedule_reconnect();
                }
                Err(err)
            }
            Err(_) => {
                self.invalidate_handlers();
                let _ = client.disconnect().await;
                self.consecutive_timeouts = self.consecutive_timeouts.saturating_add(1);
                if !reconnecting {
                    self.set_state(SessionState::Disconnected);
                }
                self.emit(SessionEvent::Failed {
                    message: SessionError::Timeout.to_string(),
                });
                if self.consecutive_timeouts >= IDENTITY_TIMEOUTS_BEFORE_UPGRADE {
                    self.start_identity_upgrade().await;
                } else if reconnecting {
                    self.schedule_reconnect();
                }
                Err(SessionError::Timeout)
            }
        }
    }

    async fn disconnect(&mut self) -> Result<(), SessionError> {
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

    async fn send_text(
        &self,
        target_mode: i32,
        target_id: u64,
        message: String,
    ) -> Result<(), SessionError> {
        let client = self.connected()?;
        // ServerQuery 的单行上限是 8192 字节。长文本按 UTF-8 边界分片，
        // 每一片单独走 sendtextmessage，避免整条消息被服务端截断。
        for chunk in split_text_message(&message, MAX_TEXT_MESSAGE_BYTES) {
            tsclient_rs::sendTextMessage(&client, target_mode, target_id, &chunk)
                .await
                .map_err(protocol_error)?;
        }
        Ok(())
    }

    async fn move_to_channel(
        &self,
        client_id: i32,
        channel_id: u64,
        password: Option<String>,
    ) -> Result<(), SessionError> {
        let client = self.connected()?;
        let password = password.unwrap_or_default();
        tsclient_rs::clientMove(&client, client_id, channel_id, &password)
            .await
            .map_err(protocol_error)
    }

    async fn list_channels(&self) -> Result<Vec<ChannelView>, SessionError> {
        let client = self.connected()?;
        let directory = self.read_channel_directory(&client).await?;
        if let Some(err) = directory.metadata_error {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("读取频道标志失败: {err}"),
            });
        }
        Ok(directory.channels)
    }

    async fn list_clients(&self) -> Result<Vec<ClientView>, SessionError> {
        let client = self.connected()?;
        let clients = match tsclient_rs::listClients(&client).await {
            Ok(clients) => clients,
            Err(err) => {
                // None 表示目录还没同步完，和空快照一样拿不到成员，回退到原错误。
                let Some(snapshot) = client
                    .directory_snapshot()
                    .filter(|snapshot| !snapshot.clients.is_empty())
                else {
                    return Err(protocol_error(err));
                };
                snapshot.clients
            }
        };
        Ok(clients.into_iter().map(ClientView::from).collect())
    }

    async fn refresh_snapshot(&mut self, force: bool) -> Result<(), SessionError> {
        let Some(client) = self.client.clone() else {
            return Ok(());
        };
        let previous = self.last_snapshot.clone();
        let mut failures = Vec::new();

        let channels = match self.read_channel_directory(&client).await {
            Ok(directory) => {
                if let Some(err) = directory.metadata_error {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("读取频道标志失败: {err}"),
                    });
                }
                if let Some(codecs) = directory.codecs {
                    self.channel_codecs = codecs;
                }
                directory.channels
            }
            Err(err) => {
                failures.push(format!("频道目录: {err}"));
                previous
                    .as_ref()
                    .map(|(channels, _)| channels.clone())
                    .unwrap_or_default()
            }
        };

        let clients = match tsclient_rs::listClients(&client).await {
            Ok(clients) => clients.into_iter().map(ClientView::from).collect(),
            Err(err) => {
                let snapshot = client
                    .directory_snapshot()
                    .filter(|snapshot| !snapshot.clients.is_empty());
                if let Some(snapshot) = snapshot {
                    snapshot.clients.into_iter().map(ClientView::from).collect()
                } else {
                    failures.push(format!("成员列表: {err}"));
                    previous
                        .as_ref()
                        .map(|(_, clients)| clients.clone())
                        .unwrap_or_default()
                }
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
            if me.channel_id != self.self_channel_id {
                self.apply_self_channel(me.channel_id, self_codec);
            } else {
                self.apply_channel_codec(self_codec);
            }
        }

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
        Ok(())
    }

    async fn subscribe_all_channels(&self) {
        let Ok(client) = self.connected() else {
            return;
        };
        if let Err(err) = client.exec_command("channelsubscribeall", 5_000).await {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("订阅全部频道失败，将只接收当前订阅范围内的成员事件: {err}"),
            });
        }
    }

    async fn wait_for_welcome_directory(&self, client: &Client) {
        // 上游 0.2.0 提供事件驱动的目录就绪等待（channellistfinished）；保留旧轮询
        // 实现的 500ms 上限，服务器迟迟不发目录时跳过等待，不阻塞连接后的初始化。
        let _ = tokio::time::timeout(
            Duration::from_millis(500),
            client.wait_directory_ready(None),
        )
        .await;
    }

    async fn read_channel_directory(
        &self,
        client: &Client,
    ) -> Result<ChannelDirectory, SessionError> {
        let (channels, explicit_list_worked) = match tsclient_rs::listChannels(client).await {
            Ok(channels) => (channels, true),
            Err(err) => {
                let Some(snapshot) = client
                    .directory_snapshot()
                    .filter(|snapshot| !snapshot.channels.is_empty())
                else {
                    return Err(protocol_error(err));
                };
                (snapshot.channels, false)
            }
        };
        if !explicit_list_worked {
            let codecs: HashMap<u64, i32> = channels
                .iter()
                .filter_map(|channel| channel.codec.map(|codec| (channel.id, codec)))
                .collect();
            return Ok(ChannelDirectory {
                channels: channels
                    .into_iter()
                    .map(|channel| channel_view(channel, None))
                    .collect(),
                codecs: (!codecs.is_empty()).then_some(codecs),
                metadata_error: None,
            });
        }
        match fetch_channel_metadata(client).await {
            Ok(metadata) => {
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
                let codecs: HashMap<u64, i32> = channels
                    .iter()
                    .filter_map(|channel| channel.codec.map(|codec| (channel.id, codec)))
                    .collect();
                Ok(ChannelDirectory {
                    channels: channels
                        .into_iter()
                        .map(|channel| channel_view(channel, None))
                        .collect(),
                    codecs: (!codecs.is_empty()).then_some(codecs),
                    metadata_error: Some(err.to_string()),
                })
            }
        }
    }

    async fn poll_snapshot(&mut self) {
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

    async fn emit_history(&self) {
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

    fn set_muted(&mut self, muted: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_muted(muted)?;
        }
        self.voice_state.muted = muted;
        if muted {
            self.voice_state.ptt_active = false;
            if self.audio_enabled {
                let _ = self.voice.set_ptt_active(false);
            }
        }
        self.emit_voice_state();
        Ok(())
    }

    fn set_deafened(&mut self, deafened: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_deafened(deafened)?;
        }
        self.voice_state.deafened = deafened;
        if deafened {
            self.voice_state.ptt_active = false;
            if self.audio_enabled {
                let _ = self.voice.set_ptt_active(false);
            }
        }
        self.emit_voice_state();
        Ok(())
    }

    fn set_ptt_mode(&mut self, enabled: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_ptt_mode(enabled)?;
        }
        self.voice_state.ptt_mode = enabled;
        if !enabled {
            self.voice_state.ptt_active = false;
        }
        self.emit_voice_state();
        Ok(())
    }

    fn set_ptt_active(&mut self, active: bool) -> Result<(), SessionError> {
        if !self.voice_state.ptt_mode {
            return Ok(());
        }
        let active = active && !self.voice_state.muted && !self.voice_state.deafened;
        if self.audio_enabled {
            self.voice.set_ptt_active(active)?;
        }
        self.voice_state.ptt_active = active;
        self.emit_voice_state();
        Ok(())
    }

    fn set_audio_devices(
        &mut self,
        input: Option<String>,
        output: Option<String>,
    ) -> Result<(), SessionError> {
        if !self.audio_enabled {
            return Ok(());
        }
        if self.input_device == input && self.output_device == output {
            return Ok(());
        }
        self.input_device = input;
        self.output_device = output;
        if self.client.is_some() {
            self.voice.set_input_device(self.input_device.clone())?;
            self.voice.set_output_device(self.output_device.clone())?;
        }
        Ok(())
    }

    fn apply_self_channel(&mut self, channel_id: u64, codec: Option<i32>) {
        if self.self_channel_id == channel_id {
            self.apply_channel_codec(codec);
            return;
        }
        self.self_channel_id = channel_id;
        if let SessionState::Connected { client_id, .. } = self.state.clone() {
            self.set_state(SessionState::Connected {
                client_id,
                channel_id,
            });
        }
        if channel_id == 0 {
            if self.capture_active {
                let _ = self.voice.stop_capture();
                self.capture_active = false;
            }
            return;
        }
        self.apply_channel_codec(codec);
    }

    fn apply_channel_codec(&mut self, codec: Option<i32>) {
        if !self.audio_enabled {
            return;
        }
        let Some(codec) = codec else {
            self.stop_capture_with_message("无法读取当前频道的 codec");
            return;
        };
        if !is_supported_codec(codec) {
            self.stop_capture_with_message(&format!("频道 codec {codec} 不受支持（仅 Opus 4/5）"));
            return;
        }
        self.current_codec = codec;
        if let Err(err) = self.voice.set_channel_codec(codec) {
            self.voice_state.message = Some(err.to_string());
            self.emit_voice_state();
            return;
        }
        self.voice_state.message = None;
        if self.client.is_some() && self.self_channel_id != 0 && !self.capture_active {
            let _ = self.voice.set_muted(self.voice_state.muted);
            let _ = self.voice.set_deafened(self.voice_state.deafened);
            let _ = self.voice.set_ptt_mode(self.voice_state.ptt_mode);
            let _ = self.voice.set_ptt_active(self.voice_state.ptt_active);
            if let Err(err) = self.voice.start_capture(self.input_device.clone()) {
                self.voice_state.message = Some(err.to_string());
            } else {
                self.capture_active = true;
            }
        }
        self.emit_voice_state();
    }

    fn stop_capture_with_message(&mut self, message: &str) {
        if self.capture_active {
            let _ = self.voice.stop_capture();
            self.capture_active = false;
        }
        self.voice_state.message = Some(message.to_string());
        self.emit_voice_state();
    }

    async fn upload_file(
        &mut self,
        local_path: String,
        remote_path: String,
        channel_id: u64,
        password: Option<String>,
        overwrite: bool,
    ) -> Result<u64, SessionError> {
        if channel_id == 0 {
            return Err(SessionError::NotInChannel);
        }
        let client = self.connected()?;
        let profile = self.active_profile()?;
        let target = profile.target()?;
        proto::check_transfer_host(&target, &profile.host)?;

        let file = tokio::fs::File::open(&local_path)
            .await
            .map_err(|err| SessionError::Transfer(format!("打开本地文件失败: {err}")))?;
        let size = file
            .metadata()
            .await
            .map_err(|err| SessionError::Transfer(format!("读取文件大小失败: {err}")))?
            .len();
        let info = client
            .file_transfer_init_upload(
                channel_id,
                &remote_path,
                password.as_deref().unwrap_or(""),
                size,
                overwrite,
            )
            .await
            .map_err(protocol_error)?;
        validate_port(info.port)?;

        let id = self.next_transfer_id;
        self.next_transfer_id = self.next_transfer_id.wrapping_add(1);
        self.emit(SessionEvent::TransferStarted {
            id,
            direction: TransferDirection::Upload,
            remote_path: remote_path.clone(),
            total: size,
        });

        let events = self.events.clone();
        let host = target.host.clone();
        tokio::task::spawn_local(async move {
            let reader = ProgressReader::new(file, id, size, events.clone());
            let outcome = client.upload_file_data(&host, &info, reader).await;
            let _ = events.send(SessionEvent::TransferFinished {
                id,
                error: outcome.err().map(|err| err.to_string()),
            });
        });
        Ok(id)
    }

    async fn download_file(
        &mut self,
        remote_path: String,
        local_path: String,
        channel_id: u64,
        password: Option<String>,
    ) -> Result<u64, SessionError> {
        if channel_id == 0 {
            return Err(SessionError::NotInChannel);
        }
        let client = self.connected()?;
        let profile = self.active_profile()?;
        let target = profile.target()?;
        proto::check_transfer_host(&target, &profile.host)?;

        let info: FileDownloadInfo = client
            .file_transfer_init_download(
                channel_id,
                &remote_path,
                password.as_deref().unwrap_or(""),
            )
            .await
            .map_err(protocol_error)?;
        validate_port(info.port)?;

        let file = tokio::fs::File::create(&local_path)
            .await
            .map_err(|err| SessionError::Transfer(format!("创建本地文件失败: {err}")))?;
        let truncate = file
            .try_clone()
            .await
            .map_err(|err| SessionError::Transfer(format!("复制文件句柄失败: {err}")))?;
        let id = self.next_transfer_id;
        self.next_transfer_id = self.next_transfer_id.wrapping_add(1);
        self.emit(SessionEvent::TransferStarted {
            id,
            direction: TransferDirection::Download,
            remote_path: remote_path.clone(),
            total: info.size,
        });

        let events = self.events.clone();
        let host = target.host.clone();
        tokio::task::spawn_local(async move {
            let writer = ProgressWriter::new(file, id, info.size, events.clone());
            let outcome = client.download_file_data(&host, &info, writer).await;
            let error = match &outcome {
                Ok(()) => {
                    // 下载流同样按 16 字节块解密，多出的补零要按服务器声明的 size 截掉。
                    truncate
                        .set_len(info.size)
                        .await
                        .err()
                        .map(|err| err.to_string())
                }
                Err(_) => None,
            };
            let _ = events.send(SessionEvent::TransferFinished {
                id,
                error: error.or_else(|| outcome.err().map(|err| err.to_string())),
            });
        });
        Ok(id)
    }

    async fn handle_signal(&mut self, signal: SessionSignal) {
        match signal {
            SessionSignal::TextMessage { epoch, message } => {
                if epoch != self.connection_epoch {
                    return;
                }
                if let Some(server_id) = self.active_server_id.clone() {
                    let path = store::history_path(&self.store_path);
                    if let Err(message) = store::append_history(&path, &server_id, &message).await {
                        self.emit(SessionEvent::Failed {
                            message: format!("消息历史写入失败: {message}"),
                        });
                    }
                }
                self.emit(SessionEvent::TextMessage(message));
            }
            SessionSignal::ClientMoved {
                epoch,
                id,
                channel_id,
            } => {
                if epoch == self.connection_epoch && self.self_client_id == Some(id) {
                    self.on_self_moved(channel_id).await;
                }
            }
            SessionSignal::Disconnected { epoch, message } => {
                if epoch == self.connection_epoch {
                    self.on_connection_lost(message, true).await;
                }
            }
            SessionSignal::Kicked { epoch, message } => {
                if epoch == self.connection_epoch {
                    self.auto_reconnect = false;
                    self.on_connection_lost(message, false).await;
                }
            }
        }
    }

    async fn on_connection_lost(&mut self, message: String, allow_reconnect: bool) {
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

    async fn start_identity_upgrade(&mut self) {
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

    fn schedule_reconnect(&mut self) {
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

    async fn on_self_moved(&mut self, channel_id: u64) {
        if self.self_channel_id == channel_id {
            return;
        }
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
    }

    fn handle_audio(&mut self, event: AudioEvent) {
        match event {
            AudioEvent::Outbound { codec, data } => {
                if codec != self.current_codec {
                    return;
                }
                if data.len() > MAX_VOICE_PAYLOAD {
                    self.voice_state.message =
                        Some(format!("语音包 {} 字节超过发送上限", data.len()));
                    self.emit_voice_state();
                    return;
                }
                if let Some(client) = &self.client {
                    client.send_voice(data, codec);
                }
            }
            AudioEvent::Talkers { client_ids } => {
                self.emit(SessionEvent::Speaking { client_ids });
            }
            AudioEvent::SelfSpeaking { speaking } => {
                self.emit(SessionEvent::SelfSpeaking { speaking });
            }
            AudioEvent::CaptureState {
                ready,
                ptt_mode,
                ptt_active,
            } => {
                self.voice_state.input_ready = ready;
                self.voice_state.ptt_mode = ptt_mode;
                self.voice_state.ptt_active = ptt_active;
                if ready {
                    self.voice_state.message = None;
                }
                self.capture_active = ready;
                self.emit_voice_state();
            }
            AudioEvent::PlaybackState { ready } => {
                self.voice_state.output_ready = ready;
                if ready {
                    self.voice_state.message = None;
                }
                self.emit_voice_state();
            }
            AudioEvent::Error { stage, message } => {
                let stage = match stage {
                    AudioStage::Capture => "采集",
                    AudioStage::Playback => "播放",
                    AudioStage::Codec => "编解码",
                };
                self.voice_state.message = Some(format!("{stage}失败: {message}"));
                self.emit_voice_state();
            }
        }
    }

    fn start_voice(&mut self) {
        if !self.audio_enabled {
            return;
        }
        let _ = self.voice.set_muted(self.voice_state.muted);
        let _ = self.voice.set_deafened(self.voice_state.deafened);
        let _ = self.voice.set_ptt_mode(self.voice_state.ptt_mode);
        let _ = self.voice.set_ptt_active(self.voice_state.ptt_active);
        if let Err(err) = self.voice.start_playback(self.output_device.clone()) {
            self.voice_state.message = Some(err.to_string());
        }
        if self.self_channel_id != 0 && is_supported_codec(self.current_codec) {
            if let Err(err) = self.voice.start_capture(self.input_device.clone()) {
                self.voice_state.message = Some(err.to_string());
                self.capture_active = false;
            } else {
                self.capture_active = true;
            }
        } else {
            self.capture_active = false;
        }
    }

    fn stop_voice(&mut self) {
        if self.audio_enabled {
            let _ = self.voice.stop();
        }
        self.capture_active = false;
    }

    async fn teardown(&mut self) {
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
        self.set_state(SessionState::Disconnected);
    }

    async fn persist(&self) {
        if let Err(message) = store::save_registry(&self.store_path, &self.registry).await {
            self.emit(SessionEvent::Failed {
                message: format!("档案保存失败: {message}"),
            });
        }
    }

    fn connected(&self) -> Result<Arc<Client>, SessionError> {
        self.client.clone().ok_or(SessionError::NotConnected)
    }

    fn active_profile(&self) -> Result<ServerProfile, SessionError> {
        let id = self
            .active_server_id
            .as_ref()
            .ok_or(SessionError::NotConnected)?;
        self.registry.require(id).cloned().map_err(Into::into)
    }

    fn invalidate_handlers(&mut self) {
        self.connection_epoch = self.connection_epoch.wrapping_add(1);
        self.epoch.store(self.connection_epoch, Ordering::SeqCst);
    }

    fn set_state(&mut self, state: SessionState) {
        self.state = state.clone();
        self.emit(SessionEvent::State(state));
    }

    fn emit_voice_state(&self) {
        self.emit(SessionEvent::Voice(self.voice_state.clone()));
    }

    fn emit(&self, event: SessionEvent) {
        emit(&self.events, event);
    }
}

fn reconnect_delay(attempt: u32) -> Duration {
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

async fn fetch_channel_metadata(
    client: &Client,
) -> Result<HashMap<u64, ChannelMetadata>, SessionError> {
    let rows = client
        .exec_command_with_response("channellist -flags -codec", 5_000)
        .await
        .map_err(protocol_error)?;
    Ok(parse_channel_metadata(&rows))
}

fn parse_channel_metadata(rows: &[HashMap<String, String>]) -> HashMap<u64, ChannelMetadata> {
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
                    .get("channel_topic")
                    .or_else(|| row.get("channel_description"))
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

fn channel_view(channel: ChannelInfo, metadata: Option<&ChannelMetadata>) -> ChannelView {
    let metadata = metadata.cloned().unwrap_or_default();
    ChannelView {
        id: channel.id,
        parent_id: channel.parent_id,
        order: metadata.order.or(Some(channel.order)),
        name: channel.name,
        description: metadata.description.unwrap_or(channel.description),
        max_clients: metadata.max_clients.or(channel.max_clients),
        max_clients_limited: metadata.max_clients_limited.or(channel.max_clients_limited),
        password_protected: metadata.password_protected.or(channel.password_protected),
    }
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

fn list_audio_devices() -> Result<AudioDevicesView, SessionError> {
    let inputs = audio::device::input_devices()
        .map_err(SessionError::Audio)?
        .into_iter()
        .map(AudioDeviceView::from)
        .collect();
    let outputs = audio::device::output_devices()
        .map_err(SessionError::Audio)?
        .into_iter()
        .map(AudioDeviceView::from)
        .collect();
    Ok(AudioDevicesView { inputs, outputs })
}

fn validate_port(port: i32) -> Result<(), SessionError> {
    if (1..=u16::MAX as i32).contains(&port) {
        Ok(())
    } else {
        Err(SessionError::Transfer(format!(
            "服务器下发了非法端口: {port}"
        )))
    }
}

impl From<audio::device::DeviceInfo> for AudioDeviceView {
    fn from(info: audio::device::DeviceInfo) -> Self {
        Self {
            id: info.id,
            name: info.name,
            is_default: info.is_default,
        }
    }
}

fn protocol_error(err: tsclient_rs::Error) -> SessionError {
    SessionError::Protocol(err.to_string())
}

/// 按 UTF-8 字节上限切分文本消息。
///
/// 优先在空白处断开；找不到合适空白时退到字符边界。单个字符本身超过上限时
/// 独占一片，不切断 UTF-8。片与片之间的空白会被丢弃，语义与 TeamSpeakClaw 一致。
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

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

fn emit(events: &broadcast::Sender<SessionEvent>, event: SessionEvent) {
    // 没有订阅者时事件直接丢弃，actor 不因此停下。
    let _ = events.send(event);
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
                    message: message.message,
                    target_mode: message.target_mode,
                    target_id: message.target_id,
                    at: now_millis(),
                },
            });
        }
    }));

    let channel = events.clone();
    let live = Arc::clone(&current);
    client.on_client_enter(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::ClientEnter(info) = event {
            emit(&channel, SessionEvent::ClientJoined(ClientView::from(info)));
        }
    }));

    let channel = events.clone();
    let live = Arc::clone(&current);
    client.on_client_leave(Arc::new(move |event: ProtocolEvent| {
        if live.load(Ordering::Relaxed) != epoch {
            return;
        }
        if let ProtocolEvent::ClientLeave(info) = event {
            emit(&channel, SessionEvent::ClientLeft { id: info.id });
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

    let channel = signals;
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

impl From<ClientInfo> for ClientView {
    fn from(info: ClientInfo) -> Self {
        Self {
            id: info.id,
            nickname: info.nickname,
            uid: info.uid,
            channel_id: info.channel_id,
        }
    }
}

struct EventLogger {
    events: broadcast::Sender<SessionEvent>,
}

impl EventLogger {
    fn log(&self, level: &str, message: &str) {
        emit(
            &self.events,
            SessionEvent::Log {
                level: level.to_string(),
                message: message.to_string(),
            },
        );
    }
}

impl Logger for EventLogger {
    fn debug(&self, msg: &str, _args: &[&dyn std::fmt::Display]) {
        self.log("debug", msg);
    }

    fn info(&self, msg: &str, _args: &[&dyn std::fmt::Display]) {
        self.log("info", msg);
    }

    fn warn(&self, msg: &str, _args: &[&dyn std::fmt::Display]) {
        self.log("warn", msg);
    }

    fn error(&self, msg: &str, _args: &[&dyn std::fmt::Display]) {
        self.log("error", msg);
    }
}

/// 上传进度读取器：每 256KiB 或 200ms 发一次进度。
struct ProgressReader {
    inner: tokio::fs::File,
    id: u64,
    total: u64,
    transferred: u64,
    last_emit_bytes: u64,
    last_emit_at: Instant,
    padding: usize,
    padding_sent: bool,
    events: broadcast::Sender<SessionEvent>,
}

impl ProgressReader {
    fn new(
        inner: tokio::fs::File,
        id: u64,
        total: u64,
        events: broadcast::Sender<SessionEvent>,
    ) -> Self {
        let padding = (16 - (total % 16) as usize) % 16;
        Self {
            inner,
            id,
            total,
            transferred: 0,
            last_emit_bytes: 0,
            last_emit_at: Instant::now(),
            padding,
            padding_sent: false,
            events,
        }
    }

    fn maybe_emit(&mut self) {
        if self.transferred.saturating_sub(self.last_emit_bytes) < TRANSFER_PROGRESS_BYTES
            && self.last_emit_at.elapsed() < TRANSFER_PROGRESS_INTERVAL
        {
            return;
        }
        self.last_emit_bytes = self.transferred;
        self.last_emit_at = Instant::now();
        let _ = self.events.send(SessionEvent::TransferProgress {
            id: self.id,
            transferred: self.transferred,
            total: self.total,
        });
    }
}

impl AsyncRead for ProgressReader {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let this = self.get_mut();
        let before = buf.filled().len();
        let poll = Pin::new(&mut this.inner).poll_read(cx, buf);
        if let Poll::Ready(Ok(())) = &poll {
            let read = buf.filled().len() - before;
            if read == 0 && !this.padding_sent && this.padding > 0 {
                // tsclient-rs 的 AES 数据流按 16 字节块加密，尾部不足一块会被静默丢掉；
                // 补零到块边界，服务端按声明的原始 size 截断。
                const ZEROS: [u8; 16] = [0; 16];
                let count = this.padding.min(buf.remaining());
                buf.put_slice(&ZEROS[..count]);
                this.padding_sent = count == this.padding;
                return Poll::Ready(Ok(()));
            }
            this.transferred += read as u64;
            this.maybe_emit();
        }
        poll
    }
}

/// 下载进度写入器。
struct ProgressWriter {
    inner: tokio::fs::File,
    id: u64,
    total: u64,
    transferred: u64,
    last_emit_bytes: u64,
    last_emit_at: Instant,
    events: broadcast::Sender<SessionEvent>,
}

impl ProgressWriter {
    fn new(
        inner: tokio::fs::File,
        id: u64,
        total: u64,
        events: broadcast::Sender<SessionEvent>,
    ) -> Self {
        Self {
            inner,
            id,
            total,
            transferred: 0,
            last_emit_bytes: 0,
            last_emit_at: Instant::now(),
            events,
        }
    }

    fn record(&mut self, written: usize) {
        self.transferred += written as u64;
        if self.transferred.saturating_sub(self.last_emit_bytes) < TRANSFER_PROGRESS_BYTES
            && self.last_emit_at.elapsed() < TRANSFER_PROGRESS_INTERVAL
        {
            return;
        }
        self.last_emit_bytes = self.transferred;
        self.last_emit_at = Instant::now();
        let _ = self.events.send(SessionEvent::TransferProgress {
            id: self.id,
            transferred: self.transferred,
            total: self.total,
        });
    }
}

impl AsyncWrite for ProgressWriter {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        let this = self.get_mut();
        let poll = Pin::new(&mut this.inner).poll_write(cx, buf);
        if let Poll::Ready(Ok(written)) = &poll {
            this.record(*written);
        }
        poll
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_flush(cx)
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_shutdown(cx)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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

    #[tokio::test]
    async fn upload_reader_pads_the_last_aes_block() {
        use tokio::io::AsyncReadExt;

        let dir = std::env::temp_dir().join("flspeak-transfer-padding-test");
        let path = dir.join("payload.bin");
        let _ = tokio::fs::remove_dir_all(&dir).await;
        tokio::fs::create_dir_all(&dir).await.unwrap();
        tokio::fs::write(&path, b"hello").await.unwrap();

        let file = tokio::fs::File::open(&path).await.unwrap();
        let (events, _) = broadcast::channel(8);
        let mut reader = ProgressReader::new(file, 1, 5, events);
        let mut output = Vec::new();
        reader.read_to_end(&mut output).await.unwrap();

        assert_eq!(output.len(), 16, "不足 16 字节的尾部必须补零");
        assert_eq!(&output[..5], b"hello");
        assert!(output[5..].iter().all(|byte| *byte == 0));

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[test]
    fn channel_flags_codec_and_public_metadata_are_parsed() {
        let mut first = HashMap::new();
        first.insert("cid".to_string(), "7".to_string());
        first.insert("channel_order".to_string(), "3".to_string());
        first.insert("channel_topic".to_string(), "Welcome".to_string());
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
        assert_eq!(first.description.as_deref(), Some("Welcome"));
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
