use tsclient_rs::open_protocol::{
    ClientKind, EngineEffects, OpenProtocolConfig, OpenProtocolEngine, OpenProtocolEvent,
    PeerIdentity, SendOutcome, SendReceipt, TimerToken,
};

use super::*;

pub(super) fn new_open_protocol_engine() -> OpenProtocolEngine {
    let identity = PeerIdentity::new(ClientKind::FlSpeak, "FlSpeak", env!("CARGO_PKG_VERSION"));
    let config = OpenProtocolConfig::new(identity)
        .with_server_announce_on_join(true)
        .with_auto_discover_peers(true);
    OpenProtocolEngine::new(config, Instant::now())
}

fn map_client_type(kind: &ClientKind) -> ClientType {
    match kind {
        ClientKind::FlSpeak => ClientType::FlSpeak,
        ClientKind::Bot => ClientType::Bot,
        ClientKind::Custom(_) => ClientType::Custom,
    }
}

impl Actor {
    pub(super) fn enrich_clients(&self, clients: &mut [ClientView]) {
        for client in clients {
            self.enrich_client(client);
        }
    }

    pub(super) fn enrich_client(&self, client: &mut ClientView) {
        if Some(client.id) == self.self_client_id {
            let self_id = self.open_protocol.effective_identity();
            client.client_type = map_client_type(&self_id.client_type);
            client.app_name = Some(self_id.app_name);
            client.app_version = Some(self_id.app_version);
            client.capabilities = self_id.capabilities;
            client.bot_commands = None;
            client.bot_command_prefix = None;
            return;
        }
        if client.uid.is_empty() {
            return;
        }
        if let Some(identity) = self.open_protocol.peer_identity(&client.uid) {
            client.client_type = map_client_type(&identity.client_type);
            client.app_name = Some(identity.app_name.clone());
            client.app_version = Some(identity.app_version.clone());
            client.capabilities = identity.capabilities.clone();
        }
        if let Some(list) = self.open_protocol.peer_commands(&client.uid) {
            client.bot_commands = Some(
                list.commands
                    .iter()
                    .map(|cmd| BotCommandView {
                        name: cmd.name.clone(),
                        args: cmd.args.clone().unwrap_or_default(),
                        desc: cmd.desc.clone(),
                    })
                    .collect(),
            );
            client.bot_command_prefix = list.command_prefix.clone();
        }
    }

    fn sync_peer_metadata_to_snapshot(&mut self) {
        let Some((channels, mut clients)) = self.last_snapshot.clone() else {
            return;
        };
        self.enrich_clients(&mut clients);
        if self
            .last_snapshot
            .as_ref()
            .is_some_and(|(_, old_clients)| old_clients == &clients)
        {
            return;
        }
        self.last_snapshot = Some((channels.clone(), clients.clone()));
        self.emit(SessionEvent::Snapshot { channels, clients });
    }

    fn resolve_peer_uid(&self, invoker_id: i32, invoker_uid: &str) -> String {
        if !invoker_uid.is_empty() {
            return invoker_uid.to_string();
        }
        self.last_snapshot
            .as_ref()
            .and_then(|(_, clients)| {
                clients
                    .iter()
                    .find(|client| client.id == invoker_id && !client.uid.is_empty())
                    .map(|client| client.uid.clone())
            })
            .or_else(|| {
                self.client
                    .as_ref()?
                    .directory_snapshot()?
                    .clients
                    .into_iter()
                    .find(|client| client.id == invoker_id && !client.uid.is_empty())
                    .map(|client| client.uid)
            })
            .unwrap_or_default()
    }

