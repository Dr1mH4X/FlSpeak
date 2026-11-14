use super::*;

const PROTOCOL_VERSION: u8 = 1;
pub(super) const IDENTITY_PLUGIN: &str = "tsclient:identity";
pub(super) const COMMANDS_PLUGIN: &str = "tsclient:commands";
const ANNOUNCE_ACK_COOLDOWN: Duration = Duration::from_secs(10);
const QUERY_ACK_COOLDOWN: Duration = Duration::from_secs(5);
const SELF_ANNOUNCE_DEBOUNCE: Duration = Duration::from_secs(2);
const SELF_ANNOUNCE_RETRY_DELAY: Duration = Duration::from_millis(500);
pub(super) const ACK_GLOBAL_BURST: f64 = 4.0;
const ACK_GLOBAL_RATE_PER_SEC: f64 = 2.0;
const MAX_PAYLOAD_BYTES: usize = 1024;
const MAX_IDENTITY_FIELD_CHARS: usize = 32;
const MAX_CAPABILITIES: usize = 16;
const MAX_BOT_COMMANDS: usize = 16;
const MAX_COMMAND_NAME_CHARS: usize = 24;
const MAX_COMMAND_ARGS_CHARS: usize = 32;
const MAX_COMMAND_DESC_CHARS: usize = 64;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub(super) struct IdentityPayload {
    v: u8,
    action: String,
    #[serde(default)]
    client_type: String,
    #[serde(default)]
    app_name: String,
    #[serde(default)]
    app_version: String,
    #[serde(default)]
    capabilities: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct CommandsPayload {
    v: u8,
    action: String,
    #[serde(default)]
    commands: Vec<BotCommandView>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct CachedPeerIdentity {
    pub(super) client_type: ClientType,
    pub(super) app_name: String,
    pub(super) app_version: String,
    pub(super) capabilities: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(super) enum AckCooldownAction {
    IdentityAnnounce,
    IdentityQuery,
}

impl AckCooldownAction {
    fn from_action(action: &str) -> Option<Self> {
        match action {
            "announce" => Some(Self::IdentityAnnounce),
            "query" => Some(Self::IdentityQuery),
            _ => None,
        }
    }

    fn cooldown(self) -> Duration {
        match self {
            Self::IdentityAnnounce => ANNOUNCE_ACK_COOLDOWN,
            Self::IdentityQuery => QUERY_ACK_COOLDOWN,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(super) struct AckCooldownKey {
    peer: String,
    action: AckCooldownAction,
}

/// 按 `(peer, action)` 隔离单播回复冷却，并用全局令牌桶约束出站 ACK 洪峰。
pub(super) struct AckRateLimiter {
    pub(super) cooldowns: HashMap<AckCooldownKey, Instant>,
    pub(super) tokens: f64,
    last_refill: Instant,
}

impl AckRateLimiter {
    pub(super) fn new(now: Instant) -> Self {
        Self {
            cooldowns: HashMap::new(),
            tokens: ACK_GLOBAL_BURST,
            last_refill: now,
        }
    }

    pub(super) fn try_acquire(
        &mut self,
        peer: &str,
        action: AckCooldownAction,
        now: Instant,
    ) -> bool {
        self.cooldowns
            .retain(|key, &mut last| now.saturating_duration_since(last) < key.action.cooldown());

        let key = AckCooldownKey {
            peer: peer.to_string(),
            action,
        };
        if let Some(&last) = self.cooldowns.get(&key)
            && now.saturating_duration_since(last) < action.cooldown()
        {
            return false;
        }

        let elapsed = now
            .saturating_duration_since(self.last_refill)
            .as_secs_f64();
        self.tokens = (self.tokens + elapsed * ACK_GLOBAL_RATE_PER_SEC).min(ACK_GLOBAL_BURST);
        self.last_refill = self.last_refill.max(now);
        if self.tokens < 1.0 {
            return false;
        }
        self.tokens -= 1.0;

        self.cooldowns.insert(key, now);
        true
    }

    pub(super) fn rollback(&mut self, peer: &str, action: AckCooldownAction, acquired_at: Instant) {
        let key = AckCooldownKey {
            peer: peer.to_string(),
            action,
        };
        if self.cooldowns.get(&key) == Some(&acquired_at) {
            self.cooldowns.remove(&key);
        }
    }

    pub(super) fn reset(&mut self, now: Instant) {
        self.cooldowns.clear();
        self.tokens = ACK_GLOBAL_BURST;
        self.last_refill = now;
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum AnnounceDecision {
    SendNow {
        attempt_at: Instant,
        seq_at_start: u64,
    },
    ScheduleTrailing {
        wait: Duration,
    },
    AlreadyScheduled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AnnounceAttemptMode {
    Normal,
    Trailing,
}

#[derive(Default)]
pub(super) struct AnnounceState {
    pub(super) last_attempt: Option<Instant>,
    pub(super) trailing_scheduled: bool,
    success_seq: u64,
}

impl AnnounceState {
    pub(super) fn try_begin(
        &mut self,
        mode: AnnounceAttemptMode,
        now: Instant,
    ) -> AnnounceDecision {
        if matches!(mode, AnnounceAttemptMode::Trailing) {
            self.trailing_scheduled = false;
        }
        if let Some(last) = self.last_attempt {
            let elapsed = now.saturating_duration_since(last);
            if elapsed < SELF_ANNOUNCE_DEBOUNCE {
                if !self.trailing_scheduled {
                    self.trailing_scheduled = true;
                    return AnnounceDecision::ScheduleTrailing {
                        wait: SELF_ANNOUNCE_DEBOUNCE - elapsed,
                    };
                }
                return AnnounceDecision::AlreadyScheduled;
            }
        }

        self.last_attempt = Some(now);
        self.trailing_scheduled = false;
        AnnounceDecision::SendNow {
            attempt_at: now,
            seq_at_start: self.success_seq,
        }
    }

    pub(super) fn record_success(&mut self) {
        self.success_seq = self.success_seq.wrapping_add(1);
    }

    pub(super) fn rollback_failure(&mut self, attempt_at: Instant, seq_at_start: u64) -> bool {
        if self.last_attempt == Some(attempt_at) {
            self.last_attempt = None;
        }
        self.success_seq == seq_at_start
    }

    pub(super) fn should_run_failure_retry(&self, seq_at_start: u64) -> bool {
        self.success_seq == seq_at_start
    }

    pub(super) fn reset(&mut self) {
        self.last_attempt = None;
        self.trailing_scheduled = false;
        self.success_seq = self.success_seq.wrapping_add(1);
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
            client.client_type = ClientType::FlSpeak;
            client.app_name = Some("FlSpeak".into());
            client.app_version = Some(env!("CARGO_PKG_VERSION").into());
            client.capabilities = self_capabilities();
            client.bot_commands = None;
            return;
        }
        if client.uid.is_empty() {
            return;
        }
        if let Some(identity) = self.peer_identities.get(&client.uid) {
            client.client_type = identity.client_type;
            client.app_name = Some(identity.app_name.clone());
            client.app_version = Some(identity.app_version.clone());
            client.capabilities = identity.capabilities.clone();
        }
        if let Some(commands) = self.peer_commands.get(&client.uid) {
            client.bot_commands = Some(commands.clone());
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

    fn encode_identity_payload(&self, action: &str) -> Option<String> {
        let payload = IdentityPayload {
            v: PROTOCOL_VERSION,
            action: action.into(),
            client_type: "flspeak".into(),
            app_name: "FlSpeak".into(),
            app_version: env!("CARGO_PKG_VERSION").into(),
            capabilities: self_capabilities(),
        };
        let data = serde_json::to_string(&payload).ok()?;
        if data.len() >= MAX_PAYLOAD_BYTES {
            self.emit(SessionEvent::Log {
                level: "warn".into(),
                message: format!(
                    "跳过发送超长开放协议载荷: action={action}, bytes={}, limit={MAX_PAYLOAD_BYTES}",
                    data.len()
                ),
            });
            return None;
        }
        Some(data)
    }

    fn schedule_announce_signal(
        &self,
        delay: Duration,
        mode: AnnounceAttemptMode,
        allow_failure_retry: bool,
        expected_seq: Option<u64>,
    ) {
        let epoch = self.connection_epoch;
        let signals = self.signals.clone();
        tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            let _ = signals.send(SessionSignal::AnnounceIdentity {
                epoch,
                mode,
                allow_failure_retry,
                expected_seq,
            });
        });
    }

    pub(super) async fn maybe_announce_identity(&mut self) {
        self.announce_identity_step(AnnounceAttemptMode::Normal, true)
            .await;
    }

    pub(super) async fn announce_identity_step(
        &mut self,
        mode: AnnounceAttemptMode,
        allow_failure_retry: bool,
    ) {
        if self.self_channel_id == 0 {
            return;
        }
        let Some(client) = self.client.clone() else {
            return;
        };
        let Some(data) = self.encode_identity_payload("announce") else {
            return;
        };

        let now = Instant::now();
        let (attempt_at, seq_at_start) = match self.announce_state.try_begin(mode, now) {
            AnnounceDecision::SendNow {
                attempt_at,
                seq_at_start,
            } => (attempt_at, seq_at_start),
            AnnounceDecision::ScheduleTrailing { wait } => {
                self.schedule_announce_signal(wait, AnnounceAttemptMode::Trailing, true, None);
                return;
            }
            AnnounceDecision::AlreadyScheduled => return,
        };

        match tsclient_rs::send_plugin_command(
            &client,
            IDENTITY_PLUGIN,
            &data,
            PluginCommandTarget::CurrentChannel,
            None,
        )
        .await
        {
            Ok(()) => self.announce_state.record_success(),
            Err(err) => {
                let should_retry = self
                    .announce_state
                    .rollback_failure(attempt_at, seq_at_start);
                self.emit(SessionEvent::Log {
                    level: "debug".into(),
                    message: format!("开放协议进房广播失败: {err}"),
                });
                if allow_failure_retry && should_retry {
                    self.schedule_announce_signal(
                        SELF_ANNOUNCE_RETRY_DELAY,
                        AnnounceAttemptMode::Normal,
                        false,
                        Some(seq_at_start),
                    );
                }
            }
        }
    }

    pub(super) async fn handle_identity_event(&mut self, event: PluginCommandEvent) {
        let Ok(payload) = serde_json::from_str::<IdentityPayload>(&event.data) else {
            return;
        };
        if payload.v != PROTOCOL_VERSION || self.self_client_id == Some(event.invoker_id) {
            return;
        }

        let peer_uid = self.resolve_peer_uid(event.invoker_id, &event.invoker_uid);
        if !peer_uid.is_empty() && !payload.client_type.is_empty() {
            let cached = sanitize_identity_payload(&payload);
            self.peer_identities.insert(peer_uid.clone(), cached);
            self.sync_peer_metadata_to_snapshot();
        }

        let Some(action) = AckCooldownAction::from_action(&payload.action) else {
            return;
        };
        let Some(client) = self.client.clone() else {
            return;
        };
        let Some(data) = self.encode_identity_payload("announce_ack") else {
            return;
        };

        let cooldown_key = if !peer_uid.is_empty() {
            peer_uid
        } else {
            event.invoker_id.to_string()
        };
        let now = Instant::now();
        if !self.ack_limiter.try_acquire(&cooldown_key, action, now) {
            return;
        }

        if let Err(err) = tsclient_rs::send_plugin_command(
            &client,
            IDENTITY_PLUGIN,
            &data,
            PluginCommandTarget::Client,
            Some(event.invoker_id),
        )
        .await
        {
            self.ack_limiter.rollback(&cooldown_key, action, now);
            self.emit(SessionEvent::Log {
                level: "debug".into(),
                message: format!(
                    "开放协议身份回执发送失败: invoker_id={}, err={err}",
                    event.invoker_id
                ),
            });
        }
    }

    pub(super) async fn query_peer_identity(
        &mut self,
        target_clid: i32,
    ) -> Result<(), SessionError> {
        let client = self.connected()?;
        let req = serde_json::json!({
            "v": PROTOCOL_VERSION,
            "action": "query"
        });
        tsclient_rs::send_plugin_command(
            &client,
            IDENTITY_PLUGIN,
            &req.to_string(),
            PluginCommandTarget::Client,
            Some(target_clid),
        )
        .await
        .map_err(protocol_error)
    }

    pub(super) fn handle_commands_event(&mut self, event: PluginCommandEvent) {
        let Ok(payload) = serde_json::from_str::<CommandsPayload>(&event.data) else {
            return;
        };
        if payload.v != PROTOCOL_VERSION
            || payload.action != "list_ack"
            || self.self_client_id == Some(event.invoker_id)
        {
            return;
        }
        let peer_uid = self.resolve_peer_uid(event.invoker_id, &event.invoker_uid);
        if peer_uid.is_empty() {
            return;
        }
        self.commands_fetching.remove(&peer_uid);
        let sanitized = sanitize_bot_commands(payload.commands);
        self.peer_commands.insert(peer_uid, sanitized);
        self.sync_peer_metadata_to_snapshot();
    }

    pub(super) async fn fetch_bot_commands(
        &mut self,
        target_clid: i32,
        target_uid: &str,
    ) -> Result<(), SessionError> {
        if target_uid.is_empty()
            || self.peer_commands.contains_key(target_uid)
            || !self.commands_fetching.insert(target_uid.to_string())
        {
            return Ok(());
        }
        let client = match self.connected() {
            Ok(client) => client,
            Err(err) => {
                self.commands_fetching.remove(target_uid);
                return Err(err);
            }
        };
        let req = serde_json::json!({
            "v": PROTOCOL_VERSION,
            "action": "list_req"
        });
        let result = tsclient_rs::send_plugin_command(
            &client,
            COMMANDS_PLUGIN,
            &req.to_string(),
            PluginCommandTarget::Client,
            Some(target_clid),
        )
        .await
        .map_err(protocol_error);
        if result.is_err() {
            self.commands_fetching.remove(target_uid);
        }
        result
    }
}

pub(super) fn self_capabilities() -> Vec<String> {
    Vec::new()
}

fn truncate_chars(s: &str, max_chars: usize) -> String {
    s.chars().take(max_chars).collect()
}

pub(super) fn sanitize_identity_payload(payload: &IdentityPayload) -> CachedPeerIdentity {
    let client_type = match payload.client_type.as_str() {
        "flspeak" => ClientType::FlSpeak,
        "bot" => ClientType::Bot,
        _ => ClientType::Custom,
    };
    let app_name = truncate_chars(&payload.app_name, MAX_IDENTITY_FIELD_CHARS);
    let app_version = truncate_chars(&payload.app_version, MAX_IDENTITY_FIELD_CHARS);
    let capabilities = payload
        .capabilities
        .iter()
        .take(MAX_CAPABILITIES)
        .map(|cap| truncate_chars(cap, MAX_IDENTITY_FIELD_CHARS))
        .collect();
    CachedPeerIdentity {
        client_type,
        app_name,
        app_version,
        capabilities,
    }
}

pub(super) fn sanitize_bot_commands(commands: Vec<BotCommandView>) -> Vec<BotCommandView> {
    commands
        .into_iter()
        .take(MAX_BOT_COMMANDS)
        .map(|mut cmd| {
            cmd.name = truncate_chars(&cmd.name, MAX_COMMAND_NAME_CHARS);
            cmd.args = truncate_chars(&cmd.args, MAX_COMMAND_ARGS_CHARS);
            cmd.desc = truncate_chars(&cmd.desc, MAX_COMMAND_DESC_CHARS);
            cmd
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::test_support::*;

    #[test]
    fn bot_command_view_deserializes_with_default_args_and_desc() {
        let json = r#"{"v":1,"action":"list_ack","commands":[{"name":"ping"},{"name":"play","args":"<song>","desc":"Play song"}]}"#;
        let payload: CommandsPayload = serde_json::from_str(json).expect("deserialize commands");
        assert_eq!(payload.commands.len(), 2);
        assert_eq!(
            payload.commands[0],
            BotCommandView {
                name: "ping".into(),
                args: String::new(),
                desc: String::new(),
            }
        );
        assert_eq!(
            payload.commands[1],
            BotCommandView {
                name: "play".into(),
                args: "<song>".into(),
                desc: "Play song".into(),
            }
        );
    }

    #[tokio::test]
    async fn identity_event_truncates_fields_ignores_self_and_updates_snapshot() {
        let mut actor = audio_actor();
        actor.self_client_id = Some(7);
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

        // 自身广播回显直接忽略，不写入缓存也不触发回复。
        actor
            .handle_identity_event(PluginCommandEvent {
                name: IDENTITY_PLUGIN.into(),
                data: r#"{"v":1,"action":"announce","client_type":"bot","app_name":"FakeSelf","app_version":"9.9"}"#.into(),
                invoker_id: 7,
                invoker_name: "Self".into(),
                invoker_uid: "self-uid".into(),
            })
            .await;
        assert!(!actor.peer_identities.contains_key("self-uid"));
        assert!(actor.ack_limiter.cooldowns.is_empty());
        assert!(events.try_recv().is_err());

        // 对端宣告超长字段与过多 capability 时按上限截断，并同步刷新内存快照。
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

        actor
            .handle_identity_event(PluginCommandEvent {
                name: IDENTITY_PLUGIN.into(),
                data,
                invoker_id: 12,
                invoker_name: "MusicBot".into(),
                invoker_uid: "bot-uid".into(),
            })
            .await;

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
        actor.last_snapshot = Some((
            Vec::new(),
            vec![ClientView::from(ClientInfo {
                id: 12,
                nickname: "MusicBot".into(),
                uid: "bot-uid".into(),
                ..client_info(12, 5, "MusicBot")
            })],
        ));
        actor.commands_fetching.insert("bot-uid".into());
        let mut events = actor.events.subscribe();

        for bad_version in [0, 2] {
            actor
                .handle_identity_event(PluginCommandEvent {
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
                })
                .await;

            actor.handle_commands_event(PluginCommandEvent {
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

        assert!(!actor.peer_identities.contains_key("bot-uid"));
        assert!(!actor.peer_commands.contains_key("bot-uid"));
        assert!(actor.commands_fetching.contains("bot-uid"));
        assert!(events.try_recv().is_err());
    }

    #[test]
    fn ack_rate_limiter_isolates_actions_enforces_global_bucket_and_rolls_back() {
        let t0 = Instant::now();
        let mut limiter = AckRateLimiter::new(t0);

        // 同一对端的 announce 与 query 冷却相互独立，不交叉阻塞。
        assert!(limiter.try_acquire("peer-a", AckCooldownAction::IdentityAnnounce, t0));
        assert!(limiter.try_acquire("peer-a", AckCooldownAction::IdentityQuery, t0));
        assert!(!limiter.try_acquire(
            "peer-a",
            AckCooldownAction::IdentityQuery,
            t0 + Duration::from_secs(4)
        ));
        assert!(limiter.try_acquire(
            "peer-a",
            AckCooldownAction::IdentityQuery,
            t0 + Duration::from_secs(5)
        ));
        assert!(!limiter.try_acquire(
            "peer-a",
            AckCooldownAction::IdentityAnnounce,
            t0 + Duration::from_secs(9)
        ));
        assert!(limiter.try_acquire(
            "peer-a",
            AckCooldownAction::IdentityAnnounce,
            t0 + Duration::from_secs(10)
        ));

        // 全局令牌桶初始突发为 4，耗尽后第 5 个请求被拒绝且不会污染该对端冷却记录。
        let t_burst = t0 + Duration::from_secs(30);
        let mut burst = AckRateLimiter::new(t_burst);
        for i in 0..4 {
            assert!(burst.try_acquire(
                &format!("peer-{i}"),
                AckCooldownAction::IdentityAnnounce,
                t_burst
            ));
        }
        assert!(!burst.try_acquire("peer-blocked", AckCooldownAction::IdentityAnnounce, t_burst));

        // 0.5 秒后补回 1 个令牌，刚才被全局限流拒绝的 peer-blocked 立刻可请求。
        assert!(burst.try_acquire(
            "peer-blocked",
            AckCooldownAction::IdentityAnnounce,
            t_burst + Duration::from_millis(500)
        ));

        // 发送失败回滚后无需等待 5 秒冷却，且 11 秒后过期记录会被清理。
        let t_rb = t_burst + Duration::from_secs(20);
        assert!(burst.try_acquire("peer-rb", AckCooldownAction::IdentityQuery, t_rb));
        burst.rollback("peer-rb", AckCooldownAction::IdentityQuery, t_rb);
        assert!(burst.try_acquire(
            "peer-rb",
            AckCooldownAction::IdentityQuery,
            t_rb + Duration::from_millis(100)
        ));

        let t_prune = t_rb + Duration::from_secs(11);
        assert!(burst.try_acquire("peer-fresh", AckCooldownAction::IdentityQuery, t_prune));
        assert_eq!(burst.cooldowns.len(), 1);
        assert!(burst.cooldowns.contains_key(&AckCooldownKey {
            peer: "peer-fresh".to_string(),
            action: AckCooldownAction::IdentityQuery,
        }));
    }

    #[test]
    fn announce_state_schedules_trailing_and_rolls_back_on_failure() {
        let mut state = AnnounceState::default();
        let t0 = Instant::now();

        assert_eq!(
            state.try_begin(AnnounceAttemptMode::Normal, t0),
            AnnounceDecision::SendNow {
                attempt_at: t0,
                seq_at_start: 0,
            }
        );

        // 去抖窗口内多次切房仅调度一次尾随广播。
        assert_eq!(
            state.try_begin(AnnounceAttemptMode::Normal, t0 + Duration::from_millis(500)),
            AnnounceDecision::ScheduleTrailing {
                wait: Duration::from_millis(1500),
            }
        );
        assert_eq!(
            state.try_begin(AnnounceAttemptMode::Normal, t0 + Duration::from_secs(1)),
            AnnounceDecision::AlreadyScheduled
        );

        // 尾随触发时到达 2 秒窗口即刻发送。
        let t_trailing = t0 + Duration::from_secs(2);
        assert_eq!(
            state.try_begin(AnnounceAttemptMode::Trailing, t_trailing),
            AnnounceDecision::SendNow {
                attempt_at: t_trailing,
                seq_at_start: 0,
            }
        );

        // 发送失败回滚后允许单次重试，成功后阻止过期重试。
        assert!(state.rollback_failure(t_trailing, 0));
        assert!(state.should_run_failure_retry(0));
        assert_eq!(
            state.try_begin(
                AnnounceAttemptMode::Normal,
                t0 + Duration::from_millis(2100)
            ),
            AnnounceDecision::SendNow {
                attempt_at: t0 + Duration::from_millis(2100),
                seq_at_start: 0,
            }
        );
        state.record_success();
        assert!(!state.should_run_failure_retry(0));
    }

    #[test]
    fn encode_identity_payload_stays_within_payload_limit() {
        let actor = audio_actor();
        for action in ["announce", "announce_ack"] {
            let encoded = actor
                .encode_identity_payload(action)
                .expect("serialized identity payload");
            assert!(encoded.len() < MAX_PAYLOAD_BYTES);
            let value: serde_json::Value =
                serde_json::from_str(&encoded).expect("valid json payload");
            assert_eq!(value["v"], PROTOCOL_VERSION);
            assert_eq!(value["action"], action);
        }
    }

    #[tokio::test]
    async fn commands_event_truncates_fields_clears_inflight_and_updates_snapshot() {
        let mut actor = audio_actor();
        actor.self_client_id = Some(7);
        actor.last_snapshot = Some((
            Vec::new(),
            vec![ClientView::from(ClientInfo {
                id: 12,
                nickname: "MusicBot".into(),
                uid: "bot-uid".into(),
                ..client_info(12, 5, "MusicBot")
            })],
        ));
        actor.commands_fetching.insert("bot-uid".into());

        // 请求仍在途中时，重复调用 fetch_bot_commands 直接幂等跳过。
        assert!(actor.fetch_bot_commands(12, "bot-uid").await.is_ok());

        let mut events = actor.events.subscribe();
        let raw_commands: Vec<serde_json::Value> = (0..20)
            .map(|i| {
                serde_json::json!({
                    "name": format!("cmd_{i:02}_{}", "n".repeat(30)),
                    "args": "a".repeat(45),
                    "desc": "转化说明".repeat(25),
                })
            })
            .collect();
        let payload = serde_json::json!({
            "v": 1,
            "action": "list_ack",
            "commands": raw_commands,
        })
        .to_string();

        actor.handle_commands_event(PluginCommandEvent {
            name: COMMANDS_PLUGIN.into(),
            data: payload,
            invoker_id: 12,
            invoker_name: "MusicBot".into(),
            invoker_uid: "bot-uid".into(),
        });

        assert!(!actor.commands_fetching.contains("bot-uid"));
        let cached = actor.peer_commands.get("bot-uid").expect("cached commands");
        assert_eq!(cached.len(), 16);
        assert!(cached.iter().all(|c| c.name.chars().count() <= 24));
        assert!(cached.iter().all(|c| c.args.chars().count() <= 32));
        assert!(cached.iter().all(|c| c.desc.chars().count() <= 64));

        let Some(SessionEvent::Snapshot { clients, .. }) = events.try_recv().ok() else {
            panic!("expected Snapshot event after commands update");
        };
        let bot = clients.iter().find(|c| c.id == 12).expect("bot row");
        assert_eq!(bot.bot_commands.as_ref().map(Vec::len), Some(16));

        // 命中本地缓存时 fetch_bot_commands 直接返回 Ok(())，跳过网络请求。
        assert!(actor.fetch_bot_commands(12, "bot-uid").await.is_ok());
        assert!(!actor.commands_fetching.contains("bot-uid"));
    }
}
