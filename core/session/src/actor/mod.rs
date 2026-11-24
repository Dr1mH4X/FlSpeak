//! 命令循环：所有协议操作在这里串行执行。

mod connect;
mod directory;
mod messaging;
mod open_protocol;
mod snapshot;
mod streams;
mod telemetry;
#[cfg(test)]
pub(super) mod test_support;
#[cfg(test)]
mod tests_integration;
mod transfers;
mod voice;

use std::cell::RefCell;
use std::collections::{HashMap, HashSet, VecDeque};
use std::path::PathBuf;
use std::pin::Pin;
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::task::{Context, Poll};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use audio::engine::{AudioEvent, AudioStage, VoiceEngine};
use audio::format::{MAX_PACKET_BYTES, VOICE_CODEC, is_supported_codec};
use audio::playback::VoiceFrame;
#[cfg(test)]
use base64::Engine;
use proto::ConnectError;
use server::{ServerError, ServerProfile, ServerRegistry, ServerTarget};
use tokio::io::{AsyncRead, ReadBuf};
use tokio::sync::{broadcast, mpsc, oneshot, watch};
use tsclient_rs::open_protocol::{OpenProtocolEngine, SendOutcome, SendReceipt, TimerToken};
use tsclient_rs::{
    AbortSignal, ChannelInfo, Client, ClientInfo, Event as ProtocolEvent, FileDownloadInfo, Logger,
    PluginCommandEvent,
};

use crate::store::{self, identity_path};
use crate::streams::{StreamEndReason, StreamView};
use crate::{
    AudioDeviceView, AudioDevicesView, AudioSettings, BotCommandView, ChannelView, ClientType,
    ClientView, SessionCommand, SessionError, SessionEvent, SessionState, SettingsManager,
    TextMessageView, TransferDirection, VoiceStateView,
};
use streams::ActiveStreamSession;

use connect::*;
use open_protocol::*;
use transfers::*;
use voice::*;

/// 音频线程到 actor 的事件队列，溢出时丢的是语音包而不是协议命令。
pub(crate) const AUDIO_EVENT_CAPACITY: usize = 64;

#[derive(Debug, Clone)]
pub(super) struct ConnectTarget {
    id: String,
    nickname: String,
}

#[derive(Debug)]
pub(crate) struct StreamJoinResponse {
    pub(super) epoch: u64,
    pub(super) stream_epoch: u64,
    pub(super) stream_id: String,
    pub(super) viewer_clid: i32,
    pub(super) request_token: u64,
    pub(super) accept: bool,
    pub(super) outcome: Result<Option<streams::ViewerPeerHandle>, tsclient_rs::stream::StreamError>,
    pub(super) reply: oneshot::Sender<Result<(), SessionError>>,
}

