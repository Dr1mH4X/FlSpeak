//! 会话 actor：`Client` 的所有权与并发边界。
//!
//! 上一层的所有协议操作都经命令通道串行执行。原因是 tsclient-rs 的 `Client` 内部用
//! `std::sync::Mutex` 且在建连路径上跨 `.await` 持锁，并发调用会死锁；接收侧的每个
//! 事件都会 spawn 一个 tokio 任务，所以每类事件只允许注册一个处理器。
//!
//! 语音走旁路：编码后的语音包由音频线程回送 actor，仍然由 actor 串行调用
//! `Client::send_voice`；音频帧本身不进入这条事件流。

mod actor;
mod images;
mod store;

use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use server::{AddressError, ServerError, ServerProfile, ServerRegistry};
use tokio::runtime::Builder;
use tokio::sync::{broadcast, mpsc, oneshot};
use tokio::task::LocalSet;

pub use images::{ImageError, fetch_image};
pub use proto::ConnectError;

/// 事件广播通道容量，溢出时订阅者收到 Lagged 并跳过旧事件。
pub const EVENT_CHANNEL_CAPACITY: usize = 256;

/// 连接期间刷新频道/成员快照的间隔。
pub const SNAPSHOT_INTERVAL: Duration = Duration::from_secs(30);

/// 每台服务器保留的历史消息条数。
pub const HISTORY_LIMIT: usize = 500;

