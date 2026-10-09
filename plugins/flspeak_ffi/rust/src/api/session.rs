//! Dart 可见的会话 API。
//!
//! 这一层只做转发与类型转换：每个函数对应 core 里一个动作，Dart 侧拿到的类型都在
//! 本文件定义，core 的类型变化不会直接冲进生成代码。

use std::path::PathBuf;
use std::sync::OnceLock;

use flutter_rust_bridge::for_generated::SseCodec;
use flutter_rust_bridge::frb;
use policy::ServerProfile as PolicyProfile;
use proto::ConnectError;
use session::{
    ChannelView as CoreChannelView, ClientView as CoreClientView, SessionError, SessionEvent,
    SessionHandle, SessionState as SessionStateCore,
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
    pub id: u64,
    pub parent_id: u64,
    pub name: String,
    pub description: String,
}

#[derive(Debug, Clone)]
pub struct ClientView {
    pub id: i32,
    pub nickname: String,
    pub uid: String,
    pub channel_id: u64,
}

#[derive(Debug, Clone)]
pub enum CoreSessionState {
    Disconnected,
    Connecting,
    Connected { client_id: i32, channel_id: u64 },
}

/// 送往 Dart 的事件。语音帧不走这里，它在 Rust 侧直接进音频后端。
#[derive(Debug, Clone)]
pub enum CoreEvent {
    State {
        state: CoreSessionState,
    },
    Servers {
        profiles: Vec<ServerProfileView>,
    },
    TextMessage {
        from: String,
        from_uid: String,
        message: String,
        target_mode: i32,
        target_id: u64,
    },
    ClientJoined {
        id: i32,
        nickname: String,
        channel_id: u64,
    },
    ClientLeft {
        id: i32,
    },
    ClientMoved {
        id: i32,
        channel_id: u64,
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
    /// 命中合规策略，例如目标属于官方基础设施或服务器未登记。
    PolicyDenied { message: String },
    /// 建连或协议层失败。
    Connection { message: String },
    /// 桥自身的问题。
    Internal { message: String },
}

/// Dart 侧持有的核心句柄。
#[frb(opaque)]
pub struct CoreSession {
    handle: SessionHandle,
}

impl CoreSession {
    #[frb(sync)]
    pub fn new(store_path: String) -> Result<CoreSession, CoreError> {
        Ok(CoreSession {
            handle: SessionHandle::spawn(PathBuf::from(store_path))?,
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

    /// 录入服务器。地址在这里过 T1 校验，通过后成为 T2 档案，连接目标只能来自档案。
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

    pub async fn shutdown(&self) -> Result<(), CoreError> {
        Ok(self.handle.shutdown().await?)
    }
}

/// 合规审计入口：把策略判定暴露给 Dart，供设置页做“为什么连不上”的解释。
#[frb(sync)]
pub fn validate_server_address(address: String) -> Result<ServerProfileView, CoreError> {
    let target = proto::approve(&address)?;
    Ok(ServerProfileView {
        id: target.authority(),
        label: String::new(),
        host: target.host,
        port: target.port,
    })
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

impl From<PolicyProfile> for ServerProfileView {
    fn from(profile: PolicyProfile) -> Self {
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
            id: view.id,
            parent_id: view.parent_id,
            name: view.name,
            description: view.description,
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
        }
    }
}

impl From<SessionEvent> for CoreEvent {
    fn from(event: SessionEvent) -> Self {
        match event {
            SessionEvent::State(state) => CoreEvent::State {
                state: state.into(),
            },
            SessionEvent::Servers(profiles) => CoreEvent::Servers {
                profiles: profiles.into_iter().map(ServerProfileView::from).collect(),
            },
            SessionEvent::TextMessage(message) => CoreEvent::TextMessage {
                from: message.from,
                from_uid: message.from_uid,
                message: message.message,
                target_mode: message.target_mode,
                target_id: message.target_id,
            },
            SessionEvent::ClientJoined(client) => CoreEvent::ClientJoined {
                id: client.id,
                nickname: client.nickname,
                channel_id: client.channel_id,
            },
            SessionEvent::ClientLeft { id } => CoreEvent::ClientLeft { id },
            SessionEvent::ClientMoved { id, channel_id } => {
                CoreEvent::ClientMoved { id, channel_id }
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
            SessionError::Policy(_) | SessionError::Connect(ConnectError::Policy(_)) => {
                CoreError::PolicyDenied {
                    message: err.to_string(),
                }
            }
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
            ConnectError::Policy(_) => CoreError::PolicyDenied {
                message: err.to_string(),
            },
            ConnectError::Protocol(_) => CoreError::Connection {
                message: err.to_string(),
            },
        }
    }
}
