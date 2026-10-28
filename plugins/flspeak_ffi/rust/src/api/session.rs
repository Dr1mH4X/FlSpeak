//! Dart 可见的会话 API。
//!
//! 这一层只做转发与类型转换：每个函数对应 core 里一个动作，Dart 侧拿到的类型都在
//! 本文件定义，core 的类型变化不会直接冲进生成代码。

use std::path::PathBuf;
use std::sync::OnceLock;

use flutter_rust_bridge::for_generated::SseCodec;
use flutter_rust_bridge::frb;
use proto::ConnectError;
use server::ServerProfile as ServerProfileCore;
use session::{
    AudioDeviceView as CoreAudioDeviceView, ChannelView as CoreChannelView,
    ClientView as CoreClientView, SessionError, SessionEvent, SessionHandle,
    SessionState as SessionStateCore, TextMessageView as CoreTextMessage,
    TransferDirection as SessionTransferDirection,
};
use tokio::runtime::{Builder, Runtime};

use crate::frb_generated::StreamSink;

#[derive(Debug, Clone)]
pub struct ServerProfileView {
    pub id: String,
    pub label: String,
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone)]
pub struct ChannelView {
    pub icon_id: Option<u32>,
    pub id: u64,
    pub parent_id: u64,
    pub order: Option<u64>,
    pub name: String,
    pub description: String,
    pub max_clients: Option<u16>,
    pub max_clients_limited: Option<bool>,
    pub password_protected: Option<bool>,
}

