//! 命令循环：所有协议操作在这里串行执行。

use std::collections::{HashMap, HashSet, VecDeque};
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::task::{Context, Poll};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use audio::engine::{AudioEvent, AudioStage, VoiceEngine};
use audio::format::{MAX_PACKET_BYTES, VOICE_CODEC, is_supported_codec};
use audio::playback::VoiceFrame;
use base64::Engine;
use proto::ConnectError;
use server::{ServerError, ServerProfile, ServerRegistry, ServerTarget};
use tokio::io::{AsyncRead, ReadBuf};
use tokio::sync::{broadcast, mpsc, oneshot, watch};
use tsclient_rs::{
    AbortSignal, ChannelInfo, Client, ClientInfo, Event as ProtocolEvent, FileDownloadInfo, Logger,
};

use crate::store::{self, identity_path};
use crate::streams::{self, StreamCoordinator, StreamEndReason};
use crate::{
    AudioDeviceView, AudioDevicesView, ChannelView, ClientView, SessionCommand, SessionError,
    SessionEvent, SessionState, SettingsManager, TextMessageView, TransferDirection,
    VoiceStateView,
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
const MAX_VOICE_QUEUE_DELAY: Duration = Duration::from_millis(100);

/// ServerQuery 单行消息上限。
#[allow(dead_code)]
const MAX_TEXT_MESSAGE_BYTES: usize = 8192;

/// 音频线程到 actor 的事件队列，溢出时丢的是语音包而不是协议命令。
pub(crate) const AUDIO_EVENT_CAPACITY: usize = 64;

/// TeamSpeak 的 “command not found”：服务器不支持 TS6 屏幕共享命令。
const COMMAND_NOT_FOUND: &str = "256";
const STREAM_PROBE_TIMEOUT_MS: u64 = 5_000;

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
    /// 目录快照（0.2.1 起目录一变就发）：携带最新的成员状态，含静音标志。
    Snapshot {
        epoch: u64,
        clients: Vec<ClientView>,
    },
    Disconnected {
        epoch: u64,
        message: String,
    },
    Kicked {
        epoch: u64,
        message: String,
    },
    ClientLeft {
        epoch: u64,
        id: i32,
    },
    /// TS6 屏幕共享相关的原始通知，一条通知可能带多行。
    StreamNotification {
        epoch: u64,
        name: String,
        items: Vec<HashMap<String, String>>,
    },
    /// 原始通知队列溢出过，流目录可能漏了更新，需要重新发现。
    StreamResync {
        epoch: u64,
    },
    /// `notifyconnectioninfo`：服务器返回自身连接的权威统计。
    ConnectionInfo {
        epoch: u64,
        items: Vec<HashMap<String, String>>,
    },
    /// 服务器要求本端用 `setconnectioninfo` 上报连接统计。
    ConnectionInfoRequested {
        epoch: u64,
    },
}

pub(crate) struct SessionAudio {
    pub voice: VoiceEngine,
    pub events: mpsc::Receiver<AudioEvent>,
    pub levels: crate::events::LevelPublisher,
    pub enabled: bool,
}

type ImageNegotiation =
    Pin<Box<dyn std::future::Future<Output = Result<(String, FileDownloadInfo), SessionError>>>>;

struct PendingImage {
    remote_path: String,
    reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
}

struct ActiveImage {
    negotiation: ImageNegotiation,
    reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
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
    levels: crate::events::LevelPublisher,
    logger: Arc<dyn Logger>,
    state: SessionState,
    client: Option<Arc<Client>>,
    self_client_id: Option<i32>,
    self_channel_id: u64,
    active_server_id: Option<String>,
    transfer_target: Option<ServerTarget>,
    last_target: Option<ConnectTarget>,
    generation: u64,
    reconnect_attempt: u32,
    auto_reconnect: bool,
    voice_state: VoiceStateView,
    input_device: Option<String>,
    output_device: Option<String>,
    capture_active: bool,
    audio_since: Instant,
    audio_enabled: bool,
    last_snapshot: Option<(Vec<ChannelView>, Vec<ClientView>)>,
    channel_codecs: HashMap<u64, i32>,
    channel_tools: crate::channel_tools::ChannelTools,
    current_codec: i32,
    ever_connected: bool,
    consecutive_timeouts: u32,
    identity_upgrade: Option<Arc<AbortSignal>>,
    identity_upgrading: bool,
    next_transfer_id: u64,
    connection_epoch: u64,
    epoch: Arc<AtomicU64>,
    streams: StreamCoordinator,
    /// 当前连接的服务器是否认识 TS6 流命令；首次探测返回 command not found 后关闭。
    streams_supported: bool,
    network_monitor: Option<crate::network::NetworkMonitor>,
    pending_images: VecDeque<PendingImage>,
    active_image: Option<ActiveImage>,
    disconnect_tx: watch::Sender<u64>,
    disconnect_rx: watch::Receiver<u64>,
}

