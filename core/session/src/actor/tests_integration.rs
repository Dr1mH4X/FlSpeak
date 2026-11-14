use super::*;
use crate::actor::test_support::*;

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

#[test]
fn invalidate_handlers_resets_open_protocol_caches_and_cooldowns() {
    let mut actor = audio_actor();
    actor.peer_identities.insert(
        "bot-uid".into(),
        CachedPeerIdentity {
            client_type: ClientType::Bot,
            app_name: "Bot".into(),
            app_version: "1.0".into(),
            capabilities: vec!["chat:slash_commands".into()],
        },
    );
    actor.peer_commands.insert("bot-uid".into(), Vec::new());
    actor.commands_fetching.insert("other-uid".into());
    let now = Instant::now();
    assert!(
        actor
            .ack_limiter
            .try_acquire("bot-uid", AckCooldownAction::IdentityAnnounce, now)
    );
    assert!(matches!(
        actor
            .announce_state
            .try_begin(AnnounceAttemptMode::Normal, now),
        AnnounceDecision::SendNow { .. }
    ));
    let prev_epoch = actor.connection_epoch;

    actor.invalidate_handlers();

    assert!(actor.peer_identities.is_empty());
    assert!(actor.peer_commands.is_empty());
    assert!(actor.commands_fetching.is_empty());
    assert!(actor.ack_limiter.cooldowns.is_empty());
    assert_eq!(actor.ack_limiter.tokens, ACK_GLOBAL_BURST);
    assert!(actor.announce_state.last_attempt.is_none());
    assert!(!actor.announce_state.trailing_scheduled);
    assert!(!actor.announce_state.should_run_failure_retry(0));
    assert_eq!(actor.connection_epoch, prev_epoch + 1);
    assert!(actor.channel_list_allowed.is_none());
    assert!(actor.channel_meta_allowed.is_none());
    assert!(actor.client_list_allowed.is_none());
    assert!(!actor.subscribed_all_channels);
    assert!(actor.self_server_groups.is_empty());
}

#[tokio::test]
async fn dynamic_reset_triggers_clear_permission_flags() {
    let mut actor = audio_actor();
    actor.self_client_id = Some(7);
    actor.self_channel_id = 5;
    actor.self_server_groups = vec!["6".into()];

    // 1. 切换频道重置权限标志。
    actor.channel_list_allowed = Some(false);
    actor.channel_meta_allowed = Some(false);
    actor.client_list_allowed = Some(false);
    actor.on_self_moved(9).await;
    assert_eq!(actor.channel_list_allowed, None);
    assert_eq!(actor.channel_meta_allowed, None);
    assert_eq!(actor.client_list_allowed, None);

    // 2. ClientUpdated 服务器组不变时不重置；变化时重置（顺序不同但集合相同也不重置）。
    actor.channel_list_allowed = Some(false);
    actor.channel_meta_allowed = Some(false);
    actor.client_list_allowed = Some(false);
    actor.self_server_groups = vec!["6".into(), "8".into()];
    actor
        .handle_signal(SessionSignal::ClientUpdated {
            epoch: actor.connection_epoch,
            id: 7,
            input_muted: None,
            output_muted: None,
            away: None,
            away_message: None,
            server_groups: vec!["8".into(), "6".into()],
        })
        .await;
    assert_eq!(actor.channel_list_allowed, Some(false));

    actor
        .handle_signal(SessionSignal::ClientUpdated {
            epoch: actor.connection_epoch,
            id: 7,
            input_muted: None,
            output_muted: None,
            away: None,
            away_message: None,
            server_groups: vec!["6".into(), "7".into(), "8".into()],
        })
        .await;
    assert_eq!(actor.channel_list_allowed, None);
    assert_eq!(actor.channel_meta_allowed, None);
    assert_eq!(actor.client_list_allowed, None);

    // 3. DirectorySnapshot 检测到自身 server_groups 变化时也重置。
    actor.channel_list_allowed = Some(false);
    actor.channel_meta_allowed = Some(false);
    actor.client_list_allowed = Some(false);
    actor
        .handle_signal(SessionSignal::Snapshot {
            epoch: actor.connection_epoch,
            snapshot: tsclient_rs::DirectorySnapshot {
                channels: Vec::new(),
                clients: vec![ClientInfo {
                    server_groups: vec!["6".into()],
                    ..client_info(7, 9, "Self")
                }],
                truncated: false,
            },
        })
        .await;
    assert_eq!(actor.channel_list_allowed, None);
    assert_eq!(actor.channel_meta_allowed, None);
    assert_eq!(actor.client_list_allowed, None);

    // 4. RequestSnapshot 命令重置权限标志。
    actor.channel_list_allowed = Some(false);
    actor.channel_meta_allowed = Some(false);
    actor.client_list_allowed = Some(false);
    let (reply, rx) = oneshot::channel();
    assert!(
        actor
            .handle(SessionCommand::RequestSnapshot { reply })
            .await
    );
    assert!(rx.await.unwrap().is_ok());
    assert_eq!(actor.channel_list_allowed, None);
    assert_eq!(actor.channel_meta_allowed, None);
    assert_eq!(actor.client_list_allowed, None);
}
