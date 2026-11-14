//! 命令循环：所有协议操作在这里串行执行。

mod connect;
mod directory;
mod open_protocol;
mod streams;
#[cfg(test)]
pub(super) mod test_support;
#[cfg(test)]
mod tests_integration;
mod transfers;
mod voice;

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
    PluginCommandEvent, PluginCommandTarget,
};

use crate::store::{self, identity_path};
use crate::streams::{StreamCoordinator, StreamEndReason};
use crate::{
    AudioDeviceView, AudioDevicesView, BotCommandView, ChannelView, ClientType, ClientView,
    ServerIconView, SessionCommand, SessionError, SessionEvent, SessionState, SettingsManager,
    TextMessageView, TransferDirection, VoiceStateView,
};

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
pub(crate) enum SessionSignal {
    TextMessage {
        epoch: u64,
        message: TextMessageView,
    },
    ClientJoined {
        epoch: u64,
        client: ClientView,
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
        input_muted: Option<bool>,
        output_muted: Option<bool>,
        away: Option<bool>,
        away_message: Option<String>,
        server_groups: Vec<String>,
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
        result: Result<Vec<u8>, SessionError>,
    },
    /// 开放协议延迟进房广播（去抖尾随广播或失败单次重试）。
    AnnounceIdentity {
        epoch: u64,
        mode: AnnounceAttemptMode,
        allow_failure_retry: bool,
        expected_seq: Option<u64>,
    },
    /// 节流/退避延迟后的自身语音状态上报。
    ReportVoiceFlags {
        epoch: u64,
        seq: u64,
    },
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
    streams: StreamCoordinator,
    /// 当前连接的服务器是否认识 TS6 流命令；首次探测返回 command not found 后关闭。
    streams_supported: bool,
    network_monitor: Option<crate::network::NetworkMonitor>,
    last_network_sample_error: Option<Instant>,
    peer_identities: HashMap<String, CachedPeerIdentity>,
    peer_commands: HashMap<String, Vec<BotCommandView>>,
    commands_fetching: HashSet<String>,
    ack_limiter: AckRateLimiter,
    announce_state: AnnounceState,
    voice_report: VoiceReportState,
    pending_images: VecDeque<PendingImage>,
    active_image: Option<ActiveImage>,
    server_icons: HashMap<String, crate::server_icons::CachedServerIcon>,
    active_server_icon_id: Option<u32>,
    fetching_server_icon: Option<(u64, String, u32)>,
    in_flight_channel_icons: HashMap<ChannelIconKey, ChannelIconWaiters>,
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
        let server_icons = crate::server_icons::load(&store_path, &active_server_ids);
        crate::channel_icons::prune_orphans(&store_path, &active_server_ids);
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
            streams: StreamCoordinator::default(),
            streams_supported: true,
            network_monitor: None,
            last_network_sample_error: None,
            peer_identities: HashMap::new(),
            peer_commands: HashMap::new(),
            commands_fetching: HashSet::new(),
            ack_limiter: AckRateLimiter::new(Instant::now()),
            announce_state: AnnounceState::default(),
            voice_report: VoiceReportState::default(),
            pending_images: VecDeque::new(),
            active_image: None,
            server_icons,
            active_server_icon_id: None,
            fetching_server_icon: None,
            in_flight_channel_icons: HashMap::new(),
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
            SessionCommand::ListServerIcons { reply } => {
                let icons = self
                    .server_icons
                    .iter()
                    .map(|(server_id, entry)| ServerIconView {
                        server_id: server_id.clone(),
                        bytes: entry.bytes.clone(),
                    })
                    .collect();
                let _ = reply.send(icons);
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
                        self.maybe_announce_identity().await;
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
                self.fetch_channel_icon(icon_id, reply);
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
                            crate::streams::answer_payload(&sdp),
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
                        let payload = crate::streams::ice_payload(&sdp, mid.as_deref(), m_line);
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
            SessionCommand::QueryPeerIdentity { target_clid, reply } => {
                let _ = reply.send(self.query_peer_identity(target_clid).await);
            }
            SessionCommand::FetchBotCommands {
                target_clid,
                target_uid,
                reply,
            } => {
                let _ = reply.send(self.fetch_bot_commands(target_clid, &target_uid).await);
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
                message.peer_uid = self.direct_peer_uid(&message);
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
            SessionSignal::ClientJoined { epoch, mut client } => {
                if epoch != self.connection_epoch {
                    return;
                }
                self.enrich_client(&mut client);
                self.emit(SessionEvent::ClientJoined(client));
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
            SessionSignal::PluginCommand { epoch, event } => {
                if epoch != self.connection_epoch {
                    return;
                }
                if event.name == IDENTITY_PLUGIN {
                    self.handle_identity_event(event).await;
                } else if event.name == COMMANDS_PLUGIN {
                    self.handle_commands_event(event);
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
                mut input_muted,
                mut output_muted,
                mut away,
                away_message,
                server_groups,
            } => {
                if epoch != self.connection_epoch {
                    return;
                }
                if self.self_client_id == Some(id) {
                    self.sync_self_server_groups(&server_groups);
                    let local = VoiceFlagsSnapshot::from_voice_state(&self.voice_state);
                    let resolved = self.voice_report.resolve_self_flags(
                        local,
                        input_muted,
                        output_muted,
                        away,
                    );
                    if input_muted.is_some() {
                        input_muted = Some(resolved.input_muted);
                    }
                    if output_muted.is_some() {
                        output_muted = Some(resolved.output_muted);
                    }
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
                    self.on_connection_lost(message, true).await;
                }
            }
            SessionSignal::Kicked { epoch, message } => {
                if epoch == self.connection_epoch {
                    self.auto_reconnect = false;
                    self.on_connection_lost(message, false).await;
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
                        if let Err(error) = crate::server_icons::save(
                            &self.store_path,
                            &mut self.server_icons,
                            &server_id,
                            icon_id,
                            bytes.clone(),
                        ) {
                            self.emit(SessionEvent::Log {
                                level: "warn".into(),
                                message: format!("保存服务器图标缓存失败: {error}"),
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
                                message: format!("获取服务器图标 {icon_id} 失败: {error}"),
                            });
                        }
                    }
                }
            }
            SessionSignal::ChannelIconFetched {
                epoch,
                server_id,
                icon_id,
                result,
            } => {
                let Some(waiters) =
                    self.in_flight_channel_icons
                        .remove(&(epoch, server_id.clone(), icon_id))
                else {
                    return;
                };
                if epoch != self.connection_epoch
                    || self.active_server_id.as_deref() != Some(server_id.as_str())
                {
                    for reply in waiters {
                        let _ = reply.send(Err(SessionError::NotConnected));
                    }
                    return;
                }
                match result {
                    Ok(bytes) => {
                        if let Err(error) = crate::channel_icons::save(
                            &self.store_path,
                            &server_id,
                            icon_id,
                            &bytes,
                        ) {
                            self.emit(SessionEvent::Log {
                                level: "warn".into(),
                                message: format!("保存频道图标缓存失败: {error}"),
                            });
                        }
                        for reply in waiters {
                            let _ = reply.send(Ok(bytes.clone()));
                        }
                    }
                    Err(error) => {
                        if !matches!(error, SessionError::NotConnected) {
                            self.emit(SessionEvent::Log {
                                level: "warn".into(),
                                message: format!("获取频道图标 {icon_id} 失败: {error}"),
                            });
                        }
                        for reply in waiters {
                            let _ = reply.send(Err(Self::clone_image_error(&error)));
                        }
                    }
                }
            }
            SessionSignal::AnnounceIdentity {
                epoch,
                mode,
                allow_failure_retry,
                expected_seq,
            } => {
                if epoch != self.connection_epoch {
                    return;
                }
                if let Some(seq) = expected_seq
                    && !self.announce_state.should_run_failure_retry(seq)
                {
                    return;
                }
                self.announce_identity_step(mode, allow_failure_retry).await;
            }
            SessionSignal::ReportVoiceFlags { epoch, seq } => {
                if epoch != self.connection_epoch {
                    return;
                }
                self.report_voice_flags_step(VoiceReportMode::Timer { seq })
                    .await;
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
        self.emit(SessionEvent::State {
            state,
            connection_epoch: self.connection_epoch,
        });
    }
    pub(super) fn emit_voice_state(&self) {
        self.emit(SessionEvent::Voice(self.voice_state.clone()));
    }

    pub(super) fn emit(&self, event: SessionEvent) {
        emit(&self.events, event);
    }

    pub(super) fn emit_all(&self, events: Vec<SessionEvent>) {
        for event in events {
            self.emit(event);
        }
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

/// 日志里只保留前 `max_chars` 个字符，避免整段 JSON 刷屏。
pub(super) fn truncate_log(raw: &str, max_chars: usize) -> String {
    let mut chars = raw.chars();
    let head: String = chars.by_ref().take(max_chars).collect();
    if chars.next().is_some() {
        format!("{head}…")
    } else {
        head
    }
}

pub(super) fn client_channel(
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