#[derive(Debug, Clone)]
pub struct ClientView {
    pub id: i32,
    pub nickname: String,
    pub uid: String,
    pub channel_id: u64,
    /// 麦克风静音（服务器回显）；目录快照没带标志时为 null。
    pub input_muted: Option<bool>,
    /// 扬声器静音（服务器回显）。
    pub output_muted: Option<bool>,
    /// 离开状态（服务器回显）。
    pub away: Option<bool>,
    /// 离开时留下的说明文字。
    pub away_message: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CoreMessage {
    pub from: String,
    pub from_uid: String,
    pub message: String,
    pub target_mode: i32,
    pub target_id: u64,
    pub at: u64,
}

#[derive(Debug, Clone)]
pub struct CoreVoiceState {
    pub muted: bool,
    pub deafened: bool,
    pub away: bool,
    pub ptt_mode: bool,
    pub ptt_active: bool,
    pub input_ready: bool,
    pub output_ready: bool,
    pub message: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AudioDeviceView {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

#[derive(Debug, Clone)]
pub struct AudioDevicesView {
    pub inputs: Vec<AudioDeviceView>,
    pub outputs: Vec<AudioDeviceView>,
}

#[derive(Debug, Clone)]
pub enum CoreTransferDirection {
    Upload,
    Download,
}

#[derive(Debug, Clone)]
pub enum CoreSessionState {
    Disconnected,
    Connecting,
    Connected { client_id: i32, channel_id: u64 },
    Reconnecting { attempt: u32, delay_ms: u64 },
}

/// 送往 Dart 的事件。语音帧不走这里，它在 Rust 侧直接进音频后端。
#[derive(Debug, Clone)]
pub enum CoreEvent {
    AccessChanged,
    State {
        state: CoreSessionState,
    },
    Servers {
        profiles: Vec<ServerProfileView>,
    },
    Snapshot {
        channels: Vec<ChannelView>,
        clients: Vec<ClientView>,
    },
    History {
        messages: Vec<CoreMessage>,
    },
    TextMessage {
        from: String,
        from_uid: String,
        message: String,
        target_mode: i32,
        target_id: u64,
        at: u64,
    },
    Poked {
        from: String,
        message: String,
    },
    ClientJoined {
        id: i32,
        nickname: String,
        uid: String,
        channel_id: u64,
    },
    ClientLeft {
        id: i32,
    },
    ClientMoved {
        id: i32,
        channel_id: u64,
    },
    /// 某个客户端（含自己）的服务器标志变化；null 表示本次事件没提到，
    /// 不是清除。
    ClientUpdated {
        id: i32,
        input_muted: Option<bool>,
        output_muted: Option<bool>,
        away: Option<bool>,
        away_message: Option<String>,
    },
    Voice {
        state: CoreVoiceState,
    },
    Speaking {
        client_ids: Vec<i32>,
    },
    SelfSpeaking {
        speaking: bool,
    },
    /// 本端采集与远端混音电平（0–1），≤10Hz。
    Levels {
        mic: f64,
        received: f64,
    },
    IdentityUpgrade {
        from: i32,
        to: i32,
    },
    IdentityUpgraded {
        level: i32,
    },
    TransferStarted {
        id: u64,
        direction: CoreTransferDirection,
        remote_path: String,
        total: u64,
    },
    TransferProgress {
        id: u64,
        transferred: u64,
        total: u64,
    },
    TransferFinished {
        id: u64,
        error: Option<String>,
    },
    Log {
        level: String,
        message: String,
    },
    Denied {
        message: String,
    },
    Failed {
        message: String,
    },
}

#[derive(Debug, Clone)]
pub enum CoreError {
    /// 地址为空、格式非法或不是 IP/域名。
    InvalidAddress {
        message: String,
    },
    /// 地址或图片主机被最终连接边界拒绝。
    BlockedAddress {
        message: String,
    },
    /// 建连或协议层失败。
    Connection {
        message: String,
    },
    ChannelPasswordRequired {
        message: String,
    },
    /// 桥自身的问题。
    Internal {
        message: String,
    },
}

#[derive(Debug, Clone)]
pub struct AccessView {
    pub member_add_power: Option<i32>,
    pub member_remove_power: Option<i32>,
    pub kick_channel_power: Option<i32>,
    pub kick_server_power: Option<i32>,
    pub connection_epoch: Option<u64>,
}
#[derive(Debug, Clone)]
pub enum KickTarget {
    Channel,
    Server,
}
#[derive(Debug, Clone)]
pub enum GroupKind {
    Server,
    Channel,
}
#[derive(Debug, Clone)]
pub struct MemberGroupView {
    pub channel_id: u64,
    pub id: u64,
    pub name: String,
    pub kind: GroupKind,
    pub member: bool,
    pub can_add: bool,
    pub can_remove: bool,
}
#[derive(Debug, Clone)]
pub struct ChannelFileView {
    pub name: String,
    pub path: String,
    pub directory: bool,
    pub size: u64,
}

/// Dart 侧持有的核心句柄。
#[frb(opaque)]
pub struct CoreSession {
    handle: SessionHandle,
}

impl CoreSession {
    #[frb(sync)]
    pub fn new(store_path: String, audio_enabled: Option<bool>) -> Result<CoreSession, CoreError> {
        Ok(CoreSession {
            handle: SessionHandle::spawn_with_options(
                PathBuf::from(store_path),
                session::SessionOptions {
                    audio: audio_enabled.unwrap_or(true),
                },
            )?,
        })
    }

    /// 订阅事件流。
    ///
    /// 取消订阅要在 `shutdown()` 之后：`shutdown()` 关闭广播通道，转发任务随即退出，
    /// 这时 Dart 侧取消订阅会立刻完成；反过来先取消，要等下一次 `add` 失败才收尾。
    pub fn events(&self, sink: StreamSink<CoreEvent, SseCodec>) -> Result<(), CoreError> {
        let mut events = self.handle.subscribe();
        runtime()?.spawn(async move {
            loop {
                match events.recv().await {
                    Ok(event) => {
                        if sink.add(CoreEvent::from(event)).is_err() {
                            break;
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                }
            }
        });
        Ok(())
    }

    pub async fn list_servers(&self) -> Result<Vec<ServerProfileView>, CoreError> {
        let profiles = self.handle.list_servers().await?;
        Ok(profiles.into_iter().map(ServerProfileView::from).collect())
    }

    /// 录入服务器。地址在这里解析并登记，连接目标只能来自档案。
    pub async fn register_server(
        &self,
        label: String,
        address: String,
    ) -> Result<ServerProfileView, CoreError> {
        let profile = self.handle.register_server(label, address).await?;
        Ok(ServerProfileView::from(profile))
    }

    pub async fn remove_server(&self, id: String) -> Result<(), CoreError> {
        Ok(self.handle.remove_server(id).await?)
    }

    pub async fn state(&self) -> Result<CoreSessionState, CoreError> {
        Ok(self.handle.state().await?.into())
    }

    pub async fn connect(&self, id: String, nickname: String) -> Result<(), CoreError> {
        Ok(self.handle.connect(id, nickname).await?)
    }

    pub async fn disconnect(&self) -> Result<(), CoreError> {
        Ok(self.handle.disconnect().await?)
    }

    pub async fn send_text(
        &self,
        target_mode: i32,
        target_id: u64,
        message: String,
    ) -> Result<(), CoreError> {
        Ok(self
            .handle
            .send_text(target_mode, target_id, message)
            .await?)
    }

    pub async fn poke(&self, client_id: i32, message: String) -> Result<(), CoreError> {
        Ok(self.handle.poke(client_id, message).await?)
    }

    pub async fn move_to_channel(
        &self,
        client_id: i32,
        channel_id: u64,
        password: Option<String>,
    ) -> Result<(), CoreError> {
        Ok(self
            .handle
            .move_to_channel(client_id, channel_id, password)
            .await?)
    }

    pub async fn list_channels(&self) -> Result<Vec<ChannelView>, CoreError> {
        let channels = self.handle.list_channels().await?;
        Ok(channels.into_iter().map(ChannelView::from).collect())
    }

    pub async fn list_clients(&self) -> Result<Vec<ClientView>, CoreError> {
        let clients = self.handle.list_clients().await?;
        Ok(clients.into_iter().map(ClientView::from).collect())
    }

    /// 主动拉一次频道/成员快照。连接期间 actor 也会每 30 秒自动刷新。
    pub async fn request_snapshot(&self) -> Result<(), CoreError> {
        Ok(self.handle.request_snapshot().await?)
    }

    pub async fn set_muted(&self, muted: bool) -> Result<(), CoreError> {
        Ok(self.handle.set_muted(muted).await?)
    }

    pub async fn set_deafened(&self, deafened: bool) -> Result<(), CoreError> {
        Ok(self.handle.set_deafened(deafened).await?)
    }

    pub async fn set_away(&self, away: bool) -> Result<(), CoreError> {
        Ok(self.handle.set_away(away).await?)
    }

    pub async fn set_ptt_mode(&self, enabled: bool) -> Result<(), CoreError> {
        Ok(self.handle.set_ptt_mode(enabled).await?)
    }

    pub async fn set_ptt_active(&self, active: bool) -> Result<(), CoreError> {
        Ok(self.handle.set_ptt_active(active).await?)
    }

    pub async fn cancel_identity_upgrade(&self) -> Result<(), CoreError> {
        Ok(self.handle.cancel_identity_upgrade().await?)
    }

    pub async fn set_auto_reconnect(&self, enabled: bool) -> Result<(), CoreError> {
        Ok(self.handle.set_auto_reconnect(enabled).await?)
    }

    pub async fn list_audio_devices(&self) -> Result<AudioDevicesView, CoreError> {
        Ok(self.handle.list_audio_devices().await?.into())
    }

    pub async fn set_audio_devices(
        &self,
        input: Option<String>,
        output: Option<String>,
    ) -> Result<(), CoreError> {
        Ok(self.handle.set_audio_devices(input, output).await?)
    }

    pub async fn upload_file(
        &self,
        local_path: String,
        remote_path: String,
        channel_id: u64,
        password: Option<String>,
        overwrite: bool,
    ) -> Result<u64, CoreError> {
        Ok(self
            .handle
            .upload_file(local_path, remote_path, channel_id, password, overwrite)
            .await?)
    }

    pub async fn fetch_icon(&self, icon_id: u32) -> Result<Vec<u8>, CoreError> {
        Ok(self.handle.fetch_icon(icon_id).await?)
    }

    pub async fn access(&self) -> Result<AccessView, CoreError> {
        let access = self.handle.access().await?;
        Ok(AccessView {
            member_add_power: access.member_add_power,
            member_remove_power: access.member_remove_power,
            kick_channel_power: access.kick_channel_power,
            kick_server_power: access.kick_server_power,
            connection_epoch: access.connection_epoch,
        })
    }
    pub async fn kick(
        &self,
        uid: String,
        channel_id: u64,
        target: KickTarget,
        reason: String,
        connection_epoch: u64,
    ) -> Result<(), CoreError> {
        self.handle
            .kick(
                uid,
                channel_id,
                match target {
                    KickTarget::Channel => session::KickTarget::Channel,
                    KickTarget::Server => session::KickTarget::Server,
                },
                reason,
                connection_epoch,
            )
            .await?;
        Ok(())
    }
    pub async fn member_groups(&self, uid: String) -> Result<Vec<MemberGroupView>, CoreError> {
        Ok(self
            .handle
            .member_groups(uid)
            .await?
            .into_iter()
            .map(|g| MemberGroupView {
                channel_id: g.channel_id,
                id: g.id,
                name: g.name,
                kind: match g.kind {
                    session::GroupKind::Server => GroupKind::Server,
                    session::GroupKind::Channel => GroupKind::Channel,
                },
                member: g.member,
                can_add: g.can_add,
                can_remove: g.can_remove,
            })
            .collect())
    }
    pub async fn set_member_group(
        &self,
        uid: String,
        group_id: u64,
        channel_id: u64,
        kind: GroupKind,
        enabled: bool,
    ) -> Result<(), CoreError> {
        self.handle
            .set_member_group(
                uid,
                group_id,
                channel_id,
                match kind {
                    GroupKind::Server => session::GroupKind::Server,
                    GroupKind::Channel => session::GroupKind::Channel,
                },
                enabled,
            )
            .await?;
        Ok(())
    }
    pub async fn list_files(
        &self,
        channel_id: u64,
        path: String,
        password: Option<String>,
    ) -> Result<Vec<ChannelFileView>, CoreError> {
        Ok(self
            .handle
            .list_files(channel_id, path, password.unwrap_or_default())
            .await?
            .into_iter()
            .map(|f| ChannelFileView {
                name: f.name,
                path: f.path,
                directory: f.directory,
                size: f.size,
            })
            .collect())
    }

    pub async fn download_file(
        &self,
        remote_path: String,
        local_path: String,
        channel_id: u64,
        password: Option<String>,
    ) -> Result<u64, CoreError> {
        Ok(self
            .handle
            .download_file(remote_path, local_path, channel_id, password)
            .await?)
    }

    pub async fn shutdown(&self) -> Result<(), CoreError> {
        Ok(self.handle.shutdown().await?)
    }
}

/// 抓取第三方图片 URL。myTS 的 `ts.file.myts` 附件不经过这里。
pub async fn fetch_image(url: String) -> Result<Vec<u8>, CoreError> {
    Ok(session::fetch_image(&url).await?)
}

pub fn validate_image_host(upload_base: String, public_base: String) -> Result<(), CoreError> {
    Ok(session::validate_image_host(&upload_base, &public_base)?)
}

pub async fn upload_image(
    upload_base: String,
    public_base: String,
    token: Option<String>,
    bytes: Vec<u8>,
) -> Result<String, CoreError> {
    Ok(session::upload_image(&upload_base, &public_base, token.as_deref(), bytes).await?)
}

impl From<session::ImageError> for CoreError {
    fn from(err: session::ImageError) -> Self {
        match err {
            session::ImageError::InvalidUrl(_) => CoreError::InvalidAddress {
                message: err.to_string(),
            },
            session::ImageError::BlockedHost(_) | session::ImageError::BlockedAddress(_) => {
                CoreError::BlockedAddress {
                    message: err.to_string(),
                }
            }
            _ => CoreError::Connection {
                message: err.to_string(),
            },
        }
    }
}

fn runtime() -> Result<&'static Runtime, CoreError> {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    if let Some(runtime) = RUNTIME.get() {
        return Ok(runtime);
    }
    let built = Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .thread_name("flspeak-core")
        .build()
        .map_err(|err| CoreError::Internal {
            message: format!("tokio runtime: {err}"),
        })?;
    let _ = RUNTIME.set(built);
    RUNTIME.get().ok_or(CoreError::Internal {
        message: "tokio runtime 初始化竞态".into(),
    })
}

impl From<ServerProfileCore> for ServerProfileView {
    fn from(profile: ServerProfileCore) -> Self {
        Self {
            id: profile.id,
            label: profile.label,
            host: profile.host,
            port: profile.port,
        }
    }
}

impl From<CoreChannelView> for ChannelView {
    fn from(view: CoreChannelView) -> Self {
        Self {
            icon_id: view.icon_id,
            id: view.id,
            parent_id: view.parent_id,
            order: view.order,
            name: view.name,
            description: view.description,
            max_clients: view.max_clients,
            max_clients_limited: view.max_clients_limited,
            password_protected: view.password_protected,
        }
    }
}

impl From<CoreClientView> for ClientView {
    fn from(view: CoreClientView) -> Self {
        Self {
            id: view.id,
            nickname: view.nickname,
            uid: view.uid,
            channel_id: view.channel_id,
            input_muted: view.input_muted,
            output_muted: view.output_muted,
            away: view.away,
            away_message: view.away_message,
        }
    }
}

impl From<CoreTextMessage> for CoreMessage {
    fn from(message: CoreTextMessage) -> Self {
        Self {
            from: message.from,
            from_uid: message.from_uid,
            message: message.message,
            target_mode: message.target_mode,
            target_id: message.target_id,
            at: message.at,
        }
    }
}

impl From<SessionStateCore> for CoreSessionState {
    fn from(state: SessionStateCore) -> Self {
        match state {
            SessionStateCore::Disconnected => CoreSessionState::Disconnected,
            SessionStateCore::Connecting => CoreSessionState::Connecting,
            SessionStateCore::Connected {
                client_id,
                channel_id,
            } => CoreSessionState::Connected {
                client_id,
                channel_id,
            },
            SessionStateCore::Reconnecting { attempt, delay_ms } => {
                CoreSessionState::Reconnecting { attempt, delay_ms }
            }
        }
    }
}

impl From<SessionTransferDirection> for CoreTransferDirection {
    fn from(direction: SessionTransferDirection) -> Self {
        match direction {
            SessionTransferDirection::Upload => CoreTransferDirection::Upload,
            SessionTransferDirection::Download => CoreTransferDirection::Download,
        }
    }
}

impl From<session::VoiceStateView> for CoreVoiceState {
    fn from(state: session::VoiceStateView) -> Self {
        Self {
            muted: state.muted,
            deafened: state.deafened,
            away: state.away,
            ptt_mode: state.ptt_mode,
            ptt_active: state.ptt_active,
            input_ready: state.input_ready,
            output_ready: state.output_ready,
            message: state.message,
        }
    }
}

impl From<CoreAudioDeviceView> for AudioDeviceView {
    fn from(device: CoreAudioDeviceView) -> Self {
        Self {
            id: device.id,
            name: device.name,
            is_default: device.is_default,
        }
    }
}

impl From<session::AudioDevicesView> for AudioDevicesView {
    fn from(devices: session::AudioDevicesView) -> Self {
        Self {
            inputs: devices.inputs.into_iter().map(Into::into).collect(),
            outputs: devices.outputs.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<SessionEvent> for CoreEvent {
    fn from(event: SessionEvent) -> Self {
        match event {
            SessionEvent::AccessChanged => CoreEvent::AccessChanged,
            SessionEvent::State(state) => CoreEvent::State {
                state: state.into(),
            },
            SessionEvent::Servers(profiles) => CoreEvent::Servers {
                profiles: profiles.into_iter().map(ServerProfileView::from).collect(),
            },
            SessionEvent::Snapshot { channels, clients } => CoreEvent::Snapshot {
                channels: channels.into_iter().map(ChannelView::from).collect(),
                clients: clients.into_iter().map(ClientView::from).collect(),
            },
            SessionEvent::History { messages } => CoreEvent::History {
                messages: messages.into_iter().map(CoreMessage::from).collect(),
            },
            SessionEvent::TextMessage(message) => CoreEvent::TextMessage {
                from: message.from,
                from_uid: message.from_uid,
                message: message.message,
                target_mode: message.target_mode,
                target_id: message.target_id,
                at: message.at,
            },
            SessionEvent::Poked { from, message } => CoreEvent::Poked { from, message },
            SessionEvent::ClientJoined(client) => CoreEvent::ClientJoined {
                id: client.id,
                nickname: client.nickname,
                uid: client.uid,
                channel_id: client.channel_id,
            },
            SessionEvent::ClientLeft { id } => CoreEvent::ClientLeft { id },
            SessionEvent::ClientMoved { id, channel_id } => {
                CoreEvent::ClientMoved { id, channel_id }
            }
            SessionEvent::ClientUpdated {
                id,
                input_muted,
                output_muted,
                away,
                away_message,
            } => CoreEvent::ClientUpdated {
                id,
                input_muted,
                output_muted,
                away,
                away_message,
            },
            SessionEvent::Voice(state) => CoreEvent::Voice {
                state: state.into(),
            },
            SessionEvent::Speaking { client_ids } => CoreEvent::Speaking { client_ids },
            SessionEvent::SelfSpeaking { speaking } => CoreEvent::SelfSpeaking { speaking },
            SessionEvent::Levels { mic, received } => CoreEvent::Levels {
                mic: mic as f64,
                received: received as f64,
            },
            SessionEvent::IdentityUpgrade { from, to } => CoreEvent::IdentityUpgrade { from, to },
            SessionEvent::IdentityUpgraded { level } => CoreEvent::IdentityUpgraded { level },
            SessionEvent::TransferStarted {
                id,
                direction,
                remote_path,
                total,
            } => CoreEvent::TransferStarted {
                id,
                direction: direction.into(),
                remote_path,
                total,
            },
            SessionEvent::TransferProgress {
                id,
                transferred,
                total,
            } => CoreEvent::TransferProgress {
                id,
                transferred,
                total,
            },
            SessionEvent::TransferFinished { id, error } => {
                CoreEvent::TransferFinished { id, error }
            }
            SessionEvent::Log { level, message } => CoreEvent::Log { level, message },
            SessionEvent::Denied { message } => CoreEvent::Denied { message },
            SessionEvent::Failed { message } => CoreEvent::Failed { message },
        }
    }
}

impl From<SessionError> for CoreError {
    fn from(err: SessionError) -> Self {
        match err {
            SessionError::Server(server::ServerError::Address(_))
            | SessionError::Address(_)
            | SessionError::Connect(ConnectError::Address(_)) => CoreError::InvalidAddress {
                message: err.to_string(),
            },
            SessionError::Connect(ConnectError::Blocked { .. }) => CoreError::BlockedAddress {
                message: err.to_string(),
            },
            SessionError::ChannelPasswordRequired => CoreError::ChannelPasswordRequired {
                message: err.to_string(),
            },
            SessionError::Closed | SessionError::Spawn(_) => CoreError::Internal {
                message: err.to_string(),
            },
            _ => CoreError::Connection {
                message: err.to_string(),
            },
        }
    }
}

impl From<ConnectError> for CoreError {
    fn from(err: ConnectError) -> Self {
        match err {
            ConnectError::Address(_) => CoreError::InvalidAddress {
                message: err.to_string(),
            },
            ConnectError::Blocked { .. } => CoreError::BlockedAddress {
                message: err.to_string(),
            },
            ConnectError::TransferHostMismatch { .. } | ConnectError::Protocol(_) => {
                CoreError::Connection {
                    message: err.to_string(),
                }
            }
        }
    }
}
