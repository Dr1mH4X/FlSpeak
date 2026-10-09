//! 会话 actor：`Client` 的所有权与并发边界。
//!
//! 上一层的所有协议操作都经命令通道串行执行。原因是 tsclient-rs 的 `Client` 内部用
//! `std::sync::Mutex` 且在建连路径上跨 `.await` 持锁，并发调用会死锁；接收侧的每个
//! 事件都会 spawn 一个 tokio 任务，所以每类事件只允许注册一个处理器。

mod actor;
mod store;

use std::path::{Path, PathBuf};

use policy::{PolicyError, ServerProfile};
use serde::{Deserialize, Serialize};
use tokio::runtime::Builder;
use tokio::sync::{broadcast, mpsc, oneshot};
use tokio::task::LocalSet;

pub use proto::{ConnectError, validate_address};

/// 事件广播通道容量，溢出时订阅者收到 Lagged 并跳过旧事件。
pub const EVENT_CHANNEL_CAPACITY: usize = 256;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionState {
    Disconnected,
    Connecting,
    Connected { client_id: i32, channel_id: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextMessageView {
    pub from: String,
    pub from_uid: String,
    pub message: String,
    pub target_mode: i32,
    pub target_id: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChannelView {
    pub id: u64,
    pub parent_id: u64,
    pub name: String,
    pub description: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClientView {
    pub id: i32,
    pub nickname: String,
    pub uid: String,
    pub channel_id: u64,
}

#[derive(Debug, Clone)]
pub enum SessionEvent {
    State(SessionState),
    Servers(Vec<ServerProfile>),
    TextMessage(TextMessageView),
    ClientJoined(ClientView),
    ClientLeft { id: i32 },
    ClientMoved { id: i32, channel_id: u64 },
    Log { level: String, message: String },
    Denied { message: String },
    Failed { message: String },
}

pub enum SessionCommand {
    RegisterServer {
        label: String,
        address: String,
        reply: oneshot::Sender<Result<ServerProfile, PolicyError>>,
    },
    RemoveServer {
        id: String,
        reply: oneshot::Sender<Result<(), PolicyError>>,
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
    Shutdown,
}

#[derive(Debug, thiserror::Error)]
pub enum SessionError {
    #[error(transparent)]
    Policy(#[from] PolicyError),

    #[error(transparent)]
    Connect(#[from] ConnectError),

    #[error("{0}")]
    Protocol(String),

    #[error("会话 actor 已退出")]
    Closed,

    #[error("连接超时")]
    Timeout,

    #[error("尚未连接到服务器")]
    NotConnected,

    #[error("actor 线程启动失败: {0}")]
    Spawn(String),
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
        let (commands, command_rx) = mpsc::unbounded_channel();
        let (events, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let handle = Self {
            commands,
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
                    let registry = match store::load_registry(&store_path).await {
                        Ok(registry) => registry,
                        Err(message) => {
                            let _ = events.send(SessionEvent::Failed {
                                message: format!("档案读取失败: {message}"),
                            });
                            policy::ServerRegistry::new()
                        }
                    };
                    let _ = events.send(SessionEvent::Servers(registry.profiles().to_vec()));
                    actor::Actor::new(store_path, registry, events)
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