impl Actor {
    pub(crate) fn new(
        store_path: PathBuf,
        registry: ServerRegistry,
        events: broadcast::Sender<SessionEvent>,
        commands: mpsc::UnboundedSender<SessionCommand>,
        audio: SessionAudio,
    ) -> Self {
        let SessionAudio {
            voice,
            events: audio_events,
            levels,
            enabled: audio_enabled,
        } = audio;
        let (signals, signal_rx) = mpsc::unbounded_channel();
        let (disconnect_tx, disconnect_rx) = watch::channel(0);
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
            levels,
            logger,
            state: SessionState::Disconnected,
            client: None,
            self_client_id: None,
            self_channel_id: 0,
            active_server_id: None,
            transfer_target: None,
            last_target: None,
            generation: 0,
            reconnect_attempt: 0,
            auto_reconnect: true,
            voice_state: VoiceStateView::default(),
            input_device: None,
            output_device: None,
            capture_active: false,
            audio_since: Instant::now(),
            audio_enabled,
            last_snapshot: None,
            channel_codecs: HashMap::new(),
            channel_tools: Default::default(),
            current_codec: VOICE_CODEC,
            ever_connected: false,
            consecutive_timeouts: 0,
            identity_upgrade: None,
            identity_upgrading: false,
            next_transfer_id: 1,
            connection_epoch: 0,
            epoch: Arc::new(AtomicU64::new(0)),
            streams: StreamCoordinator::default(),
            streams_supported: true,
            network_monitor: None,
            pending_images: VecDeque::new(),
            active_image: None,
            disconnect_tx,
            disconnect_rx,
        }
    }

    pub(crate) async fn run(&mut self, mut commands: mpsc::UnboundedReceiver<SessionCommand>) {
        let mut snapshots = tokio::time::interval(crate::SNAPSHOT_INTERVAL);
        snapshots.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        // interval 的第一次 tick 立即就绪；消费掉，避免刚启动就发空快照。
        snapshots.tick().await;

        loop {
            // 排空音频事件，保证语音帧零延迟分发
            while let Ok(event) = self.audio_events.try_recv() {
                self.handle_audio(event);
            }

            if self.active_image.is_none() && !self.pending_images.is_empty() {
                self.start_next_image();
            }

            tokio::select! {
                command = commands.recv() => {
                    match command {
                        Some(SessionCommand::Shutdown) => {
                            self.cancel_active_image();
                            break;
                        }
                        Some(command) => {
                            let is_image_request = matches!(
                                command,
                                SessionCommand::FetchAvatar { .. } | SessionCommand::FetchIcon { .. }
                            );
                            if !is_image_request {
                                self.interrupt_active_image();
                            }
                            if !self.handle(command).await {
                                break;
                            }
                        }
                        None => {
                            self.cancel_active_image();
                            break;
                        }
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
                result = async {
                    match &mut self.active_image {
                        Some(active) => active.negotiation.as_mut().await,
                        None => std::future::pending().await,
                    }
                } => {
                    let active = self.active_image.take().expect("polled image request");
                    self.finish_server_image(result, active.reply);
                }
                _ = snapshots.tick() => {
                    self.interrupt_active_image();
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
            SessionCommand::UpdateServer {
                id,
                label,
                address,
                reply,
            } => {
                let _ = reply.send(self.update_server(id, label, address));
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
            SessionCommand::Poke {
                client_id,
                message,
                reply,
            } => {
                let result = match self.connected() {
                    Ok(client) => tsclient_rs::poke(&client, client_id, &message)
                        .await
                        .map_err(protocol_error),
                    Err(err) => Err(err),
                };
                let _ = reply.send(result);
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
            SessionCommand::ChannelDescription { channel_id, reply } => {
                let _ = reply.send(self.channel_description(channel_id).await);
            }
            SessionCommand::ListClients { reply } => {
                let _ = reply.send(self.list_clients().await);
            }
            SessionCommand::RequestSnapshot { reply } => {
                let _ = reply.send(self.refresh_snapshot(true).await);
            }
            SessionCommand::SampleNetwork { reply } => {
                let _ = reply.send(self.sample_network());
            }
            SessionCommand::Access { reply } => {
                let result = match self.connected() {
                    Ok(client) => crate::channel_tools::access(&client, &mut self.channel_tools)
                        .await
                        .map(|mut access| {
                            access.connection_epoch = Some(self.connection_epoch);
                            access
                        }),
                    Err(error) => Err(error),
                };
                let _ = reply.send(result);
            }
            SessionCommand::Kick {
                uid,
                client_id,
                channel_id,
                target,
                reason,
                connection_epoch,
                reply,
            } => {
                let result = if connection_epoch != self.connection_epoch {
                    Err(SessionError::Protocol("connection changed".into()))
                } else {
                    match self.connected() {
                        Ok(client) => {
                            crate::channel_tools::kick(
                                &client,
                                &mut self.channel_tools,
                                &uid,
                                client_id,
                                channel_id,
                                target,
                                &reason,
                            )
                            .await
                        }
                        Err(error) => Err(error),
                    }
                };
                let _ = reply.send(result);
            }
            SessionCommand::MemberGroups {
                uid,
                client_id,
                reply,
            } => {
                let result = match self.connected() {
                    Ok(client) => {
                        crate::channel_tools::member_groups(
                            &client,
                            &uid,
                            client_id,
                            &mut self.channel_tools,
                        )
                        .await
                    }
                    Err(error) => Err(error),
                };
                let _ = reply.send(result);
            }
            SessionCommand::SetMemberGroup {
                uid,
                client_id,
                group_id,
                channel_id,
                kind,
                enabled,
                reply,
            } => {
                let result = match self.connected() {
                    Ok(client) => {
                        crate::channel_tools::set_member_group(
                            &client,
                            (&uid, client_id),
                            group_id,
                            channel_id,
                            kind,
                            enabled,
                            &mut self.channel_tools,
                        )
                        .await
                    }
                    Err(error) => Err(error),
                };
                let _ = reply.send(result);
            }
            SessionCommand::ListFiles {
                channel_id,
                path,
                password,
                reply,
            } => {
                let result = match self.connected() {
                    Ok(client) => {
                        crate::channel_tools::files(&client, channel_id, &path, &password).await
                    }
                    Err(error) => Err(error),
                };
                let _ = reply.send(result);
            }
            SessionCommand::SetMuted { muted, reply } => {
                let _ = reply.send(self.set_muted(muted).await);
            }
            SessionCommand::SetDeafened { deafened, reply } => {
                let _ = reply.send(self.set_deafened(deafened).await);
            }
            SessionCommand::SetAway { away, reply } => {
                let _ = reply.send(self.set_away(away).await);
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
            SessionCommand::FetchIcon { icon_id, reply } => {
                self.fetch_icon(icon_id, reply);
            }
            SessionCommand::FetchAvatar { uid, reply } => match avatar_file_name(&uid) {
                Ok(path) => self.fetch_server_image(&path, reply),
                Err(error) => {
                    let _ = reply.send(Err(error));
                }
            },
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
            SessionCommand::JoinStream {
                stream_id,
                source_clid,
                reply,
            } => {
                let _ = reply.send(self.join_stream(stream_id, source_clid).await);
            }
            SessionCommand::LeaveStream { stream_id, reply } => {
                let _ = reply.send(self.leave_stream(stream_id).await);
            }
            SessionCommand::SendStreamAnswer {
                stream_id,
                target_clid,
                sdp,
                reply,
            } => {
                let result = match self.streams.check_signal_target(&stream_id, target_clid) {
                    Ok(()) => {
                        self.stream_signaling(
                            &stream_id,
                            target_clid,
                            streams::answer_payload(&sdp),
                        )
                        .await
                    }
                    Err(err) => Err(err),
                };
                let _ = reply.send(result);
            }
            SessionCommand::SendStreamIceCandidate {
                stream_id,
                target_clid,
                sdp,
                mid,
                m_line,
                reply,
            } => {
                let result = match self.streams.check_signal_target(&stream_id, target_clid) {
                    Ok(()) => {
                        let payload = streams::ice_payload(&sdp, mid.as_deref(), m_line);
                        self.stream_signaling(&stream_id, target_clid, payload)
                            .await
                    }
                    Err(err) => Err(err),
                };
                let _ = reply.send(result);
            }
            SessionCommand::StartScreenShare {
                name,
                audio,
                bitrate,
                viewer_limit,
                reply,
            } => {
                let _ = reply.send(
                    self.start_screen_share(name, audio, bitrate, viewer_limit)
                        .await,
                );
            }
            SessionCommand::StopScreenShare { reply } => {
                let _ = reply.send(self.stop_screen_share().await);
            }
            SessionCommand::RespondStreamJoinRequest {
                viewer_clid,
                accept,
                offer_sdp,
                reply,
            } => {
                let _ = reply.send(
                    self.respond_stream_join_request(viewer_clid, accept, offer_sdp)
                        .await,
                );
            }
            SessionCommand::SendPublisherIceCandidate {
                viewer_clid,
                sdp,
                mid,
                m_line,
                reply,
            } => {
                let _ = reply.send(
                    self.send_publisher_ice_candidate(viewer_clid, sdp, mid, m_line)
                        .await,
                );
            }
            SessionCommand::KickStreamViewer { viewer_clid, reply } => {
                let _ = reply.send(self.kick_stream_viewer(viewer_clid).await);
            }
        }
        true
    }

    async fn register(
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

    async fn remove(&mut self, id: String) -> Result<(), SessionError> {
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
        Ok(())
    }

    fn update_server(
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
        Ok(profile)
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
                }
                if let Err(err) = self.refresh_snapshot(true).await {
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: err.to_string(),
                    });
                }
                self.start_voice();
                // 服务器端自己的标志在（重）连后是重置过的，把本地状态重新同步。
                self.report_voice_flags().await;
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

    async fn send_text(
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

    async fn move_to_channel(
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

    async fn list_channels(&mut self) -> Result<Vec<ChannelView>, SessionError> {
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

    async fn channel_description(&self, channel_id: u64) -> Result<String, SessionError> {
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

    async fn list_clients(&self) -> Result<Vec<ClientView>, SessionError> {
        let client = self.connected()?;
        self.read_clients(&client).await
    }

    /// 成员列表 = clientlist 与欢迎目录快照的合并，再保证自己这一行可信。
    ///
    /// 部分 TS6 服务器的 clientlist 行缺 `cid`（解析成 0），而欢迎目录的
    /// `channelclientlist` 行频道是准的；反过来目录可能漏掉后来进出的成员。
    /// 两边按 id 合并：clientlist 的标志新，目录的频道准。
    async fn read_clients(&self, client: &Arc<Client>) -> Result<Vec<ClientView>, SessionError> {
        let listed = tsclient_rs::listClients(client).await;
        let directory = client
            .directory_snapshot()
            .map(|snapshot| snapshot.clients)
            .unwrap_or_default();
        let mut rows = match listed {
            Ok(listed) => merged_clients(listed, directory),
            Err(err) => {
                // 目录还没同步完（None 或空）时同样拿不到成员，回退到原错误。
                if directory.is_empty() {
                    return Err(protocol_error(err));
                }
                directory.into_iter().map(ClientView::from).collect()
            }
        };
        self.ensure_self_row(client, &mut rows).await;
        Ok(rows)
    }

    /// 自身行修补：本地已知频道时无网补齐；首次未知用 `whoami` 学习。
    ///
    /// TS6 服务器对推送进来的自己的行缺省 `cid`（官方客户端从别的渠道知道
    /// 自己在哪），访客又常被拒 `clientinfo`；`whoami` 免权限且带
    /// `client_channel_id`。补全结果由 refresh 的交叉检查写回会话状态。
    async fn ensure_self_row(&self, client: &Arc<Client>, rows: &mut Vec<ClientView>) {
        let Some(self_id) = self.self_client_id else {
            return;
        };
        let known = rows.iter().find(|row| row.id == self_id);
        if known.is_some_and(|row| row.channel_id != 0) {
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
        };
        match rows.iter_mut().find(|row| row.id == self_id) {
            Some(row) => *row = view,
            None => rows.push(view),
        }
    }

    /// 已知自己频道时的无网修补：目录推送对 TS6 服务器永远给 0 频道的自己，
    /// 用会话状态里确认过的频道与本地语音状态补齐，缺行则合成。
    fn patch_self_row(&self, rows: &mut Vec<ClientView>) {
        let Some(self_id) = self.self_client_id else {
            return;
        };
        match rows.iter_mut().find(|row| row.id == self_id) {
            Some(row) => {
                if row.channel_id == 0 {
                    row.channel_id = self.self_channel_id;
                }
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
                input_muted: Some(self.voice_state.muted || self.voice_state.deafened),
                output_muted: Some(self.voice_state.deafened),
                away: Some(self.voice_state.away),
                away_message: None,
            }),
        }
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

        let clients = match self.read_clients(&client).await {
            Ok(clients) => clients,
            Err(err) => {
                failures.push(format!("成员列表: {err}"));
                previous
                    .as_ref()
                    .map(|(_, clients)| clients.clone())
                    .unwrap_or_default()
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
            // cid=0 的行说明这路数据没带频道，不能拿它重置自己的真实频道。
            if me.channel_id != 0 && me.channel_id != self.self_channel_id {
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
        self.sync_stream_channel().await;
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
        &mut self,
        client: &Client,
    ) -> Result<ChannelDirectory, SessionError> {
        // 复用已有目录请求采样，避免额外探测占用语音发送所在的 actor。
        let started = Instant::now();
        let result = tsclient_rs::listChannels(client).await;
        if let Some(monitor) = &mut self.network_monitor {
            // 权限拒绝也是服务器的有效回复，不能当作网络丢失。
            let reached = matches!(&result, Ok(_) | Err(tsclient_rs::Error::ServerError { .. }));
            let round_trip_ms = reached.then(|| started.elapsed().as_secs_f64() * 1_000.0);
            let telemetry = monitor.record(round_trip_ms, now_millis());
            self.emit(SessionEvent::Network(telemetry));
        }
        let (channels, explicit_list_worked) = match result {
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

    async fn set_muted(&mut self, muted: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_muted(muted)?;
        }
        self.voice_state.muted = muted;
        self.audio_since = Instant::now();
        if muted {
            self.emit(SessionEvent::SelfSpeaking { speaking: false });
            self.voice_state.ptt_active = false;
            if self.audio_enabled {
                let _ = self.voice.set_ptt_active(false);
            }
        }
        self.emit_voice_state();
        self.report_voice_flags().await;
        Ok(())
    }

    async fn set_deafened(&mut self, deafened: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_deafened(deafened)?;
        }
        self.voice_state.deafened = deafened;
        self.audio_since = Instant::now();
        if deafened {
            self.emit(SessionEvent::SelfSpeaking { speaking: false });
            self.voice_state.ptt_active = false;
            if self.audio_enabled {
                let _ = self.voice.set_ptt_active(false);
            }
        }
        self.emit_voice_state();
        self.report_voice_flags().await;
        Ok(())
    }

    /// 把自己的静音/聋听/离开状态上报给服务器，其他客户端才能看到标志。
    /// 本地门控已经生效，上报失败只记日志不回滚。
    async fn report_voice_flags(&self) {
        let Some(client) = self.client.clone() else {
            return;
        };
        let (input, output) = mute_flags(self.voice_state.muted, self.voice_state.deafened);
        let params = vec![
            ("client_input_muted", input),
            ("client_output_muted", output),
            ("client_away", if self.voice_state.away { "1" } else { "0" }),
        ];
        if let Err(err) = tsclient_rs::clientUpdate(&client, &params).await {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("状态上报失败: {err}"),
            });
        }
    }

    /// 离开只是服务器上的标志，不影响本地音频采集与播放。
    async fn set_away(&mut self, away: bool) -> Result<(), SessionError> {
        self.voice_state.away = away;
        self.emit_voice_state();
        self.report_voice_flags().await;
        Ok(())
    }

    fn set_ptt_mode(&mut self, enabled: bool) -> Result<(), SessionError> {
        if self.audio_enabled {
            self.voice.set_ptt_mode(enabled)?;
        }
        self.voice_state.ptt_mode = enabled;
        self.audio_since = Instant::now();
        if enabled && !self.voice_state.ptt_active {
            self.emit(SessionEvent::SelfSpeaking { speaking: false });
        }
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
        self.audio_since = Instant::now();
        if !active {
            self.emit(SessionEvent::SelfSpeaking { speaking: false });
        }
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
        self.audio_since = Instant::now();
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

    fn fetch_icon(&mut self, icon_id: u32, reply: oneshot::Sender<Result<Vec<u8>, SessionError>>) {
        if icon_id == 0 {
            let _ = reply.send(Err(SessionError::Transfer(
                "icon id must be nonzero".into(),
            )));
            return;
        }
        self.fetch_server_image(&tsclient_rs::icon_file_name(icon_id), reply);
    }

    fn fetch_server_image(
        &mut self,
        remote_path: &str,
        reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
    ) {
        if self.pending_images.len() >= 32 {
            let _ = reply.send(Err(SessionError::Transfer(
                "image request queue is full".into(),
            )));
            return;
        }
        self.pending_images.push_back(PendingImage {
            remote_path: remote_path.to_owned(),
            reply,
        });
    }

    fn start_next_image(&mut self) {
        if self.active_image.is_some() {
            return;
        }
        let Some(pending) = self.pending_images.pop_front() else {
            return;
        };
        let target = (|| {
            let client = self.connected()?;
            let target = self
                .transfer_target
                .as_ref()
                .ok_or(SessionError::NotConnected)?;
            proto::check_transfer_host(target, &target.host)?;
            Ok::<_, SessionError>((client, target.host.clone()))
        })();
        let (client, host) = match target {
            Ok(target) => target,
            Err(error) => {
                let _ = pending.reply.send(Err(error));
                return;
            }
        };
        let path = pending.remote_path;
        self.active_image = Some(ActiveImage {
            reply: pending.reply,
            negotiation: Box::pin(async move {
                let info = tokio::time::timeout(
                    Duration::from_secs(5),
                    client.file_transfer_init_download(0, &path, ""),
                )
                .await
                .map_err(|_| SessionError::Timeout)?
                .map_err(protocol_error)?;
                validate_port(info.port)?;
                if info.size == 0 || info.size > 1024 * 1024 {
                    return Err(SessionError::Transfer(
                        "image size must be between 1 byte and 1 MiB".into(),
                    ));
                }
                Ok((host, info))
            }),
        });
    }

    fn interrupt_active_image(&mut self) {
        if let Some(active) = self.active_image.take() {
            let _ = active.reply.send(Err(SessionError::Transfer(
                "image negotiation interrupted".into(),
            )));
        }
    }

    fn cancel_active_image(&mut self) {
        if let Some(active) = self.active_image.take() {
            let _ = active.reply.send(Err(SessionError::NotConnected));
        }
    }

    fn finish_server_image(
        &self,
        negotiated: Result<(String, FileDownloadInfo), SessionError>,
        reply: oneshot::Sender<Result<Vec<u8>, SessionError>>,
    ) {
        let (host, info) = match negotiated {
            Ok(value) => value,
            Err(error) => {
                let _ = reply.send(Err(error));
                return;
            }
        };
        let epoch = self.connection_epoch;
        let mut disconnect_rx = self.disconnect_rx.clone();
        // 仅 TCP 字节传输离开 actor；Client 的协商仍在命令队列中串行执行。
        tokio::task::spawn_local(async move {
            let download = async {
                let mut bytes = Vec::with_capacity(info.size as usize);
                tsclient_rs::downloadFileData(&host, &info, &mut bytes)
                    .await
                    .map_err(protocol_error)?;
                Ok(bytes)
            };
            let outcome = tokio::select! {
                res = tokio::time::timeout(Duration::from_secs(20), download) => {
                    res.unwrap_or(Err(SessionError::Timeout))
                }
                _ = async {
                    while disconnect_rx.changed().await.is_ok() {
                        if *disconnect_rx.borrow() != epoch {
                            break;
                        }
                    }
                } => {
                    Err(SessionError::NotConnected)
                }
            };
            let _ = reply.send(outcome);
        });
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
        let target = self
            .transfer_target
            .as_ref()
            .ok_or(SessionError::NotConnected)?;
        proto::check_transfer_host(target, &target.host)?;

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
                &crate::channel_tools::channel_password(password.as_deref().unwrap_or("")),
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
            let outcome = tsclient_rs::uploadFileData(&host, &info, reader).await;
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
        crate::channel_tools::remote_path(&remote_path)?;
        if PathBuf::from(&local_path)
            .try_exists()
            .map_err(|error| SessionError::Transfer(error.to_string()))?
        {
            return Err(SessionError::Transfer("destination already exists".into()));
        }
        if channel_id == 0 {
            return Err(SessionError::NotInChannel);
        }
        let client = self.connected()?;
        let target = self
            .transfer_target
            .as_ref()
            .ok_or(SessionError::NotConnected)?;
        proto::check_transfer_host(target, &target.host)?;

        let info: FileDownloadInfo = client
            .file_transfer_init_download(
                channel_id,
                &remote_path,
                &crate::channel_tools::channel_password(password.as_deref().unwrap_or("")),
            )
            .await
            .map_err(protocol_error)?;
        validate_port(info.port)?;

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
        let epoch = self.connection_epoch;
        let current = Arc::clone(&self.epoch);
        tokio::task::spawn_local(async move {
            let outcome = crate::downloads::receive(
                host,
                info,
                PathBuf::from(local_path),
                id,
                events.clone(),
                epoch,
                current,
            )
            .await;
            let _ = events.send(SessionEvent::TransferFinished {
                id,
                error: outcome.err().map(|error| error.to_string()),
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
                if epoch != self.connection_epoch {
                    return;
                }
                if self.self_client_id == Some(id) {
                    self.on_self_moved(channel_id).await;
                    self.sync_stream_channel().await;
                } else {
                    let events = self.streams.client_moved(id, channel_id);
                    self.emit_all(events);
                    // 已在共享的人进了本频道：问一次他的流。
                    if channel_id != 0 && channel_id == self.streams.channel() {
                        self.query_stream_info(id).await;
                    }
                }
            }
            SessionSignal::ClientLeft { epoch, id } => {
                if epoch == self.connection_epoch {
                    let events = self.streams.client_left(id);
                    self.emit_all(events);
                }
            }
            SessionSignal::StreamNotification { epoch, name, items } => {
                if epoch != self.connection_epoch {
                    return;
                }
                let client = self.client.as_ref();
                let last_snapshot = self.last_snapshot.as_ref();
                let mut out = Vec::new();
                for params in &items {
                    if name == "notifystreamsignaling" {
                        self.emit(SessionEvent::Log {
                            level: "debug".into(),
                            message: format!(
                                "收到 notifystreamsignaling: id={}, clid={}, json={}",
                                params.get("id").map(String::as_str).unwrap_or("-"),
                                params.get("clid").map(String::as_str).unwrap_or("-"),
                                params
                                    .get("json")
                                    .or_else(|| params.get("data"))
                                    .map(|raw| truncate_log(raw, 160))
                                    .unwrap_or_else(|| "-".into()),
                            ),
                        });
                    }
                    let events =
                        self.streams
                            .notification(&name, params, self.self_client_id, |clid| {
                                client_channel(client, last_snapshot, clid)
                            });
                    out.extend(events);
                }
                self.emit_all(out);
                for stream_id in self.streams.take_orphan_streams() {
                    self.stop_stream_best_effort(&stream_id).await;
                }
            }
            SessionSignal::StreamResync { epoch } => {
                if epoch == self.connection_epoch {
                    self.discover_streams().await;
                }
            }
            SessionSignal::ConnectionInfo { epoch, items } => {
                if epoch != self.connection_epoch {
                    return;
                }
                let Some(params) = items.iter().find(|item| match self.self_client_id {
                    Some(id) => {
                        item.get("clid").and_then(|value| value.parse::<i32>().ok()) == Some(id)
                    }
                    None => true,
                }) else {
                    return;
                };
                let Some(monitor) = &mut self.network_monitor else {
                    return;
                };
                monitor.apply_connection_info(params);
                let telemetry = monitor.snapshot(now_millis());
                self.emit(SessionEvent::Network(telemetry));
            }
            SessionSignal::ConnectionInfoRequested { epoch } => {
                if epoch == self.connection_epoch {
                    self.answer_connection_info_request();
                }
            }
            SessionSignal::Snapshot { epoch, clients } => {
                if epoch != self.connection_epoch {
                    return;
                }
                // 只有成员状态真的变了才转发；频道元数据仍由周期性的
                // refresh_snapshot 维护，这里只替换成员并同步基线。
                let Some((channels, previous)) = self.last_snapshot.clone() else {
                    return;
                };
                // TS6 服务器推给自己的行永远缺频道，用会话状态补齐再比较。
                let mut clients = clients;
                self.patch_self_row(&mut clients);
                if previous == clients {
                    return;
                }
                if let Some((_, old_clients)) = self.last_snapshot.as_mut() {
                    *old_clients = clients.clone();
                }
                self.emit(SessionEvent::Snapshot { channels, clients });
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

    /// 流目录与本地推流都跟随自己所在的频道。频道变了就作废旧目录、退出观看流并停止推流，再在新频道里发现。
    async fn sync_stream_channel(&mut self) {
        let channel = self.self_channel_id;
        if self.streams.channel() == channel {
            return;
        }
        let watched = self.streams.watching().map(|(id, _)| id.to_string());
        let published = self.streams.published_stream_id().map(str::to_string);
        let events = self.streams.reset(channel, StreamEndReason::SelfMoved);
        self.emit_all(events);
        if let Some(stream_id) = watched {
            self.leave_stream_best_effort(&stream_id).await;
        }
        if let Some(stream_id) = published {
            self.stop_stream_best_effort(&stream_id).await;
        }
        if channel != 0 {
            self.discover_streams().await;
        }
    }

    /// 断线时只清本地状态：连接已不可用，服务器会自己回收观看关系。
    fn reset_streams(&mut self, reason: StreamEndReason) {
        let events = self.streams.reset(0, reason);
        self.emit_all(events);
    }

    /// TS6 进频道时不重放已有的流，逐个问本频道成员。
    ///
    /// 第一条用带回执的命令探测服务器是否认识 `requeststreaminfo`；其余不等回执，
    /// 避免成员多时每人一个往返地卡住 actor。结果经 `notifystreaminfo` 回来。
    async fn discover_streams(&mut self) {
        if !self.streams_supported {
            return;
        }
        let Some(client) = self.client.clone() else {
            return;
        };
        let targets = self.channel_peers(self.streams.channel());
        for (index, clid) in targets.into_iter().enumerate() {
            let command = format!("requeststreaminfo clid={clid}");
            if index == 0 {
                match client.exec_command(&command, STREAM_PROBE_TIMEOUT_MS).await {
                    Ok(()) => {}
                    Err(tsclient_rs::Error::ServerError { id, .. }) if id == COMMAND_NOT_FOUND => {
                        self.streams_supported = false;
                        self.emit(SessionEvent::Log {
                            level: "info".into(),
                            message: "服务器不支持 TS6 屏幕共享".into(),
                        });
                        return;
                    }
                    Err(err) => self.emit(SessionEvent::Log {
                        level: "debug".into(),
                        message: format!("查询客户端 {clid} 的屏幕共享失败: {err}"),
                    }),
                }
            } else if let Err(err) = client.send_command_no_wait(&command).await {
                self.emit(SessionEvent::Log {
                    level: "warn".into(),
                    message: format!("屏幕共享发现中断: {err}"),
                });
                return;
            }
        }
    }

    async fn query_stream_info(&self, clid: i32) {
        if !self.streams_supported {
            return;
        }
        let Some(client) = self.client.clone() else {
            return;
        };
        if let Err(err) = client
            .send_command_no_wait(&format!("requeststreaminfo clid={clid}"))
            .await
        {
            self.emit(SessionEvent::Log {
                level: "debug".into(),
                message: format!("查询客户端 {clid} 的屏幕共享失败: {err}"),
            });
        }
    }

    async fn join_stream(
        &mut self,
        stream_id: String,
        source_clid: i32,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let (previous, events) = self.streams.begin_join(&stream_id, source_clid)?;
        self.emit_all(events);
        if let Some(previous) = previous {
            self.leave_stream_best_effort(&previous).await;
        }
        let result = self
            .stream_command(
                "joinstreamrequest",
                &streams::join_request(&stream_id, source_clid),
            )
            .await;
        if result.is_err() {
            let events = self.streams.abandon_join(&stream_id);
            self.emit_all(events);
        }
        result
    }

    /// 本地状态先清掉再通知服务器，命令失败也不会留下悬空的观看状态。
    async fn leave_stream(&mut self, stream_id: String) -> Result<(), SessionError> {
        let events = self.streams.leave(&stream_id)?;
        self.emit_all(events);
        self.send_stream_leave(&stream_id).await
    }

    async fn leave_stream_best_effort(&self, stream_id: &str) {
        if let Err(err) = self.send_stream_leave(stream_id).await {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("退出屏幕共享 {stream_id} 失败: {err}"),
            });
        }
    }

    async fn send_stream_leave(&self, stream_id: &str) -> Result<(), SessionError> {
        let self_clid = self.self_client_id.ok_or(SessionError::NotConnected)?;
        self.stream_command(
            "removeclientfromstream",
            &streams::leave_request(stream_id, self_clid),
        )
        .await
    }

    async fn start_screen_share(
        &mut self,
        name: String,
        audio: bool,
        bitrate: u32,
        viewer_limit: u32,
    ) -> Result<(), SessionError> {
        self.connected()?;
        if self.self_channel_id == 0 {
            return Err(SessionError::NotInChannel);
        }
        let params = self
            .streams
            .start_publish(&name, audio, bitrate, viewer_limit)?;
        let result = self.stream_command("setupstream", &params).await;
        if result.is_err() {
            self.streams.rollback_publish();
        }
        result
    }

    async fn stop_screen_share(&mut self) -> Result<(), SessionError> {
        let (active_stream_id, events) = self.streams.stop_publish();
        self.emit_all(events);
        if let Some(stream_id) = active_stream_id
            && self.client.is_some()
        {
            self.stream_command("stopstream", &streams::stop_stream_request(&stream_id))
                .await?;
        }
        Ok(())
    }

    async fn stop_stream_best_effort(&self, stream_id: &str) {
        if let Err(err) = self
            .stream_command("stopstream", &streams::stop_stream_request(stream_id))
            .await
        {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!("停止屏幕共享 {stream_id} 失败: {err}"),
            });
        }
    }

    async fn respond_stream_join_request(
        &mut self,
        viewer_clid: i32,
        accept: bool,
        offer_sdp: String,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let params = self
            .streams
            .respond_viewer_join(viewer_clid, accept, &offer_sdp)?;
        self.emit(SessionEvent::Log {
            level: "debug".into(),
            message: format!(
                "发送 respondjoinstreamrequest: 观众={viewer_clid}, accept={accept}, offer_sdp_len={}",
                offer_sdp.len()
            ),
        });
        let result = self
            .stream_command("respondjoinstreamrequest", &params)
            .await;
        if result.is_err() {
            self.streams.remove_viewer(viewer_clid);
        }
        result
    }

    async fn send_publisher_ice_candidate(
        &self,
        viewer_clid: i32,
        sdp: String,
        mid: Option<String>,
        m_line: Option<i32>,
    ) -> Result<(), SessionError> {
        self.connected()?;
        let stream_id = self
            .streams
            .check_publisher_signal_target(viewer_clid)?
            .to_string();
        let payload = streams::ice_payload(&sdp, mid.as_deref(), m_line);
        self.stream_signaling(&stream_id, viewer_clid, payload)
            .await
    }

    async fn kick_stream_viewer(&mut self, viewer_clid: i32) -> Result<(), SessionError> {
        self.connected()?;
        let (params, event) = self.streams.kick_viewer(viewer_clid)?;
        self.emit(event);
        self.stream_command("removeclientfromstream", &params).await
    }

    async fn stream_signaling(
        &self,
        stream_id: &str,
        target_clid: i32,
        payload: String,
    ) -> Result<(), SessionError> {
        self.stream_command(
            "streamsignaling",
            &[
                ("id", stream_id.to_string()),
                ("clid", target_clid.to_string()),
                ("json", payload),
            ],
        )
        .await
    }

    async fn stream_command(
        &self,
        command: &str,
        params: &[(&'static str, String)],
    ) -> Result<(), SessionError> {
        let client = self.connected()?;
        let params: Vec<(&str, &str)> = params.iter().map(|(k, v)| (*k, v.as_str())).collect();
        client
            .send_raw_command(command, &params)
            .await
            .map_err(protocol_error)
    }

    fn channel_peers(&self, channel: u64) -> Vec<i32> {
        let mut peers = Vec::new();
        let mut seen = HashSet::new();
        if let Some(snapshot) = self
            .client
            .as_ref()
            .and_then(|client| client.directory_snapshot())
        {
            for row in snapshot.clients {
                if row.channel_id == channel
                    && Some(row.id) != self.self_client_id
                    && seen.insert(row.id)
                {
                    peers.push(row.id);
                }
            }
        }
        if let Some((_, clients)) = &self.last_snapshot {
            for row in clients {
                if row.channel_id == channel
                    && Some(row.id) != self.self_client_id
                    && seen.insert(row.id)
                {
                    peers.push(row.id);
                }
            }
        }
        peers
    }

    fn handle_audio(&mut self, event: AudioEvent) {
        match event {
            AudioEvent::Outbound {
                codec,
                data,
                produced_at,
            } => {
                if !self.can_send_voice(codec, produced_at, Instant::now()) {
                    return;
                }
                if data.len() > MAX_PACKET_BYTES {
                    crate::log_error!(
                        size = data.len(),
                        max = MAX_PACKET_BYTES;
                        "encoding layer constraint violated: packet exceeds budget"
                    );
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
                self.emit(SessionEvent::SelfSpeaking {
                    speaking: speaking && self.voice_gate_open(),
                });
            }
            AudioEvent::CaptureState { ready } => {
                self.voice_state.input_ready = ready;
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

    fn voice_gate_open(&self) -> bool {
        matches!(self.state, SessionState::Connected { .. })
            && self.self_channel_id != 0
            && self.capture_active
            && !self.voice_state.muted
            && !self.voice_state.deafened
            && (!self.voice_state.ptt_mode || self.voice_state.ptt_active)
    }

    fn can_send_voice(&self, codec: i32, produced_at: Instant, now: Instant) -> bool {
        self.voice_gate_open()
            && codec == self.current_codec
            && produced_at >= self.audio_since
            && now.saturating_duration_since(produced_at) <= MAX_VOICE_QUEUE_DELAY
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
        self.reset_streams(StreamEndReason::Disconnected);
        self.set_state(SessionState::Disconnected);
    }

    fn connected(&self) -> Result<Arc<Client>, SessionError> {
        self.client.clone().ok_or(SessionError::NotConnected)
    }

    /// 遥测面板打开时按需查询自身连接统计。查询本身在后台任务里完成，
    /// 不占用 actor 的命令循环；结果通过 `notifyconnectioninfo` 回到信号队列。
    fn sample_network(&self) -> Result<(), SessionError> {
        let client = self.connected()?;
        let client_id = self.self_client_id.ok_or(SessionError::NotConnected)?;
        tokio::task::spawn_local(async move {
            let client_id = client_id.to_string();
            let _ = client
                .send_raw_command("getconnectioninfo", &[("clid", client_id.as_str())])
                .await;
        });
        Ok(())
    }

    /// 服务器查询本端连接信息时，用已知的协议层延迟作答。丢包和流量
    /// 计数不在本端测量范围内，留空比伪造更诚实。
    fn answer_connection_info_request(&self) {
        let Some(client) = self.client.clone() else {
            return;
        };
        let Some(monitor) = self.network_monitor.as_ref() else {
            return;
        };
        let Some(ping) = monitor.connection_ping() else {
            return;
        };
        let jitter = monitor.connection_jitter();
        tokio::task::spawn_local(async move {
            let mut command = format!("setconnectioninfo connection_ping={ping:.4}");
            if let Some(jitter) = jitter {
                command.push_str(&format!(" connection_ping_deviation={jitter:.4}"));
            }
            let _ = client.send_command_no_wait(&command).await;
        });
    }

    fn invalidate_handlers(&mut self) {
        self.cancel_active_image();
        for request in self.pending_images.drain(..) {
            let _ = request.reply.send(Err(SessionError::NotConnected));
        }
        self.audio_since = Instant::now();
        self.voice.set_meter_epoch(None);
        self.levels.set_epoch(None);
        self.channel_tools = Default::default();
        self.transfer_target = None;
        self.connection_epoch = self.connection_epoch.wrapping_add(1);
        self.epoch.store(self.connection_epoch, Ordering::SeqCst);
        let _ = self.disconnect_tx.send(self.connection_epoch);
    }

    fn set_state(&mut self, state: SessionState) {
        let scope =
            matches!(&state, SessionState::Connected { .. }).then_some(self.connection_epoch);
        self.voice.set_meter_epoch(scope);
        self.levels.set_epoch(scope);
        self.state = state.clone();
        self.emit(SessionEvent::State {
            state,
            connection_epoch: self.connection_epoch,
        });
    }

    fn emit_voice_state(&self) {
        self.emit(SessionEvent::Voice(self.voice_state.clone()));
    }

    fn emit(&self, event: SessionEvent) {
        emit(&self.events, event);
    }

    fn emit_all(&self, events: Vec<SessionEvent>) {
        for event in events {
            self.emit(event);
        }
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

fn channel_view(channel: ChannelInfo, metadata: Option<&ChannelMetadata>) -> ChannelView {
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
    crate::channel_tools::protocol_error(err)
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

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

fn avatar_file_name(uid: &str) -> Result<String, SessionError> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(uid)
        .map_err(|error| SessionError::Transfer(format!("invalid avatar UID: {error}")))?;
    if bytes.len() != 20 {
        return Err(SessionError::Transfer(
            "avatar UID must contain 20 bytes".into(),
        ));
    }
    // TeamSpeak 头像文件把 UID 的每个半字节映射到 a..p。
    let suffix: String = bytes
        .into_iter()
        .flat_map(|byte| {
            [
                char::from(b'a' + (byte >> 4)),
                char::from(b'a' + (byte & 15)),
            ]
        })
        .collect();
    Ok(format!("/avatar_{suffix}"))
}

/// 官方客户端的标志语义：deafen 同时置 input 与 output，解除 deafen 后
/// input 恢复用户自己的静音选择。
fn mute_flags(muted: bool, deafened: bool) -> (&'static str, &'static str) {
    (
        if muted || deafened { "1" } else { "0" },
        if deafened { "1" } else { "0" },
    )
}

/// clientlist 与欢迎目录快照按 id 合并：clientlist 的标志更新，目录的
/// 频道更准（clientlist 在部分 TS6 服务器上缺 `cid`）。两边都有的成员
/// 用 clientlist 行、频道取目录；只在目录里的成员原样保留。
fn merged_clients(listed: Vec<ClientInfo>, directory: Vec<ClientInfo>) -> Vec<ClientView> {
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
pub(crate) fn unescape_text(raw: &str) -> String {
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

fn emit(events: &broadcast::Sender<SessionEvent>, event: SessionEvent) {
    // 没有订阅者时事件直接丢弃，actor 不因此停下。
    let _ = events.send(event);
}

/// 日志里只保留前 `max_chars` 个字符，避免整段 JSON 刷屏。
fn truncate_log(raw: &str, max_chars: usize) -> String {
    let mut chars = raw.chars();
    let head: String = chars.by_ref().take(max_chars).collect();
    if chars.next().is_some() {
        format!("{head}…")
    } else {
        head
    }
}

fn client_channel(
    client: Option<&Arc<Client>>,
    last_snapshot: Option<&(Vec<ChannelView>, Vec<ClientView>)>,
    clid: i32,
) -> Option<u64> {
    client
        .and_then(|client| client.directory_snapshot())
        .and_then(|snapshot| {
            snapshot
                .clients
                .iter()
                .find(|row| row.id == clid && row.channel_id != 0)
                .map(|row| row.channel_id)
        })
        .or_else(|| {
            last_snapshot.and_then(|(_, clients)| {
                clients
                    .iter()
                    .find(|row| row.id == clid && row.channel_id != 0)
                    .map(|row| row.channel_id)
            })
        })
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
            let _ = channel.send(SessionSignal::Snapshot {
                epoch,
                clients: snapshot.clients.into_iter().map(ClientView::from).collect(),
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
                } else if name == "notifyconnectioninforequest" {
                    let _ = channel.send(SessionSignal::ConnectionInfoRequested { epoch });
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
        }
    }
}

struct EventLogger {
    events: broadcast::Sender<SessionEvent>,
}

impl EventLogger {
    fn log(&self, level: &str, message: &str) {
        match level {
            "error" => tracing::error!(target: "tsclient", message = message),
            "warn" => tracing::warn!(target: "tsclient", message = message),
            "debug" => tracing::debug!(target: "tsclient", message = message),
            _ => tracing::info!(target: "tsclient", message = message),
        }
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
    events: broadcast::Sender<SessionEvent>,
}

impl ProgressReader {
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
            this.transferred += read as u64;
            this.maybe_emit();
        }
        poll
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct SlowImage(Arc<tokio::sync::Notify>);

    impl tsclient_rs::CommandMiddleware for SlowImage {
        fn wrap(&self, _: TestCommandHandler) -> TestCommandHandler {
            let started = Arc::clone(&self.0);
            Arc::new(move |command| {
                let started = Arc::clone(&started);
                Box::pin(async move {
                    if command.starts_with("ftinitdownload ") {
                        started.notify_one();
                        tokio::time::sleep(Duration::from_millis(300)).await;
                    }
                    Err(tsclient_rs::Error::ServerError {
                        id: "2568".into(),
                        server_message: "denied".into(),
                        extra_message: None,
                    })
                })
            })
        }
    }

    #[tokio::test]
    async fn avatar_negotiation_keeps_audio_and_controls_responsive() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let started = Arc::new(tokio::sync::Notify::new());
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(SlowImage(Arc::clone(&started)))],
                        ..Default::default()
                    },
                );
                client.mark_connected();
                let mut actor = audio_actor();
                actor.client = Some(Arc::new(client));
                actor.transfer_target = Some(ServerTarget {
                    host: "127.0.0.1".into(),
                    port: 9987,
                });
                let (audio, audio_rx) = mpsc::channel(16);
                actor.audio_events = audio_rx;
                let mut events = actor.events.subscribe();
                let (commands, rx) = mpsc::unbounded_channel();
                let task = tokio::task::spawn_local(async move {
                    actor.run(rx).await;
                });
                let (reply, result) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: base64::engine::general_purpose::STANDARD.encode([0u8; 20]),
                        reply,
                    })
                    .unwrap();
                started.notified().await;
                audio
                    .send(AudioEvent::SelfSpeaking { speaking: true })
                    .await
                    .unwrap();
                assert!(matches!(
                    tokio::time::timeout(Duration::from_millis(100), events.recv())
                        .await
                        .unwrap()
                        .unwrap(),
                    SessionEvent::SelfSpeaking { speaking: true }
                ));
                let (reply, control) = oneshot::channel();
                commands
                    .send(SessionCommand::SetPttMode {
                        enabled: true,
                        reply,
                    })
                    .unwrap();
                tokio::time::timeout(Duration::from_millis(100), control)
                    .await
                    .unwrap()
                    .unwrap()
                    .unwrap();
                // 控制命令优先抢占，正在进行的图片协商立即被打断
                assert!(matches!(
                    result.await.unwrap(),
                    Err(SessionError::Transfer(msg)) if msg.contains("interrupted")
                ));
                let (reply, muted) = oneshot::channel();
                commands
                    .send(SessionCommand::SetMuted { muted: true, reply })
                    .unwrap();
                tokio::time::timeout(Duration::from_secs(1), muted)
                    .await
                    .unwrap()
                    .unwrap()
                    .unwrap();
                let (reply, result) = oneshot::channel();
                commands
                    .send(SessionCommand::FetchAvatar {
                        uid: base64::engine::general_purpose::STANDARD.encode([1u8; 20]),
                        reply,
                    })
                    .unwrap();
                started.notified().await;
                commands.send(SessionCommand::Shutdown).unwrap();
                assert!(matches!(
                    tokio::time::timeout(Duration::from_millis(100), result)
                        .await
                        .unwrap()
                        .unwrap(),
                    Err(SessionError::NotConnected)
                ));
                task.await.unwrap();
            })
            .await;
    }

    #[tokio::test]
    async fn active_download_is_cancelled_promptly_on_disconnect() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let mut actor = audio_actor();
                let (reply, rx) = oneshot::channel();
                let info = FileDownloadInfo {
                    client_file_transfer_id: 1,
                    server_file_transfer_id: 1,
                    file_transfer_key: "key".into(),
                    port: 30033,
                    size: 100,
                };
                actor.finish_server_image(Ok(("127.0.0.1".into(), info)), reply);
                // 立即失效
                actor.invalidate_handlers();
                let outcome = tokio::time::timeout(Duration::from_millis(200), rx)
                    .await
                    .expect("should not hang for 20 seconds")
                    .expect("channel not dropped");
                assert!(matches!(outcome, Err(SessionError::NotConnected)));
            })
            .await;
    }

    #[tokio::test]
    async fn image_queue_is_bounded_and_invalidated_with_the_connection() {
        let mut actor = audio_actor();
        let client = Client::new(
            tsclient_rs::generateIdentity(0),
            "127.0.0.1:9987".into(),
            "test".into(),
            Default::default(),
        );
        actor.client = Some(Arc::new(client));
        actor.transfer_target = Some(ServerTarget {
            host: "127.0.0.1".into(),
            port: 9987,
        });
        let mut replies = Vec::new();
        for _ in 0..32 {
            let (reply, result) = oneshot::channel();
            actor.fetch_server_image("/avatar_test", reply);
            replies.push(result);
        }
        let (reply, result) = oneshot::channel();
        actor.fetch_server_image("/avatar_test", reply);
        assert!(matches!(
            result.await.unwrap(),
            Err(SessionError::Transfer(_))
        ));
        actor.invalidate_handlers();
        assert!(actor.pending_images.is_empty());
        for result in replies {
            assert!(matches!(
                result.await.unwrap(),
                Err(SessionError::NotConnected)
            ));
        }
    }

    struct RefusedDirectory {
        calls: Arc<std::sync::Mutex<Vec<String>>>,
    }

    type TestCommandHandler = Arc<
        dyn Fn(
                String,
            )
                -> Pin<Box<dyn std::future::Future<Output = Result<(), tsclient_rs::Error>> + Send>>
            + Send
            + Sync,
    >;

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

    #[test]
    fn avatar_paths_encode_uid_bytes_without_allowing_arbitrary_paths() {
        let uid = base64::engine::general_purpose::STANDARD.encode((0_u8..20).collect::<Vec<_>>());
        assert_eq!(
            avatar_file_name(&uid).unwrap(),
            "/avatar_aaabacadaeafagahaiajakalamanaoapbabbbcbd"
        );
        for invalid in ["", "../avatar", "https://example.com/a.png", "YQ=="] {
            assert!(avatar_file_name(invalid).is_err());
        }
    }

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

    fn audio_actor() -> Actor {
        let (events, _) = broadcast::channel(16);
        let (commands, _) = mpsc::unbounded_channel();
        let (_, audio) = mpsc::channel(16);
        let voice = VoiceEngine::spawn(|_| {}, |_| {}).unwrap();
        let (levels, _) = crate::events::level_channel();
        let mut actor = Actor::new(
            PathBuf::new(),
            ServerRegistry::new(),
            events,
            commands,
            SessionAudio {
                voice,
                events: audio,
                levels,
                enabled: false,
            },
        );
        actor.state = SessionState::Connected {
            client_id: 1,
            channel_id: 5,
        };
        actor.self_channel_id = 5;
        actor.capture_active = true;
        actor
    }

    #[test]
    fn queued_voice_requires_fresh_data_and_an_open_gate() {
        let mut actor = audio_actor();
        let at = actor.audio_since;
        let now = at + Duration::from_millis(20);
        assert!(actor.can_send_voice(VOICE_CODEC, at, now));
        assert!(!actor.can_send_voice(
            VOICE_CODEC,
            at,
            at + MAX_VOICE_QUEUE_DELAY + Duration::from_millis(1)
        ));
        actor.audio_since = at + Duration::from_millis(1);
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
        actor.audio_since = at;
        actor.voice_state.muted = true;
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
        actor.voice_state.muted = false;
        actor.voice_state.ptt_mode = true;
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
        actor.voice_state.ptt_active = true;
        assert!(actor.can_send_voice(VOICE_CODEC, at, now));
        actor.voice_state.deafened = true;
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
        actor.voice_state.deafened = false;
        actor.capture_active = false;
        assert!(!actor.can_send_voice(VOICE_CODEC, at, now));
    }

    #[test]
    fn outbound_voice_guard_uses_the_encoder_budget() {
        let mut actor = audio_actor();
        let mut events = actor.events.subscribe();
        actor.handle_audio(AudioEvent::Outbound {
            codec: VOICE_CODEC,
            data: vec![0; MAX_PACKET_BYTES],
            produced_at: Instant::now(),
        });
        assert!(events.try_recv().is_err());
        assert!(actor.voice_state.message.is_none());

        actor.handle_audio(AudioEvent::Outbound {
            codec: VOICE_CODEC,
            data: vec![0; MAX_PACKET_BYTES + 1],
            produced_at: Instant::now(),
        });
        // 防御性拦截超限包：断言未发出且未污染 UI message 状态
        assert!(events.try_recv().is_err());
        assert!(actor.voice_state.message.is_none());
    }

    #[tokio::test]
    async fn mute_cycle_discards_already_queued_voice_and_readiness_preserves_ptt_intent() {
        let mut actor = audio_actor();
        let queued = Instant::now();
        actor.set_muted(true).await.unwrap();
        actor.set_muted(false).await.unwrap();
        assert!(!actor.can_send_voice(VOICE_CODEC, queued, Instant::now()));
        actor.voice_state.ptt_mode = true;
        actor.voice_state.ptt_active = false;
        actor.handle_audio(AudioEvent::CaptureState { ready: true });
        assert!(actor.voice_state.input_ready);
        assert!(actor.voice_state.ptt_mode);
        assert!(!actor.voice_state.ptt_active);
        let mut events = actor.events.subscribe();
        actor.handle_audio(AudioEvent::SelfSpeaking { speaking: true });
        assert!(matches!(
            events.try_recv(),
            Ok(SessionEvent::SelfSpeaking { speaking: false })
        ));
    }

    #[test]
    fn mute_flags_follow_official_deafen_semantics() {
        assert_eq!(mute_flags(false, false), ("0", "0"));
        assert_eq!(mute_flags(true, false), ("1", "0"));
        // deafen 同时置两个标志，覆盖用户当前的静音选择。
        assert_eq!(mute_flags(false, true), ("1", "1"));
        assert_eq!(mute_flags(true, true), ("1", "1"));
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

    fn client_info(id: i32, channel_id: u64, nickname: &str) -> ClientInfo {
        ClientInfo {
            id,
            nickname: nickname.to_string(),
            uid: String::new(),
            channel_id,
            r#type: 0,
            server_groups: Vec::new(),
            away: None,
            away_message: None,
            input_muted: None,
            output_muted: None,
            channel_commander: None,
        }
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
    async fn upload_reader_preserves_exact_payload() {
        use tokio::io::AsyncReadExt;

        let dir = std::env::temp_dir().join("flspeak-transfer-payload-test");
        let path = dir.join("payload.bin");
        let _ = tokio::fs::remove_dir_all(&dir).await;
        tokio::fs::create_dir_all(&dir).await.unwrap();
        tokio::fs::write(&path, b"hello").await.unwrap();

        let file = tokio::fs::File::open(&path).await.unwrap();
        let (events, _) = broadcast::channel(8);
        let mut reader = ProgressReader::new(file, 1, 5, events);
        let mut output = Vec::new();
        reader.read_to_end(&mut output).await.unwrap();

        assert_eq!(output, b"hello");

        let _ = tokio::fs::remove_dir_all(&dir).await;
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