    fn apply_open_protocol_effects(&mut self, effects: EngineEffects) {
        let mut metadata_changed = false;
        let mut flood_halted = false;
        for event in &effects.events {
            match event {
                OpenProtocolEvent::PeerIdentityUpdated { .. }
                | OpenProtocolEvent::PeerCommandsUpdated { .. } => metadata_changed = true,
                OpenProtocolEvent::ProbeHaltedByFlood => flood_halted = true,
                OpenProtocolEvent::SendFailed { .. } => {}
            }
        }
        if metadata_changed {
            self.sync_peer_metadata_to_snapshot();
        }
        if flood_halted {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: "server flood control triggered; paused automatic cross-channel member discovery".into(),
            });
        }

        let epoch = self.connection_epoch;
        for timer in effects.timers {
            let signals = self.signals.clone();
            tokio::spawn(async move {
                tokio::time::sleep(timer.delay).await;
                let _ = signals.send(SessionSignal::OpenProtocolTimer {
                    epoch,
                    token: timer.token,
                });
            });
        }

        for cmd in effects.outbound {
            let Ok(client) = self.connected() else {
                let _ = self
                    .open_protocol
                    .on_send_outcome(cmd.receipt, SendOutcome::Failed { flood: false });
                continue;
            };
            let signals = self.signals.clone();
            tokio::task::spawn_local(async move {
                let result = tsclient_rs::send_plugin_command(
                    &client,
                    cmd.plugin,
                    &cmd.data,
                    cmd.target,
                    cmd.target_id,
                )
                .await;
                let outcome = SendOutcome::from_result(&result);
                let error = result.err().map(|err| err.to_string());
                let _ = signals.send(SessionSignal::OpenProtocolSendResult {
                    epoch,
                    plugin: cmd.plugin,
                    target_id: cmd.target_id,
                    receipt: cmd.receipt,
                    outcome,
                    error,
                });
            });
        }
    }

    pub(super) fn open_protocol_connected(&mut self, clid: i32, channel_id: u64) {
        let effects = self
            .open_protocol
            .on_connected(clid, channel_id, Instant::now());
        self.apply_open_protocol_effects(effects);
    }

    pub(super) fn open_protocol_self_moved(&mut self, channel_id: u64) {
        let effects = self.open_protocol.on_self_moved(channel_id, Instant::now());
        self.apply_open_protocol_effects(effects);
    }

    pub(super) fn open_protocol_sync_peers(&mut self, clients: &[ClientView]) {
        if self.client.is_none() {
            return;
        }
        let peers: Vec<(i32, &str, u64)> = clients
            .iter()
            .map(|c| (c.id, c.uid.as_str(), c.channel_id))
            .collect();
        let effects = self
            .open_protocol
            .sync_directory_peers(&peers, Instant::now());
        self.apply_open_protocol_effects(effects);
    }

    pub(super) fn open_protocol_peer_joined(&mut self, clid: i32, uid: &str) {
        if self.client.is_none() {
            return;
        }
        let effects = self.open_protocol.on_peer_joined(clid, uid, Instant::now());
        self.apply_open_protocol_effects(effects);
    }

    pub(super) fn open_protocol_peer_left(&mut self, clid: i32) {
        self.open_protocol.on_peer_left(clid);
    }

    pub(super) fn handle_open_protocol_command(&mut self, event: PluginCommandEvent) {
        let peer_uid = self.resolve_peer_uid(event.invoker_id, &event.invoker_uid);
        let effects = self.open_protocol.on_plugin_command(
            &event,
            (!peer_uid.is_empty()).then_some(peer_uid.as_str()),
            Instant::now(),
        );
        self.apply_open_protocol_effects(effects);
    }

    pub(super) fn handle_open_protocol_timer(&mut self, token: TimerToken) {
        let effects = self.open_protocol.on_timer(token, Instant::now());
        self.apply_open_protocol_effects(effects);
    }

    pub(super) fn handle_open_protocol_send_result(
        &mut self,
        plugin: &'static str,
        target_id: Option<i32>,
        receipt: SendReceipt,
        outcome: SendOutcome,
        error: Option<String>,
    ) {
        if let Some(ref err) = error {
            self.emit(SessionEvent::Log {
                level: "debug".into(),
                message: format!(
                    "failed to send open protocol command: plugin={plugin}, target_id={target_id:?}, err={err}"
                ),
            });
        }
        let effects = self.open_protocol.on_send_outcome(receipt, outcome);
        self.apply_open_protocol_effects(effects);
    }

    pub(super) fn query_peer_identity(&mut self, target_clid: i32) -> Result<(), SessionError> {
        self.connected()?;
        let peer_uid = self.resolve_peer_uid(target_clid, "");
        let effects = self.open_protocol.request_query_peer(
            target_clid,
            (!peer_uid.is_empty()).then_some(peer_uid.as_str()),
            Instant::now(),
        );
        self.apply_open_protocol_effects(effects);
        Ok(())
    }

    pub(super) fn fetch_bot_commands(
        &mut self,
        target_clid: i32,
        target_uid: &str,
    ) -> Result<(), SessionError> {
        let effects =
            self.open_protocol
                .request_fetch_commands(target_clid, target_uid, Instant::now());
        if effects.outbound.is_empty() {
            return Ok(());
        }
        if let Err(err) = self.connected() {
            for cmd in effects.outbound {
                let _ = self
                    .open_protocol
                    .on_send_outcome(cmd.receipt, SendOutcome::Failed { flood: false });
            }
            return Err(err);
        }
        self.apply_open_protocol_effects(effects);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use tsclient_rs::open_protocol::{COMMANDS_PLUGIN, IDENTITY_PLUGIN};

    use super::*;
    use crate::actor::test_support::*;

    #[tokio::test]
    async fn identity_event_truncates_fields_ignores_self_and_updates_snapshot() {
        let mut actor = audio_actor();
        actor.self_client_id = Some(7);
        actor.open_protocol.on_connected(7, 5, Instant::now());
        actor.last_snapshot = Some((
            Vec::new(),
            vec![
                ClientView::from(ClientInfo {
                    id: 7,
                    nickname: "Self".into(),
                    uid: "self-uid".into(),
                    ..client_info(7, 5, "Self")
                }),
                ClientView::from(ClientInfo {
                    id: 12,
                    nickname: "MusicBot".into(),
                    uid: "bot-uid".into(),
                    ..client_info(12, 5, "MusicBot")
                }),
            ],
        ));
        let mut events = actor.events.subscribe();

        // 自身广播回显直接忽略，不写入缓存也不触发事件。
        actor.handle_open_protocol_command(PluginCommandEvent {
            name: IDENTITY_PLUGIN.into(),
            data: r#"{"v":1,"action":"announce","client_type":"bot","app_name":"FakeSelf","app_version":"9.9"}"#.into(),
            invoker_id: 7,
            invoker_name: "Self".into(),
            invoker_uid: "self-uid".into(),
        });
        assert!(actor.open_protocol.peer_identity("self-uid").is_none());
        assert!(events.try_recv().is_err());

        let long_name = "B".repeat(50);
        let long_ver = "1".repeat(40);
        let caps: Vec<String> = (0..20)
            .map(|i| format!("cap-{i:02}-{}", "x".repeat(40)))
            .collect();
        let data = serde_json::json!({
            "v": 1,
            "action": "announce_ack",
            "client_type": "bot",
            "app_name": long_name,
            "app_version": long_ver,
            "capabilities": caps,
        })
        .to_string();

        actor.handle_open_protocol_command(PluginCommandEvent {
            name: IDENTITY_PLUGIN.into(),
            data,
            invoker_id: 12,
            invoker_name: "MusicBot".into(),
            invoker_uid: "bot-uid".into(),
        });

        let Some(SessionEvent::Snapshot { clients, .. }) = events.try_recv().ok() else {
            panic!("expected Snapshot event after identity update");
        };
        let bot = clients.iter().find(|c| c.id == 12).expect("bot row");
        assert_eq!(bot.client_type, ClientType::Bot);
        assert_eq!(bot.app_name.as_deref().map(str::len), Some(32));
        assert_eq!(bot.app_version.as_deref().map(str::len), Some(32));
        assert_eq!(bot.capabilities.len(), 16);
        assert!(bot.capabilities.iter().all(|c| c.chars().count() <= 32));
    }

    #[tokio::test]
    async fn identity_and_commands_events_ignore_unsupported_protocol_version() {
        let mut actor = audio_actor();
        actor.self_client_id = Some(7);
        actor.open_protocol.on_connected(7, 5, Instant::now());
        actor.last_snapshot = Some((
            Vec::new(),
            vec![ClientView::from(ClientInfo {
                id: 12,
                nickname: "MusicBot".into(),
                uid: "bot-uid".into(),
                ..client_info(12, 5, "MusicBot")
            })],
        ));
        let mut events = actor.events.subscribe();

        for bad_version in [0, 2] {
            actor.handle_open_protocol_command(PluginCommandEvent {
                name: IDENTITY_PLUGIN.into(),
                data: serde_json::json!({
                    "v": bad_version,
                    "action": "announce",
                    "client_type": "bot",
                    "app_name": "MusicBot",
                    "app_version": "2.0",
                })
                .to_string(),
                invoker_id: 12,
                invoker_name: "MusicBot".into(),
                invoker_uid: "bot-uid".into(),
            });

            actor.handle_open_protocol_command(PluginCommandEvent {
                name: COMMANDS_PLUGIN.into(),
                data: serde_json::json!({
                    "v": bad_version,
                    "action": "list_ack",
                    "commands": [{ "name": "play" }],
                })
                .to_string(),
                invoker_id: 12,
                invoker_name: "MusicBot".into(),
                invoker_uid: "bot-uid".into(),
            });
        }

        assert!(actor.open_protocol.peer_identity("bot-uid").is_none());
        assert!(actor.open_protocol.peer_commands("bot-uid").is_none());
        assert!(events.try_recv().is_err());
    }

    #[tokio::test]
    async fn commands_event_truncates_fields_clears_inflight_and_updates_snapshot() {
        let mut actor = audio_actor();
        actor.self_client_id = Some(7);
        actor.open_protocol.on_connected(7, 5, Instant::now());
        actor.last_snapshot = Some((
            Vec::new(),
            vec![ClientView::from(ClientInfo {
                id: 12,
                nickname: "MusicBot".into(),
                uid: "bot-uid".into(),
                ..client_info(12, 5, "MusicBot")
            })],
        ));
        // 模拟在途请求未连客户端时回退：应返回 NotConnected
        assert!(matches!(
            actor.fetch_bot_commands(12, "bot-uid"),
            Err(SessionError::NotConnected)
        ));

        let mut events = actor.events.subscribe();
        let raw_commands: Vec<serde_json::Value> = (0..20)
            .map(|i| {
                serde_json::json!({
                    "name": format!("cmd_{i:02}_{}", "n".repeat(30)),
                    "args": "a".repeat(45),
                    "desc": "conversion note".repeat(25),
                })
            })
            .collect();
        let payload = serde_json::json!({
            "v": 1,
            "action": "list_ack",
            "command_prefix": "!",
            "commands": raw_commands,
        })
        .to_string();

        actor.handle_open_protocol_command(PluginCommandEvent {
            name: COMMANDS_PLUGIN.into(),
            data: payload,
            invoker_id: 12,
            invoker_name: "MusicBot".into(),
            invoker_uid: "bot-uid".into(),
        });

        let cached = actor
            .open_protocol
            .peer_commands("bot-uid")
            .expect("cached commands");
        assert_eq!(cached.commands.len(), 16);
        assert!(cached.commands.iter().all(|c| c.name.chars().count() <= 24));
        assert!(
            cached
                .commands
                .iter()
                .all(|c| c.args.as_deref().is_none_or(|a| a.chars().count() <= 32))
        );
        assert!(cached.commands.iter().all(|c| c.desc.chars().count() <= 64));

        let Some(SessionEvent::Snapshot { clients, .. }) = events.try_recv().ok() else {
            panic!("expected Snapshot event after commands update");
        };
        let bot = clients.iter().find(|c| c.id == 12).expect("bot row");
        assert_eq!(bot.bot_commands.as_ref().map(Vec::len), Some(16));
        assert_eq!(bot.bot_command_prefix.as_deref(), Some("!"));

        // 命中本地缓存时 fetch_bot_commands 直接返回 Ok(())，跳过网络请求。
        assert!(actor.fetch_bot_commands(12, "bot-uid").is_ok());
    }

    #[tokio::test]
    async fn flood_error_524_halts_background_probe_and_logs_warning() {
        let mut actor = audio_actor();
        let now = Instant::now();
        actor.open_protocol.on_connected(7, 5, now);
        let mut events = actor.events.subscribe();

        let eff = actor.open_protocol.sync_directory_peers(
            &[(7, "self-uid", 5), (12, "peer-a", 8), (13, "peer-b", 9)],
            now,
        );
        assert_eq!(eff.timers.len(), 1);
        let probe_eff = actor
            .open_protocol
            .on_timer(TimerToken::ProbeNext, now + Duration::from_millis(1500));
        assert_eq!(probe_eff.outbound.len(), 1);

        actor.handle_open_protocol_send_result(
            IDENTITY_PLUGIN,
            Some(12),
            probe_eff.outbound[0].receipt.clone(),
            SendOutcome::Failed { flood: true },
            Some("TeamSpeak server error: flooding (id=524)".into()),
        );

        let drained: Vec<SessionEvent> = std::iter::from_fn(|| events.try_recv().ok()).collect();
        assert!(drained.iter().any(|ev| {
            matches!(
                ev,
                SessionEvent::Log { level, message }
                    if level == "warn" && message.contains("flood control")
            )
        }));

        let after_halt = actor
            .open_protocol
            .on_timer(TimerToken::ProbeNext, now + Duration::from_millis(2400));
        assert!(after_halt.outbound.is_empty());
        assert!(after_halt.timers.is_empty());
    }
}