/// 非主动断开后的最大重连次数。
pub const RECONNECT_MAX_ATTEMPTS: u32 = 5;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionState {
    Disconnected,
    Connecting,
    Connected { client_id: i32, channel_id: u64 },
    Reconnecting { attempt: u32, delay_ms: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TextMessageView {
    pub from: String,
    pub from_uid: String,
    /// 发送者的客户端 id。私聊回复需要它；历史回放/旧记录缺失时为 0。
    pub from_id: i32,
    pub message: String,
    pub target_mode: i32,
    pub target_id: u64,
    /// Unix 毫秒。历史回放需要原始时间，不能由 UI 收到时再取 `now()`。
    pub at: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChannelView {
    pub id: u64,
    pub parent_id: u64,
    /// TeamSpeak 的同级排序位置；频道标志不可读时为空。
    pub order: Option<u64>,
    pub name: String,
    pub description: String,
    pub max_clients: Option<u16>,
    pub max_clients_limited: Option<bool>,
    pub password_protected: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClientView {
    pub id: i32,
    pub nickname: String,
    pub uid: String,
    pub channel_id: u64,
    /// 麦克风静音（服务器回显的 `client_input_muted`）；快照没带该标志时为空。
    pub input_muted: Option<bool>,
    /// 扬声器静音（服务器回显的 `client_output_muted`）。
    pub output_muted: Option<bool>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct VoiceStateView {
    pub muted: bool,
    pub deafened: bool,
    pub ptt_mode: bool,
    pub ptt_active: bool,
    pub input_ready: bool,
    pub output_ready: bool,
    pub message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioDeviceView {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AudioDevicesView {
    pub inputs: Vec<AudioDeviceView>,
    pub outputs: Vec<AudioDeviceView>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferDirection {
    Upload,
    Download,
}

#[derive(Debug, Clone)]
pub enum SessionEvent {
    State(SessionState),
    Servers(Vec<ServerProfile>),
    Snapshot {
        channels: Vec<ChannelView>,
        clients: Vec<ClientView>,
    },
    History {
        messages: Vec<TextMessageView>,
    },
    TextMessage(TextMessageView),
    ClientJoined(ClientView),
    ClientLeft {
        id: i32,
    },
    ClientMoved {
        id: i32,
        channel_id: u64,
    },
    /// 某个客户端（含自己）的服务器标志变了；`notifyclientupdated` 只带
    /// 变化字段，`None` 表示「本次没提」，不是「清除」。
    ClientUpdated {
        id: i32,
        input_muted: Option<bool>,
        output_muted: Option<bool>,
    },
    Voice(VoiceStateView),
    Speaking {
        client_ids: Vec<i32>,
    },
    SelfSpeaking {
        speaking: bool,
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
        direction: TransferDirection,
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

pub enum SessionCommand {
    RegisterServer {
        label: String,
        address: String,
        reply: oneshot::Sender<Result<ServerProfile, ServerError>>,
    },
    RemoveServer {
        id: String,
        reply: oneshot::Sender<Result<(), ServerError>>,
    },
    ListServers {
        reply: oneshot::Sender<Vec<ServerProfile>>,
    },
    State {
        reply: oneshot::Sender<SessionState>,
    },
    Connect {
        id: String,
        nickname: String,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    RetryConnect {
        generation: u64,
    },
    Disconnect {
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    SendText {
        target_mode: i32,
        target_id: u64,
        message: String,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    Move {
        client_id: i32,
        channel_id: u64,
        password: Option<String>,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    ListChannels {
        reply: oneshot::Sender<Result<Vec<ChannelView>, SessionError>>,
    },
    ListClients {
        reply: oneshot::Sender<Result<Vec<ClientView>, SessionError>>,
    },
    RequestSnapshot {
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    SetMuted {
        muted: bool,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    SetDeafened {
        deafened: bool,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    SetPttMode {
        enabled: bool,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    SetPttActive {
        active: bool,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    CancelIdentityUpgrade {
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    IdentityUpgradeFinished {
        generation: u64,
        level: Option<i32>,
        error: Option<String>,
    },
    SetAutoReconnect {
        enabled: bool,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    ListAudioDevices {
        reply: oneshot::Sender<Result<AudioDevicesView, SessionError>>,
    },
    SetAudioDevices {
        input: Option<String>,
        output: Option<String>,
        reply: oneshot::Sender<Result<(), SessionError>>,
    },
    UploadFile {
        local_path: String,
        remote_path: String,
        channel_id: u64,
        password: Option<String>,
        overwrite: bool,
        reply: oneshot::Sender<Result<u64, SessionError>>,
    },
    DownloadFile {
        remote_path: String,
        local_path: String,
        channel_id: u64,
        password: Option<String>,
        reply: oneshot::Sender<Result<u64, SessionError>>,
    },
    Shutdown,
}

#[derive(Debug, thiserror::Error)]
pub enum SessionError {
    #[error(transparent)]
    Server(#[from] ServerError),

    #[error(transparent)]
    Address(#[from] AddressError),

    #[error(transparent)]
    Connect(#[from] ConnectError),

    #[error(transparent)]
    Audio(#[from] audio::AudioError),

    #[error("{0}")]
    Protocol(String),

    #[error("{0}")]
    Transfer(String),

    #[error("会话 actor 已退出")]
    Closed,

    #[error("连接超时")]
    Timeout,

    #[error("尚未连接到服务器")]
    NotConnected,

    #[error("尚未进入频道")]
    NotInChannel,

    #[error("actor 线程启动失败: {0}")]
    Spawn(String),
}

/// 会话启动选项。集成测试可以关掉音频，避免在无麦克风/CI 环境里打开设备。
#[derive(Debug, Clone, Copy)]
pub struct SessionOptions {
    pub audio: bool,
}

impl Default for SessionOptions {
    fn default() -> Self {
        Self { audio: true }
    }
}

/// 会话句柄。
pub struct SessionHandle {
    commands: mpsc::UnboundedSender<SessionCommand>,
    events: broadcast::Sender<SessionEvent>,
    store_path: PathBuf,
}

impl SessionHandle {
    /// 在独占线程上启动 actor。
    ///
    /// tsclient-rs 在建连等路径上跨 `.await` 持 `std::sync::Mutex`（crate 级 allow 了
    /// `await_holding_lock`），这些 future 不是 `Send`，放进普通 `tokio::spawn` 会直接
    /// 编译不过。actor 因此跑在独占线程的 current-thread runtime + `LocalSet` 上，
    /// 协议层怎么持锁都不会传导到调用方。
    pub fn spawn(store_path: PathBuf) -> Result<Self, SessionError> {
        Self::spawn_with_options(store_path, SessionOptions::default())
    }

    /// 带选项启动；`audio=false` 时不打开任何音频设备，供集成测试使用。
    pub fn spawn_with_options(
        store_path: PathBuf,
        options: SessionOptions,
    ) -> Result<Self, SessionError> {
        let (commands, command_rx) = mpsc::unbounded_channel();
        let (events, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let (signals, signal_rx) = mpsc::unbounded_channel();
        let (audio_events, audio_rx) = mpsc::channel(actor::AUDIO_EVENT_CAPACITY);
        let voice = audio::engine::VoiceEngine::spawn(move |event| {
            let _ = audio_events.try_send(event);
        })?;

        let handle = Self {
            commands: commands.clone(),
            events: events.clone(),
            store_path: store_path.clone(),
        };

        std::thread::Builder::new()
            .name("session".into())
            .spawn(move || {
                let runtime = match Builder::new_current_thread().enable_all().build() {
                    Ok(runtime) => runtime,
                    Err(err) => {
                        let _ = events.send(SessionEvent::Failed {
                            message: format!("actor runtime 启动失败: {err}"),
                        });
                        return;
                    }
                };
                LocalSet::new().block_on(&runtime, async move {
                    let history_path = store::history_path(&store_path);
                    if let Err(message) = store::compact_history(&history_path, HISTORY_LIMIT).await
                    {
                        let _ = events.send(SessionEvent::Failed {
                            message: format!("历史消息压缩失败: {message}"),
                        });
                    }
                    let registry = match store::load_registry(&store_path).await {
                        Ok(registry) => registry,
                        Err(message) => {
                            let _ = events.send(SessionEvent::Failed {
                                message: format!("档案读取失败: {message}"),
                            });
                            ServerRegistry::new()
                        }
                    };
                    let _ = events.send(SessionEvent::Servers(registry.profiles().to_vec()));
                    actor::Actor::new(
                        store_path,
                        registry,
                        events,
                        commands,
                        signals,
                        signal_rx,
                        voice,
                        audio_rx,
                        options.audio,
                    )
                    .run(command_rx)
                    .await;
                });
            })
            .map_err(|err| SessionError::Spawn(err.to_string()))?;

        Ok(handle)
    }

    pub fn subscribe(&self) -> broadcast::Receiver<SessionEvent> {
        self.events.subscribe()
    }

    pub fn store_path(&self) -> &Path {
        &self.store_path
    }

    pub async fn register_server(
        &self,
        label: String,
        address: String,
    ) -> Result<ServerProfile, SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::RegisterServer {
            label,
            address,
            reply,
        })?;
        rx.await
            .map_err(|_| SessionError::Closed)?
            .map_err(Into::into)
    }

    pub async fn remove_server(&self, id: String) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::RemoveServer { id, reply })?;
        rx.await
            .map_err(|_| SessionError::Closed)?
            .map_err(Into::into)
    }

    pub async fn list_servers(&self) -> Result<Vec<ServerProfile>, SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::ListServers { reply })?;
        rx.await.map_err(|_| SessionError::Closed)
    }

    pub async fn state(&self) -> Result<SessionState, SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::State { reply })?;
        rx.await.map_err(|_| SessionError::Closed)
    }

    pub async fn connect(&self, id: String, nickname: String) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::Connect {
            id,
            nickname,
            reply,
        })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn disconnect(&self) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::Disconnect { reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn send_text(
        &self,
        target_mode: i32,
        target_id: u64,
        message: String,
    ) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::SendText {
            target_mode,
            target_id,
            message,
            reply,
        })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn move_to_channel(
        &self,
        client_id: i32,
        channel_id: u64,
        password: Option<String>,
    ) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::Move {
            client_id,
            channel_id,
            password,
            reply,
        })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn list_channels(&self) -> Result<Vec<ChannelView>, SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::ListChannels { reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn list_clients(&self) -> Result<Vec<ClientView>, SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::ListClients { reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn request_snapshot(&self) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::RequestSnapshot { reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn set_muted(&self, muted: bool) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::SetMuted { muted, reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn set_deafened(&self, deafened: bool) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::SetDeafened { deafened, reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn set_ptt_mode(&self, enabled: bool) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::SetPttMode { enabled, reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn set_ptt_active(&self, active: bool) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::SetPttActive { active, reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn cancel_identity_upgrade(&self) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::CancelIdentityUpgrade { reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn set_auto_reconnect(&self, enabled: bool) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::SetAutoReconnect { enabled, reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn list_audio_devices(&self) -> Result<AudioDevicesView, SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::ListAudioDevices { reply })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn set_audio_devices(
        &self,
        input: Option<String>,
        output: Option<String>,
    ) -> Result<(), SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::SetAudioDevices {
            input,
            output,
            reply,
        })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn upload_file(
        &self,
        local_path: String,
        remote_path: String,
        channel_id: u64,
        password: Option<String>,
        overwrite: bool,
    ) -> Result<u64, SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::UploadFile {
            local_path,
            remote_path,
            channel_id,
            password,
            overwrite,
            reply,
        })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    pub async fn download_file(
        &self,
        remote_path: String,
        local_path: String,
        channel_id: u64,
        password: Option<String>,
    ) -> Result<u64, SessionError> {
        let (reply, rx) = oneshot::channel();
        self.send(SessionCommand::DownloadFile {
            remote_path,
            local_path,
            channel_id,
            password,
            reply,
        })?;
        rx.await.map_err(|_| SessionError::Closed)?
    }

    /// 关闭 actor 并等待连接收尾。
    pub async fn shutdown(&self) -> Result<(), SessionError> {
        self.send(SessionCommand::Shutdown)
    }

    fn send(&self, command: SessionCommand) -> Result<(), SessionError> {
        self.commands
            .send(command)
            .map_err(|_| SessionError::Closed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn session_spawns_and_shuts_down_without_a_server() {
        let dir = std::env::temp_dir().join("flspeak-session-spawn-test");
        let _ = tokio::fs::remove_dir_all(&dir).await;
        let handle = SessionHandle::spawn(dir.join("servers.json")).expect("session spawn");
        assert!(matches!(
            handle.state().await.expect("state"),
            SessionState::Disconnected
        ));
        handle.shutdown().await.expect("shutdown");
        tokio::time::sleep(Duration::from_millis(50)).await;
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }
}
