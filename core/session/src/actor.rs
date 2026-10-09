//! 命令循环：所有协议操作在这里串行执行。

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use policy::{PolicyError, ServerProfile, ServerRegistry};
use proto::ConnectError;
use tokio::sync::{broadcast, mpsc};
use tsclient_rs::{ChannelInfo, Client, ClientInfo, Event as ProtocolEvent, Logger};

use crate::store::{self, identity_path};
use crate::{
    ChannelView, ClientView, SessionCommand, SessionError, SessionEvent, SessionState,
    TextMessageView,
};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);
const DISCONNECT_TIMEOUT: Duration = Duration::from_secs(5);

pub(crate) struct Actor {
    registry: ServerRegistry,
    store_path: PathBuf,
    events: broadcast::Sender<SessionEvent>,
    logger: Arc<dyn Logger>,
    state: SessionState,
    client: Option<Arc<Client>>,
}

impl Actor {
    pub(crate) fn new(
        store_path: PathBuf,
        registry: ServerRegistry,
        events: broadcast::Sender<SessionEvent>,
    ) -> Self {
        let logger: Arc<dyn Logger> = Arc::new(EventLogger {
            events: events.clone(),
        });
        Self {
            registry,
            store_path,
            events,
            logger,
            state: SessionState::Disconnected,
            client: None,
        }
    }

    pub(crate) async fn run(&mut self, mut commands: mpsc::UnboundedReceiver<SessionCommand>) {
        while let Some(command) = commands.recv().await {
            match command {
                SessionCommand::Shutdown => break,
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
                    let _ = reply.send(self.connect(&id, &nickname).await);
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
                    let _ = reply.send(self.move_to_channel(client_id, channel_id, password).await);
                }
                SessionCommand::ListChannels { reply } => {
                    let _ = reply.send(self.list_channels().await);
                }
                SessionCommand::ListClients { reply } => {
                    let _ = reply.send(self.list_clients().await);
                }
            }
        }
        self.teardown().await;
    }

    async fn register(
        &mut self,
        label: String,
        address: String,
    ) -> Result<ServerProfile, PolicyError> {
        let profile = self.registry.register(&label, &address)?;
        self.persist().await;
        self.emit(SessionEvent::Servers(self.registry.profiles().to_vec()));
        Ok(profile)
    }

    async fn remove(&mut self, id: String) -> Result<(), PolicyError> {
        if !self.registry.remove(&id) {
            return Err(PolicyError::NotRegistered(id));
        }
        self.persist().await;
        self.emit(SessionEvent::Servers(self.registry.profiles().to_vec()));
        Ok(())
    }

    async fn connect(&mut self, id: &str, nickname: &str) -> Result<(), SessionError> {
        if self.client.is_some() {
            return Err(SessionError::Protocol("已经连接".into()));
        }

        let profile = match self.registry.require(id) {
            Ok(profile) => profile.clone(),
            Err(err) => {
                self.emit(SessionEvent::Denied {
                    message: err.to_string(),
                });
                return Err(err.into());
            }
        };

        let identity = store::load_identity(&identity_path(&self.store_path))
            .await
            .map_err(SessionError::Protocol)?;

        let mut client = match proto::client(identity, &profile, nickname, Arc::clone(&self.logger))
        {
            Ok(client) => client,
            Err(err) => {
                if matches!(err, ConnectError::Policy(_)) {
                    self.emit(SessionEvent::Denied {
                        message: err.to_string(),
                    });
                }
                return Err(err.into());
            }
        };

        register_handlers(&client, self.events.clone());
        self.set_state(SessionState::Connecting);

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
                let state = SessionState::Connected {
                    client_id: client.client_id(),
                    channel_id: client.channel_id(),
                };
                self.client = Some(Arc::new(client));
                self.set_state(state);
                Ok(())
            }
            Ok(Err(err)) => {
                let _ = client.disconnect().await;
                self.set_state(SessionState::Disconnected);
                Err(err)
            }
            Err(_) => {
                let _ = client.disconnect().await;
                self.set_state(SessionState::Disconnected);
                Err(SessionError::Timeout)
            }
        }
    }

    async fn disconnect(&mut self) -> Result<(), SessionError> {
        let Some(client) = self.client.take() else {
            return Ok(());
        };
        let outcome = tokio::time::timeout(DISCONNECT_TIMEOUT, client.disconnect()).await;
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
        tsclient_rs::sendTextMessage(client, target_mode, target_id, &message)
            .await
            .map_err(protocol_error)
    }

    async fn move_to_channel(
        &self,
        client_id: i32,
        channel_id: u64,
        password: Option<String>,
    ) -> Result<(), SessionError> {
        let client = self.connected()?;
        let password = password.unwrap_or_default();
        tsclient_rs::clientMove(client, client_id, channel_id, &password)
            .await
            .map_err(protocol_error)
    }

    async fn list_channels(&self) -> Result<Vec<ChannelView>, SessionError> {
        let client = self.connected()?;
        let channels = tsclient_rs::listChannels(client)
            .await
            .map_err(protocol_error)?;
        Ok(channels.into_iter().map(ChannelView::from).collect())
    }

    async fn list_clients(&self) -> Result<Vec<ClientView>, SessionError> {
        let client = self.connected()?;
        let clients = tsclient_rs::listClients(client)
            .await
            .map_err(protocol_error)?;
        Ok(clients.into_iter().map(ClientView::from).collect())
    }

    async fn teardown(&mut self) {
        if let Some(client) = self.client.take() {
            let _ = tokio::time::timeout(DISCONNECT_TIMEOUT, client.disconnect()).await;
        }
        self.set_state(SessionState::Disconnected);
    }

    async fn persist(&self) {
        if let Err(message) = store::save_registry(&self.store_path, &self.registry).await {
            self.emit(SessionEvent::Failed {
                message: format!("档案保存失败: {message}"),
            });
        }
    }

    fn connected(&self) -> Result<&Arc<Client>, SessionError> {
        self.client.as_ref().ok_or(SessionError::NotConnected)
    }

    fn set_state(&mut self, state: SessionState) {
        self.state = state.clone();
        self.emit(SessionEvent::State(state));
    }

    fn emit(&self, event: SessionEvent) {
        emit(&self.events, event);
    }
}