#[derive(Debug)]
pub(crate) enum SessionSignal {
    TextMessage {
        epoch: u64,
        message: TextMessageView,
    },
    ClientJoined {
        epoch: u64,
        client: ClientView,
        avatar_hash: Option<String>,
    },
    ClientMoved {
        epoch: u64,
        id: i32,
        channel_id: u64,
    },
    /// 目录快照（0.2.1 起目录一变就发）：携带完整频道与成员快照。
    Snapshot {
        epoch: u64,
        snapshot: tsclient_rs::DirectorySnapshot,
    },
    /// 成员状态或服务器组变更：统一经 Actor 处理自端标志合并与权限组同步。
    ClientUpdated {
        epoch: u64,
        id: i32,
        uid: String,
        channel_id: u64,
        input_muted: Option<bool>,
        output_muted: Option<bool>,
        away: Option<bool>,
        away_message: Option<String>,
        server_groups: Vec<String>,
        avatar_hash: Option<String>,
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
    PluginCommand {
        epoch: u64,
        event: PluginCommandEvent,
    },
    /// `tsclient_rs::stream::Streams` 总线事件（流启动、更新、结束、观众变更、告警或错误）。
    StreamsBusEvent {
        epoch: u64,
        event: tsclient_rs::stream::StreamsEvent,
    },
    /// `Streams::watch` 异步等待推流端应答完成。
    WatchResolved {
        epoch: u64,
        stream_epoch: u64,
        watch_id: u64,
        stream_id: String,
        outcome: Result<tsclient_rs::stream::StreamView, tsclient_rs::stream::StreamError>,
    },
    /// 观看端对端句柄（`tsclient_rs::stream::StreamView`）收到的信令或关闭事件。
    ViewerPeerEvent {
        epoch: u64,
        stream_epoch: u64,
        watch_id: u64,
        stream_id: String,
        event: tsclient_rs::stream::PeerEvent,
    },
    /// 本地发布流收到的观看请求或结束事件。
    PublishedStreamEvent {
        epoch: u64,
        stream_epoch: u64,
        stream_id: String,
        event: tsclient_rs::stream::PublishedStreamEvent,
    },
    /// 远端观众撤回等待中的加入请求，或发布流因结束而关闭请求。
    JoinRequestClosed {
        epoch: u64,
        stream_epoch: u64,
        stream_id: String,
        viewer_clid: i32,
        token: u64,
        cause: tsclient_rs::stream::JoinRequestCloseCause,
    },
    /// 本地推流单个已接受观众的信令或关闭事件。
    PublisherPeerEvent {
        epoch: u64,
        stream_epoch: u64,
        stream_id: String,
        viewer_clid: i32,
        token: u64,
        event: tsclient_rs::stream::PeerEvent,
    },
    /// `Streams::publish` 异步开启推流完成。
    StartScreenShareResolved {
        epoch: u64,
        stream_epoch: u64,
        publish_token: u64,
        outcome: Result<tsclient_rs::stream::PublishedStream, tsclient_rs::stream::StreamError>,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    /// `JoinRequest::accept` / `deny` 异步响应完成。
    StreamJoinResponseResolved(StreamJoinResponse),
    /// 屏幕共享控制/信令异步网络等待完成回投。
    StreamCommandFinished {
        epoch: u64,
        stream_epoch: u64,
        require_matching_epoch: bool,
        outcome: Result<(), tsclient_rs::stream::StreamError>,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    /// `notifyconnectioninfo`：服务器返回自身连接的权威统计。
    ConnectionInfo {
        epoch: u64,
        items: Vec<HashMap<String, String>>,
    },
    /// `initserver` / `notifyserveredited` / `notifyserverupdated` 带来的服务器图标变化。
    ServerInfoUpdated {
        epoch: u64,
        icon_id: Option<u32>,
    },
    /// 当前连接的服务器自定义图标下载完成。
    ServerIconFetched {
        epoch: u64,
        server_id: String,
        icon_id: u32,
        result: Result<Vec<u8>, SessionError>,
    },
    /// 当前连接的频道图标下载完成。
    ChannelIconFetched {
        epoch: u64,
        server_id: String,
        icon_id: u32,
        attempt: u8,
        result: Result<Vec<u8>, ImageFetchError>,
    },
    /// 频道图标瞬态失败退避到期，准备重新入队尝试。
    RetryChannelIcon {
        epoch: u64,
        server_id: String,
        icon_id: u32,
        attempt: u8,
    },
    /// 头像磁盘缓存异步读取完成。
    AvatarDiskLoaded(AvatarDiskLoad),
    /// 当前连接的头像远程拉取完成。
    AvatarFetched(AvatarFetchOutcome),
    /// 头像瞬态失败退避到期，准备重新入队尝试。
    RetryAvatarFetch(AvatarRetry),
    /// 开放协议延迟定时器触发（去抖尾随广播或失败单次重试）。
    OpenProtocolTimer {
        epoch: u64,
        token: TimerToken,
    },
    /// 开放协议非阻塞发送结果回传，用于确认成功、防洪熔断或回滚限流状态。
    OpenProtocolSendResult {
        epoch: u64,
        plugin: &'static str,
        target_id: Option<i32>,
        receipt: SendReceipt,
        outcome: SendOutcome,
        error: Option<String>,
    },
    /// 节流/退避延迟后的自身语音状态上报。
    ReportVoiceFlags {
        epoch: u64,
        seq: u64,
    },
    /// 来自音频线程的非上行控制事件（状态/说话人/错误）。
    AudioControl(AudioEvent),
}

pub(crate) struct SessionAudio {
    pub voice: VoiceEngine,
    pub events: mpsc::Receiver<AudioEvent>,
    pub levels: crate::events::LevelPublisher,
    pub enabled: bool,
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
    self_uid: Option<String>,
    self_channel_id: u64,
    active_server_id: Option<String>,
    transfer_target: Option<ServerTarget>,
    dns_resolver: proto::HickoryDnsResolver,
    last_target: Option<ConnectTarget>,
    generation: u64,
    reconnect_attempt: u32,
    auto_reconnect: bool,
    voice_state: VoiceStateView,
    input_device: Option<String>,
    output_device: Option<String>,
    capture_active: bool,
    mic_permitted: bool,
    audio_since: Instant,
    audio_enabled: bool,
    voice_tx_gate: Rc<RefCell<VoiceTxGate>>,
    last_snapshot: Option<(Vec<ChannelView>, Vec<ClientView>)>,
    known_clients: HashMap<i32, ClientView>,
    channel_codecs: HashMap<u64, i32>,
    channel_list_allowed: Option<bool>,
    channel_meta_allowed: Option<bool>,
    client_list_allowed: Option<bool>,
    subscribed_all_channels: bool,
    self_server_groups: Vec<String>,
    channel_tools: crate::channel_tools::ChannelTools,
    current_codec: i32,
    ever_connected: bool,
    consecutive_timeouts: u32,
    identity_upgrade: Option<Arc<AbortSignal>>,
    identity_upgrading: bool,
    next_transfer_id: u64,
    connection_epoch: u64,
    epoch: Arc<AtomicU64>,
    stream_session: Option<ActiveStreamSession>,
    stream_epoch: u64,
    client_channels: HashMap<i32, u64>,
    last_streams_state: (Vec<StreamView>, Option<String>),
    next_watch_id: u64,
    next_stream_token: u64,
    network_monitor: Option<crate::network::NetworkMonitor>,
    last_network_sample_error: Option<Instant>,
    open_protocol: OpenProtocolEngine,
    open_protocol_flood_halted: bool,
    #[cfg(test)]
    open_protocol_outbound_log: Vec<(&'static str, Option<i32>, String)>,
    voice_report: VoiceReportState,
    pending_images: VecDeque<PendingImage>,
    active_image: Option<ActiveImage>,
    icons: crate::media::IconCache,
    active_server_icon_id: Option<u32>,
    fetching_server_icon: Option<(u64, String, u32)>,
    in_flight_channel_icons: HashMap<ChannelIconKey, ChannelIconWaiters>,
    avatar_hashes: HashMap<String, Option<String>>,
    avatar_negative_cache: HashSet<String>,
    avatar_cooldowns: HashMap<String, AvatarCooldown>,
    avatar_revisions: HashMap<String, u64>,
    avatars_fetched_without_hash: HashSet<String>,
    in_flight_avatars: HashMap<AvatarFetchKey, AvatarWaiters>,
    avatar_disk: crate::media::AvatarDiskQueue,
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
        let active_server_ids: Vec<&str> = registry
            .profiles()
            .iter()
            .map(|profile| profile.id.as_str())
            .collect();
        let icons = crate::media::IconCache::load(&store_path, &active_server_ids);
        let avatar_disk = crate::media::AvatarDiskQueue::new();
        avatar_disk.prune_orphans(
            store_path.clone(),
            active_server_ids
                .iter()
                .map(|id| (*id).to_owned())
                .collect(),
        );
        let initial_audio = if store_path.as_os_str().is_empty() {
            AudioSettings::default()
        } else {
            SettingsManager::with(|s| s.audio.clone()).unwrap_or_default()
        };
        let initial_input_device = normalize_device_id(initial_audio.input_device_id.clone());
        let initial_output_device = normalize_device_id(initial_audio.output_device_id.clone());
        let _ = voice.set_vad_config(
            initial_audio.vad_threshold,
            initial_audio.vad_hangover_frames,
        );
        let _ = voice.set_noise_suppression(initial_audio.noise_suppression);
        let audio_sync_tx = commands.clone();
        SettingsManager::subscribe_audio(move |audio| {
            audio_sync_tx
                .send(SessionCommand::SyncAudioSettings(audio.clone()))
                .is_ok()
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
            self_uid: None,
            self_channel_id: 0,
            active_server_id: None,
            transfer_target: None,
            dns_resolver: proto::HickoryDnsResolver::new(),
            last_target: None,
            generation: 0,
            reconnect_attempt: 0,
            auto_reconnect: true,
            voice_state: VoiceStateView::default(),
            input_device: initial_input_device,
            output_device: initial_output_device,
            capture_active: false,
            mic_permitted: true,
            audio_since: Instant::now(),
            audio_enabled,
            voice_tx_gate: Rc::new(RefCell::new(VoiceTxGate::default())),
            last_snapshot: None,
            known_clients: HashMap::new(),
            channel_codecs: HashMap::new(),
            channel_list_allowed: None,
            channel_meta_allowed: None,
            client_list_allowed: None,
            subscribed_all_channels: false,
            self_server_groups: Vec::new(),
            channel_tools: Default::default(),
            current_codec: VOICE_CODEC,
            ever_connected: false,
            consecutive_timeouts: 0,
            identity_upgrade: None,
            identity_upgrading: false,
            next_transfer_id: 1,
            connection_epoch: 0,
            epoch: Arc::new(AtomicU64::new(0)),
            stream_session: None,
            stream_epoch: 0,
            client_channels: HashMap::new(),
            last_streams_state: (Vec::new(), None),
            next_watch_id: 0,
            next_stream_token: 0,
            network_monitor: None,
            last_network_sample_error: None,
            open_protocol: new_open_protocol_engine(),
            open_protocol_flood_halted: false,
            #[cfg(test)]
            open_protocol_outbound_log: Vec::new(),
            voice_report: VoiceReportState::default(),
            pending_images: VecDeque::new(),
            active_image: None,
            icons,
            active_server_icon_id: None,
            fetching_server_icon: None,
            in_flight_channel_icons: HashMap::new(),
            avatar_hashes: HashMap::new(),
            avatar_negative_cache: HashSet::new(),
            avatar_cooldowns: HashMap::new(),
            avatar_revisions: HashMap::new(),
            avatars_fetched_without_hash: HashSet::new(),
            in_flight_avatars: HashMap::new(),
            avatar_disk,
            disconnect_tx,
            disconnect_rx,
        }
    }

    pub(crate) async fn run(&mut self, mut commands: mpsc::UnboundedReceiver<SessionCommand>) {
        let mut snapshots = tokio::time::interval(crate::SNAPSHOT_INTERVAL);
        snapshots.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        // interval 的第一次 tick 立即就绪；消费掉，避免刚启动就发空快照。
        snapshots.tick().await;

        self.sync_voice_gate();
        if self.audio_enabled
            && (self.input_device.is_some() || self.output_device.is_some())
            && let (Ok(inputs), Ok(outputs)) = (
                audio::device::input_devices(),
                audio::device::output_devices(),
            )
        {
            let inputs: Vec<AudioDeviceView> =
                inputs.into_iter().map(AudioDeviceView::from).collect();
            let outputs: Vec<AudioDeviceView> =
                outputs.into_iter().map(AudioDeviceView::from).collect();
            self.reconcile_audio_devices(&inputs, &outputs);
        }
        let (_, dummy_rx) = mpsc::channel(1);
        let mut audio_rx = std::mem::replace(&mut self.audio_events, dummy_rx);
        let (stop_audio_tx, mut stop_audio_rx) = oneshot::channel::<()>();
        let audio_gate = Rc::clone(&self.voice_tx_gate);
        let audio_signals = self.signals.clone();
        // 在同一个单线程 LocalSet 上独立泵取 audio_events，避免慢速网络 .await 阻塞语音发送。
        let audio_pump = tokio::task::spawn_local(async move {
            loop {
                tokio::select! {
                    biased;
                    _ = &mut stop_audio_rx => break,
                    event = audio_rx.recv() => match event {
                        Some(AudioEvent::Outbound { codec, data, produced_at }) => {
                            audio_gate.borrow_mut().dispatch_outbound(
                                codec,
                                data,
                                produced_at,
                                Instant::now(),
                            );
                        }
                        Some(other) => {
                            let _ = audio_signals.send(SessionSignal::AudioControl(other));
                        }
                        None => break,
                    }
                }
            }
        });

        loop {
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
        let _ = stop_audio_tx.send(());
        let _ = audio_pump.await;
        self.teardown().await;
    }

    pub(super) async fn handle(&mut self, command: SessionCommand) -> bool {
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
            SessionCommand::ListServerIcons { reply } => {
                let _ = reply.send(self.icons.list_server_icons());
            }
            SessionCommand::LoadSelfAvatarSnapshot { reply } => {
                let (tx, rx) = oneshot::channel();
                self.avatar_disk
                    .load_self_snapshot(self.store_path.clone(), move |bytes| {
                        let _ = tx.send(bytes);
                    });
                tokio::task::spawn_local(async move {
                    match rx.await {
                        Ok(bytes) => {
                            let _ = reply.send(Ok(bytes));
                        }
                        Err(_) => {
                            let _ = reply.send(Err(SessionError::Closed));
                        }
                    }
                });
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
                    if self.self_client_id == Some(client_id) && self.self_channel_id != channel_id
                    {
                        self.reset_directory_permissions();
                    }
                    let _ = self.refresh_snapshot(true).await;
                    if self.self_client_id == Some(client_id) && channel_id != 0 {
                        self.open_protocol_self_moved(channel_id);
                    }
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
                self.reset_directory_permissions();
                let _ = reply.send(self.refresh_snapshot(true).await);
            }
            SessionCommand::SampleNetwork { reply } => {
                let _ = reply.send(self.sample_network().await);
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
                let res = self.apply_muted(muted);
                let ok = res.is_ok();
                let _ = reply.send(res);
                if ok {
                    self.request_state_update().await;
                }
            }
            SessionCommand::SetDeafened { deafened, reply } => {
                let res = self.apply_deafened(deafened);
                let ok = res.is_ok();
                let _ = reply.send(res);
                if ok {
                    self.request_state_update().await;
                }
            }
            SessionCommand::SetAway { away, reply } => {
                self.apply_away(away);
                let _ = reply.send(Ok(()));
                self.request_state_update().await;
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
                    let detail = error.unwrap_or_else(|| "identity upgrade failed".into());
                    crate::log_warn!(error = detail; "identity upgrade failed");
                    self.emit(SessionEvent::Failed {
                        message: crate::notices::SESSION_IDENTITY_UPGRADE_FAILED.into(),
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
                let _ = reply.send(self.list_audio_devices());
            }
            SessionCommand::SetAudioDevices {
                input,
                output,
                reply,
            } => {
                let _ = reply.send(self.set_audio_devices(input, output));
            }
            SessionCommand::SetMicPermitted { granted, reply } => {
                let _ = reply.send(self.set_mic_permitted(granted));
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
            SessionCommand::UploadAvatar { bytes, reply } => {
                let _ = reply.send(self.upload_avatar(bytes).await);
            }
            SessionCommand::DeleteAvatar { reply } => {
                let _ = reply.send(self.delete_avatar().await);
            }
            SessionCommand::FetchIcon { icon_id, reply } => {
                self.fetch_channel_icon(icon_id, reply);
            }
            SessionCommand::FetchAvatar { uid, reply } => {
                self.fetch_avatar(uid, reply);
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
            SessionCommand::JoinStream {
                stream_id,
                source_clid,
                reply,
            } => {
                let _ = reply.send(self.join_stream(stream_id, source_clid));
            }
            SessionCommand::LeaveStream { stream_id, reply } => {
                self.leave_stream(stream_id, reply);
            }
            SessionCommand::SendStreamAnswer {
                stream_id,
                target_clid,
                sdp,
                reply,
            } => {
                self.send_stream_answer(stream_id, target_clid, sdp, reply);
            }
            SessionCommand::SendStreamIceCandidate {
                stream_id,
                target_clid,
                sdp,
                mid,
                m_line,
                reply,
            } => {
                self.send_stream_ice_candidate(stream_id, target_clid, sdp, mid, m_line, reply);
            }
            SessionCommand::StartScreenShare {
                name,
                audio,
                bitrate,
                viewer_limit,
                reply,
            } => {
                self.start_screen_share(name, audio, bitrate, viewer_limit, reply);
            }
            SessionCommand::StopScreenShare { reply } => {
                self.stop_screen_share(reply);
            }
            SessionCommand::RespondStreamJoinRequest {
                viewer_clid,
                accept,
                offer_sdp,
                reply,
            } => {
                self.respond_stream_join_request(viewer_clid, accept, offer_sdp, reply);
            }
            SessionCommand::SendPublisherIceCandidate {
                viewer_clid,
                sdp,
                mid,
                m_line,
                reply,
            } => {
                self.send_publisher_ice_candidate(viewer_clid, sdp, mid, m_line, reply);
            }
            SessionCommand::KickStreamViewer { viewer_clid, reply } => {
                self.kick_stream_viewer(viewer_clid, reply);
            }
            SessionCommand::QueryPeerIdentity { target_clid, reply } => {
                let _ = reply.send(self.query_peer_identity(target_clid));
            }
            SessionCommand::FetchBotCommands {
                target_clid,
                target_uid,
                reply,
            } => {
                let _ = reply.send(self.fetch_bot_commands(target_clid, &target_uid));
            }
            SessionCommand::SyncAudioSettings(mut audio) => {
                if !self.store_path.as_os_str().is_empty()
                    && let Ok((input, output)) = SettingsManager::with(|s| {
                        (
                            s.audio.input_device_id.clone(),
                            s.audio.output_device_id.clone(),
                        )
                    })
                {
                    audio.input_device_id = input;
                    audio.output_device_id = output;
                }
                self.apply_audio_settings(&audio);
            }
        }
        true
    }
}

impl Actor {
    pub(super) async fn handle_signal(&mut self, signal: SessionSignal) {
        match signal {
            SessionSignal::TextMessage { epoch, mut message } => {
                if epoch != self.connection_epoch {
                    return;
                }
                self.resolve_text_message_routing(&mut message);
                if let Some(server_id) = self.active_server_id.clone() {
                    let path = store::history_path(&self.store_path);
                    if let Err(message) = store::append_history(&path, &server_id, &message).await {
                        crate::log_warn!(error = message; "failed to write message history");
                        self.emit(SessionEvent::Failed {
                            message: crate::notices::SESSION_HISTORY_WRITE_FAILED.into(),
                        });
                    }
                }
                self.emit(SessionEvent::TextMessage(message));
            }
            SessionSignal::ClientJoined {
                epoch,
                mut client,
                avatar_hash,
            } => {
                if epoch != self.connection_epoch {
                    return;
                }
                if let Some(prev) = self.known_client_row(client.id) {
                    if client.nickname.is_empty() && !prev.nickname.is_empty() {
                        client.nickname = prev.nickname;
                    }
                    if client.uid.is_empty() && !prev.uid.is_empty() {
                        client.uid = prev.uid;
                    }
                    if client.channel_id == 0 && prev.channel_id != 0 {
                        client.channel_id = prev.channel_id;
                    }
                    client.input_muted = client.input_muted.or(prev.input_muted);
                    client.output_muted = client.output_muted.or(prev.output_muted);
                    client.away = client.away.or(prev.away);
                    if client.away != Some(false) {
                        client.away_message = client.away_message.or(prev.away_message);
                    }
                    client.is_streaming = client.is_streaming || prev.is_streaming;
                }
                self.sync_avatar_hash_from_join(&client.uid, avatar_hash);
                if Some(client.id) == self.self_client_id {
                    if client.channel_id == 0 && self.self_channel_id != 0 {
                        client.channel_id = self.self_channel_id;
                    }
                    if !client.uid.is_empty() {
                        self.self_uid = Some(client.uid.clone());
                    }
                    self.apply_self_voice_flags_to_row(&mut client);
                }
                let client_id = client.id;
                let client_channel_id = client.channel_id;
                self.open_protocol_peer_joined(client.id, &client.uid);
                self.enrich_client(&mut client);
                self.upsert_client_in_cache(client.clone());
                self.emit(SessionEvent::ClientJoined(client));
                self.record_client_channel(client_id, client_channel_id);
                self.sync_streams_view();
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
                } else {
                    self.on_stream_peer_moved(id, channel_id);
                }
                let moved_client = self.build_moved_client_view(id, channel_id);
                self.upsert_client_in_cache(moved_client.clone());
                self.emit(SessionEvent::ClientMoved(moved_client));
            }
            SessionSignal::ClientLeft { epoch, id } => {
                if epoch == self.connection_epoch {
                    self.remove_client_from_cache(id);
                    self.open_protocol_peer_left(id);
                    self.on_stream_peer_left(id);
                }
            }
            SessionSignal::PluginCommand { epoch, event } => {
                if epoch != self.connection_epoch {
                    return;
                }
                self.handle_open_protocol_command(event);
            }
            SessionSignal::StreamsBusEvent { epoch, event } => {
                if epoch == self.connection_epoch {
                    self.handle_streams_bus_event(event);
                }
            }
            SessionSignal::WatchResolved {
                epoch,
                stream_epoch,
                watch_id,
                stream_id,
                outcome,
            } => {
                if epoch == self.connection_epoch && stream_epoch == self.stream_epoch {
                    self.handle_watch_resolved(watch_id, stream_id, outcome);
                } else if let Ok(view) = outcome
                    && !view.closed()
                {
                    tokio::task::spawn_local(async move {
                        let _ = view.leave().await;
                    });
                }
            }
            SessionSignal::ViewerPeerEvent {
                epoch,
                stream_epoch,
                watch_id,
                stream_id,
                event,
            } => {
                if epoch == self.connection_epoch && stream_epoch == self.stream_epoch {
                    self.handle_viewer_peer_event(watch_id, stream_id, event);
                }
            }
            SessionSignal::PublishedStreamEvent {
                epoch,
                stream_epoch,
                stream_id,
                event,
            } => {
                if epoch == self.connection_epoch && stream_epoch == self.stream_epoch {
                    self.handle_published_stream_event(stream_id, event);
                }
            }
            SessionSignal::JoinRequestClosed {
                epoch,
                stream_epoch,
                stream_id,
                viewer_clid,
                token,
                cause,
            } => {
                if epoch == self.connection_epoch && stream_epoch == self.stream_epoch {
                    self.handle_join_request_closed(stream_id, viewer_clid, token, cause);
                }
            }
            SessionSignal::PublisherPeerEvent {
                epoch,
                stream_epoch,
                stream_id,
                viewer_clid,
                token,
                event,
            } => {
                if epoch == self.connection_epoch && stream_epoch == self.stream_epoch {
                    self.handle_publisher_peer_event(stream_id, viewer_clid, token, event);
                }
            }
            SessionSignal::StartScreenShareResolved {
                epoch,
                stream_epoch,
                publish_token,
                outcome,
                reply,
            } => {
                self.handle_start_screen_share_resolved(
                    epoch,
                    stream_epoch,
                    publish_token,
                    outcome,
                    reply,
                );
            }
            SessionSignal::StreamJoinResponseResolved(response) => {
                self.handle_stream_join_response_resolved(response);
            }
            SessionSignal::StreamCommandFinished {
                epoch,
                stream_epoch,
                require_matching_epoch,
                outcome,
                reply,
            } => {
                self.handle_stream_command_finished(
                    epoch,
                    stream_epoch,
                    require_matching_epoch,
                    outcome,
                    reply,
                );
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
                let round_trip = self.client.as_ref().and_then(|client| client.round_trip());
                let packet_loss = self.client.as_ref().and_then(|client| client.packet_loss());
                let Some(monitor) = &mut self.network_monitor else {
                    return;
                };
                monitor.apply_round_trip(round_trip);
                monitor.apply_packet_loss(packet_loss);
                monitor.apply_connection_info(params);
                let telemetry = monitor.snapshot(now_millis());
                self.emit(SessionEvent::Network(telemetry));
            }
            SessionSignal::Snapshot { epoch, snapshot } => {
                if epoch == self.connection_epoch {
                    self.handle_directory_snapshot(snapshot);
                }
            }
            SessionSignal::ClientUpdated {
                epoch,
                id,
                uid,
                channel_id,
                mut input_muted,
                mut output_muted,
                mut away,
                away_message,
                server_groups,
                avatar_hash,
            } => {
                if epoch != self.connection_epoch {
                    return;
                }
                let resolved_uid = if uid.is_empty() {
                    self.last_snapshot
                        .as_ref()
                        .and_then(|(_, clients)| {
                            clients.iter().find(|c| c.id == id).map(|c| c.uid.clone())
                        })
                        .unwrap_or_default()
                } else {
                    uid
                };
                self.sync_avatar_hash_from_update(&resolved_uid, avatar_hash);
                if Some(id) != self.self_client_id
                    && channel_id != 0
                    && self.client_channels.get(&id).copied() != Some(channel_id)
                {
                    self.on_stream_peer_moved(id, channel_id);
                }
                if self.self_client_id == Some(id) {
                    if !resolved_uid.is_empty() {
                        self.self_uid = Some(resolved_uid.clone());
                    }
                    self.sync_self_server_groups(&server_groups);
                    let local = VoiceFlagsSnapshot::from_voice_state(&self.voice_state);
                    let resolved = self.voice_report.resolve_self_flags(
                        local,
                        input_muted,
                        output_muted,
                        away,
                    );
                    input_muted = Some(resolved.input_muted);
                    output_muted = Some(resolved.output_muted);
                    if away.is_some() {
                        away = Some(resolved.away);
                        if (self.voice_report.dirty_mask & DIRTY_AWAY) == 0
                            && self.voice_state.away != resolved.away
                        {
                            self.voice_state.away = resolved.away;
                            self.emit_voice_state();
                        }
                    }
                }
                self.update_client_flags_in_cache(
                    id,
                    channel_id,
                    input_muted,
                    output_muted,
                    away,
                    away_message.as_ref(),
                );
                self.emit(SessionEvent::ClientUpdated {
                    id,
                    input_muted,
                    output_muted,
                    away,
                    away_message,
                });
            }
            SessionSignal::Disconnected { epoch, message } => {
                if epoch == self.connection_epoch {
                    self.on_connection_lost(crate::notices::SESSION_CONNECTION_LOST, message, true)
                        .await;
                }
            }
            SessionSignal::Kicked { epoch, message } => {
                if epoch == self.connection_epoch {
                    self.auto_reconnect = false;
                    self.on_connection_lost(crate::notices::SESSION_KICKED, message, false)
                        .await;
                }
            }
            SessionSignal::ServerInfoUpdated { epoch, icon_id } => {
                if epoch == self.connection_epoch
                    && let Some(server_id) = self.active_server_id.clone()
                {
                    self.sync_server_icon(server_id, icon_id);
                }
            }
            SessionSignal::ServerIconFetched {
                epoch,
                server_id,
                icon_id,
                result,
            } => {
                if epoch != self.connection_epoch
                    || self.active_server_id.as_deref() != Some(server_id.as_str())
                    || self.active_server_icon_id != Some(icon_id)
                {
                    return;
                }
                self.fetching_server_icon = None;
                match result {
                    Ok(bytes) => {
                        if let Err(error) = self.icons.save_server_icon(
                            &self.store_path,
                            &server_id,
                            icon_id,
                            bytes.clone(),
                        ) {
                            self.emit(SessionEvent::Log {
                                level: "warn".into(),
                                message: format!("failed to save the server icon cache: {error}"),
                            });
                        }
                        self.emit(SessionEvent::ServerIconUpdated {
                            server_id,
                            bytes: Some(bytes),
                        });
                    }
                    Err(error) => {
                        if !matches!(error, SessionError::NotConnected) {
                            self.emit(SessionEvent::Log {
                                level: "warn".into(),
                                message: format!("failed to fetch server icon {icon_id}: {error}"),
                            });
                        }
                    }
                }
            }
            SessionSignal::ChannelIconFetched {
                epoch,
                server_id,
                icon_id,
                attempt,
                result,
            } => {
                self.handle_channel_icon_fetched(epoch, server_id, icon_id, attempt, result);
            }
            SessionSignal::RetryChannelIcon {
                epoch,
                server_id,
                icon_id,
                attempt,
            } => {
                self.handle_retry_channel_icon(epoch, server_id, icon_id, attempt);
            }
            SessionSignal::AvatarDiskLoaded(load) => {
                self.handle_avatar_disk_loaded(load);
            }
            SessionSignal::AvatarFetched(outcome) => {
                self.handle_avatar_fetched(outcome);
            }
            SessionSignal::RetryAvatarFetch(retry) => {
                self.handle_retry_avatar_fetch(retry);
            }
            SessionSignal::OpenProtocolTimer { epoch, token } => {
                if epoch != self.connection_epoch {
                    return;
                }
                self.handle_open_protocol_timer(token);
            }
            SessionSignal::OpenProtocolSendResult {
                epoch,
                plugin,
                target_id,
                receipt,
                outcome,
                error,
            } => {
                if epoch != self.connection_epoch {
                    return;
                }
                self.handle_open_protocol_send_result(plugin, target_id, receipt, outcome, error);
            }
            SessionSignal::ReportVoiceFlags { epoch, seq } => {
                if epoch != self.connection_epoch {
                    return;
                }
                self.report_voice_flags_step(VoiceReportMode::Timer { seq })
                    .await;
            }
            SessionSignal::AudioControl(event) => {
                self.handle_audio(event);
            }
        }
    }
}

impl Actor {
    pub(super) fn connected(&self) -> Result<Arc<Client>, SessionError> {
        self.client.clone().ok_or(SessionError::NotConnected)
    }
    pub(super) fn set_state(&mut self, state: SessionState) {
        let scope =
            matches!(&state, SessionState::Connected { .. }).then_some(self.connection_epoch);
        self.voice.set_meter_epoch(scope);
        self.levels.set_epoch(scope);
        self.state = state.clone();
        self.sync_voice_gate();
        self.emit(SessionEvent::State {
            state,
            connection_epoch: self.connection_epoch,
        });
    }
    pub(super) fn emit_voice_state(&self) {
        self.sync_voice_gate();
        self.emit(SessionEvent::Voice(self.voice_state.clone()));
    }

    pub(super) fn emit(&self, event: SessionEvent) {
        emit(&self.events, event);
    }

    pub(super) fn sync_clients_cache(&mut self, clients: &[ClientView]) {
        self.known_clients = clients
            .iter()
            .map(|client| (client.id, client.clone()))
            .collect();
        if let Some(self_id) = self.self_client_id
            && let Some(me) = self.known_clients.get(&self_id)
            && !me.uid.is_empty()
        {
            self.self_uid = Some(me.uid.clone());
        }
    }

    fn known_client_row(&self, id: i32) -> Option<ClientView> {
        self.known_clients.get(&id).cloned().or_else(|| {
            self.last_snapshot
                .as_ref()
                .and_then(|(_, clients)| clients.iter().find(|client| client.id == id).cloned())
        })
    }

    fn upsert_client_in_cache(&mut self, client: ClientView) {
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

    fn remove_client_from_cache(&mut self, id: i32) {
        self.known_clients.remove(&id);
        if let Some((_, clients)) = &mut self.last_snapshot {
            clients.retain(|client| client.id != id);
        }
    }

    fn update_client_flags_in_cache(
        &mut self,
        id: i32,
        channel_id: u64,
        input_muted: Option<bool>,
        output_muted: Option<bool>,
        away: Option<bool>,
        away_message: Option<&String>,
    ) {
        let apply = |row: &mut ClientView| {
            if channel_id != 0 && (Some(id) != self.self_client_id || row.channel_id == 0) {
                row.channel_id = channel_id;
            }
            if let Some(value) = input_muted {
                row.input_muted = Some(value);
            }
            if let Some(value) = output_muted {
                row.output_muted = Some(value);
            }
            if let Some(value) = away {
                row.away = Some(value);
            }
            if let Some(value) = away_message {
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

    fn apply_self_voice_flags_to_row(&mut self, row: &mut ClientView) {
        let local = VoiceFlagsSnapshot::from_voice_state(&self.voice_state);
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

    fn build_moved_client_view(&mut self, id: i32, channel_id: u64) -> ClientView {
        let mut client = self
            .known_client_row(id)
            .or_else(|| {
                self.client
                    .as_ref()
                    .and_then(|client| client.directory_snapshot())
                    .and_then(|snapshot| {
                        snapshot
                            .clients
                            .into_iter()
                            .find(|existing| existing.id == id)
                            .map(ClientView::from)
                    })
            })
            .unwrap_or_else(|| ClientView {
                id,
                nickname: if Some(id) == self.self_client_id {
                    self.last_target
                        .as_ref()
                        .map(|target| target.nickname.clone())
                        .unwrap_or_default()
                } else {
                    String::new()
                },
                uid: if Some(id) == self.self_client_id {
                    self.self_uid.clone().unwrap_or_default()
                } else {
                    String::new()
                },
                channel_id,
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
        client.channel_id = channel_id;
        if Some(id) == self.self_client_id {
            self.apply_self_voice_flags_to_row(&mut client);
        }
        self.enrich_client(&mut client);
        client
    }
}
pub(super) fn protocol_error(err: tsclient_rs::Error) -> SessionError {
    crate::channel_tools::protocol_error(err)
}

pub(super) fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

pub(super) fn emit(events: &broadcast::Sender<SessionEvent>, event: SessionEvent) {
    if let SessionEvent::Log { level, message } = &event {
        match level.as_str() {
            "error" => tracing::error!(target: "session", "{message}"),
            "warn" => tracing::warn!(target: "session", "{message}"),
            "debug" => tracing::debug!(target: "session", "{message}"),
            "trace" => tracing::trace!(target: "session", "{message}"),
            _ => tracing::info!(target: "session", "{message}"),
        }
        if matches!(level.as_str(), "debug" | "trace") {
            return;
        }
    }
    // 没有订阅者时事件直接丢弃，actor 不因此停下。
    let _ = events.send(event);
}

pub(super) struct EventLogger {
    pub(super) events: broadcast::Sender<SessionEvent>,
}

impl EventLogger {
    fn log(&self, level: &str, message: &str) {
        match level {
            "error" => tracing::error!(target: "tsclient", message = message),
            "warn" => tracing::warn!(target: "tsclient", message = message),
            "debug" => tracing::debug!(target: "tsclient", message = message),
            "trace" => tracing::trace!(target: "tsclient", message = message),
            _ => tracing::info!(target: "tsclient", message = message),
        }
        if matches!(level, "debug" | "trace") {
            return;
        }
        let _ = self.events.send(SessionEvent::Log {
            level: level.to_string(),
            message: message.to_string(),
        });
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_and_trace_logs_do_not_cross_ffi_broadcast_channel() {
        let (events, mut rx) = broadcast::channel(16);
        let logger = EventLogger {
            events: events.clone(),
        };

        logger.log("debug", "suppressed tsclient debug");
        logger.log("trace", "suppressed tsclient trace");
        emit(
            &events,
            SessionEvent::Log {
                level: "debug".into(),
                message: "suppressed actor debug".into(),
            },
        );
        emit(
            &events,
            SessionEvent::Log {
                level: "trace".into(),
                message: "suppressed actor trace".into(),
            },
        );
        assert!(rx.try_recv().is_err());

        logger.log("info", "allowed tsclient info");
        emit(
            &events,
            SessionEvent::Log {
                level: "warn".into(),
                message: "allowed actor warn".into(),
            },
        );
        emit(
            &events,
            SessionEvent::Log {
                level: "error".into(),
                message: "allowed actor error".into(),
            },
        );

        let received: Vec<(String, String)> = std::iter::from_fn(|| rx.try_recv().ok())
            .filter_map(|ev| match ev {
                SessionEvent::Log { level, message } => Some((level, message)),
                _ => None,
            })
            .collect();
        assert_eq!(
            received,
            vec![
                ("info".into(), "allowed tsclient info".into()),
                ("warn".into(), "allowed actor warn".into()),
                ("error".into(), "allowed actor error".into()),
            ]
        );
    }
}