fn protocol_error(err: tsclient_rs::Error) -> SessionError {
    SessionError::Protocol(err.to_string())
}

fn emit(events: &broadcast::Sender<SessionEvent>, event: SessionEvent) {
    // 没有订阅者时事件直接丢弃，actor 不因此停下。
    let _ = events.send(event);
}

/// 每类事件只注册一个处理器：tsclient-rs 会为每个处理器、每个包 spawn 一个任务。
fn register_handlers(client: &Client, events: broadcast::Sender<SessionEvent>) {
    let channel = events.clone();
    client.on_text_message(Arc::new(move |event: ProtocolEvent| {
        if let ProtocolEvent::TextMessage(message) = event {
            emit(
                &channel,
                SessionEvent::TextMessage(TextMessageView {
                    from: message.invoker_name,
                    from_uid: message.invoker_uid,
                    message: message.message,
                    target_mode: message.target_mode,
                    target_id: message.target_id,
                }),
            );
        }
    }));

    let channel = events.clone();
    client.on_client_enter(Arc::new(move |event: ProtocolEvent| {
        if let ProtocolEvent::ClientEnter(info) = event {
            emit(&channel, SessionEvent::ClientJoined(ClientView::from(info)));
        }
    }));

    let channel = events.clone();
    client.on_client_leave(Arc::new(move |event: ProtocolEvent| {
        if let ProtocolEvent::ClientLeave(info) = event {
            emit(&channel, SessionEvent::ClientLeft { id: info.id });
        }
    }));

    let channel = events.clone();
    client.on_client_moved(Arc::new(move |event: ProtocolEvent| {
        if let ProtocolEvent::ClientMoved(info) = event {
            emit(
                &channel,
                SessionEvent::ClientMoved {
                    id: info.id,
                    channel_id: info.target_channel_id,
                },
            );
        }
    }));

    client.on_disconnected(Arc::new(move |event: ProtocolEvent| {
        if let ProtocolEvent::Disconnected(err) = event {
            let message = err
                .map(|err| err.to_string())
                .unwrap_or_else(|| "连接已关闭".to_string());
            emit(&events, SessionEvent::State(SessionState::Disconnected));
            emit(&events, SessionEvent::Failed { message });
        }
    }));
}

impl From<ChannelInfo> for ChannelView {
    fn from(info: ChannelInfo) -> Self {
        Self {
            id: info.id,
            parent_id: info.parent_id,
            name: info.name,
            description: info.description,
        }
    }
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
