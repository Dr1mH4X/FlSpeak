use super::*;
use crate::actor::test_support::*;

struct SlowImage {
    started: Arc<tokio::sync::Notify>,
    calls: Arc<std::sync::atomic::AtomicUsize>,
}

impl tsclient_rs::CommandMiddleware for SlowImage {
    fn wrap(&self, _: TestCommandHandler) -> TestCommandHandler {
        let started = Arc::clone(&self.started);
        let calls = Arc::clone(&self.calls);
        Arc::new(move |command| {
            let started = Arc::clone(&started);
            let calls = Arc::clone(&calls);
            Box::pin(async move {
                if command.starts_with("ftinitdownload ") {
                    calls.fetch_add(1, Ordering::SeqCst);
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
async fn load_self_avatar_snapshot_command_reads_the_store() {
    const PNG: [u8; 16] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
        0x52,
    ];

    tokio::task::LocalSet::new()
        .run_until(async {
            let temp = std::env::temp_dir().join(format!(
                "flspeak-self-avatar-command-{:x}",
                rand::random::<u64>()
            ));
            let _ = std::fs::create_dir_all(&temp);
            let store_path = temp.join("preferences.json");
            crate::media::save_self_avatar_snapshot(&store_path, &PNG).unwrap();

            let mut actor = audio_actor();
            actor.store_path = store_path;
            let (commands, rx) = mpsc::unbounded_channel();
            let task = tokio::task::spawn_local(async move {
                actor.run(rx).await;
            });

            let (reply, result) = oneshot::channel();
            commands
                .send(SessionCommand::LoadSelfAvatarSnapshot { reply })
                .unwrap();
            assert_eq!(result.await.unwrap().unwrap(), Some(PNG.to_vec()));

            commands.send(SessionCommand::Shutdown).unwrap();
            task.await.unwrap();

            let _ = std::fs::remove_dir_all(&temp);
        })
        .await;
}

#[tokio::test]
async fn avatar_negotiation_keeps_audio_and_controls_responsive() {
    tokio::task::LocalSet::new()
        .run_until(async {
            let started = Arc::new(tokio::sync::Notify::new());
            let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
            let client = Client::new(
                tsclient_rs::generateIdentity(0),
                "127.0.0.1:9987".into(),
                "test".into(),
                tsclient_rs::ClientOptions {
                    command_middleware: vec![Box::new(SlowImage {
                        started: Arc::clone(&started),
                        calls: Arc::clone(&calls),
                    })],
                    ..Default::default()
                },
            );
            client.mark_connected();
            let mut actor = audio_actor();
            actor.active_server_id = Some("127.0.0.1:9987".into());
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
            // 控制命令优先抢占正在进行的图片协商，Rust 在 500ms 后自动重试直至收到服务端 2568 负缓存响应。
            assert_eq!(result.await.unwrap().unwrap(), None);
            assert_eq!(calls.load(Ordering::SeqCst), 2);
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
    let now = Instant::now();
    actor.open_protocol.on_connected(7, 5, now);
    actor.handle_open_protocol_command(PluginCommandEvent {
        name: tsclient_rs::open_protocol::IDENTITY_PLUGIN.into(),
        data: r#"{"v":1,"action":"announce_ack","client_type":"bot","app_name":"Bot","app_version":"1.0","capabilities":["chat:slash_commands"]}"#.into(),
        invoker_id: 12,
        invoker_name: "Bot".into(),
        invoker_uid: "bot-uid".into(),
    });
    actor.handle_open_protocol_command(PluginCommandEvent {
        name: tsclient_rs::open_protocol::COMMANDS_PLUGIN.into(),
        data: r#"{"v":1,"action":"list_ack","command_prefix":"!","commands":[{"name":"replay","desc":"Replay"}]}"#.into(),
        invoker_id: 12,
        invoker_name: "Bot".into(),
        invoker_uid: "bot-uid".into(),
    });
    assert!(actor.open_protocol.peer_identity("bot-uid").is_some());
    assert!(actor.open_protocol.peer_commands("bot-uid").is_some());

    let prev_epoch = actor.connection_epoch;
    actor.invalidate_handlers();

    assert!(actor.open_protocol.peer_identity("bot-uid").is_none());
    assert!(actor.open_protocol.peer_commands("bot-uid").is_none());
    assert!(actor.open_protocol.self_client_id().is_none());
    assert_eq!(actor.open_protocol.self_channel_id(), 0);
    assert_eq!(actor.connection_epoch, prev_epoch + 1);
    assert!(actor.directory.channel_list_allowed().is_none());
    assert!(actor.directory.channel_meta_allowed().is_none());
    assert!(actor.directory.client_list_allowed().is_none());
    assert!(!actor.directory.subscribed_all_channels());
    assert!(actor.directory.self_server_groups().is_empty());
}

#[tokio::test]
async fn dynamic_reset_triggers_clear_permission_flags() {
    let mut actor = audio_actor();
    actor.self_client_id = Some(7);
    actor.self_channel_id = 5;
    actor.directory.set_self_server_groups(&["6".into()]);

    // 1. 切换频道重置权限标志。
    actor.directory.set_channel_list_allowed(false);
    actor.directory.set_channel_meta_allowed(false);
    actor.directory.set_client_list_allowed(false);
    actor.on_self_moved(9).await;
    assert_eq!(actor.directory.channel_list_allowed(), None);
    assert_eq!(actor.directory.channel_meta_allowed(), None);
    assert_eq!(actor.directory.client_list_allowed(), None);

    // 2. ClientUpdated 服务器组不变时不重置；变化时重置（顺序不同但集合相同也不重置）。
    actor.directory.set_channel_list_allowed(false);
    actor.directory.set_channel_meta_allowed(false);
    actor.directory.set_client_list_allowed(false);
    actor
        .directory
        .set_self_server_groups(&["6".into(), "8".into()]);
    actor
        .handle_signal(SessionSignal::ClientUpdated {
            epoch: actor.connection_epoch,
            id: 7,
            uid: String::new(),
            channel_id: 0,
            input_muted: None,
            output_muted: None,
            away: None,
            away_message: None,
            server_groups: vec!["8".into(), "6".into()],
            avatar_hash: None,
        })
        .await;
    assert_eq!(actor.directory.channel_list_allowed(), Some(false));

    actor
        .handle_signal(SessionSignal::ClientUpdated {
            epoch: actor.connection_epoch,
            id: 7,
            uid: String::new(),
            channel_id: 0,
            input_muted: None,
            output_muted: None,
            away: None,
            away_message: None,
            server_groups: vec!["6".into(), "7".into(), "8".into()],
            avatar_hash: None,
        })
        .await;
    assert_eq!(actor.directory.channel_list_allowed(), None);
    assert_eq!(actor.directory.channel_meta_allowed(), None);
    assert_eq!(actor.directory.client_list_allowed(), None);

    // 3. DirectorySnapshot 检测到自身 server_groups 变化时也重置。
    actor.directory.set_channel_list_allowed(false);
    actor.directory.set_channel_meta_allowed(false);
    actor.directory.set_client_list_allowed(false);
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
    assert_eq!(actor.directory.channel_list_allowed(), None);
    assert_eq!(actor.directory.channel_meta_allowed(), None);
    assert_eq!(actor.directory.client_list_allowed(), None);

    // 4. RequestSnapshot 命令重置权限标志。
    actor.directory.set_channel_list_allowed(false);
    actor.directory.set_channel_meta_allowed(false);
    actor.directory.set_client_list_allowed(false);
    let (reply, rx) = oneshot::channel();
    assert!(
        actor
            .handle(SessionCommand::RequestSnapshot { reply })
            .await
    );
    assert!(rx.await.unwrap().is_ok());
    assert_eq!(actor.directory.channel_list_allowed(), None);
    assert_eq!(actor.directory.channel_meta_allowed(), None);
    assert_eq!(actor.directory.client_list_allowed(), None);
}

struct SlowDirectory(Arc<tokio::sync::Notify>);

impl tsclient_rs::CommandMiddleware for SlowDirectory {
    fn wrap(&self, _: TestCommandHandler) -> TestCommandHandler {
        let started = Arc::clone(&self.0);
        Arc::new(move |command| {
            let started = Arc::clone(&started);
            Box::pin(async move {
                if command.starts_with("channellist") {
                    started.notify_one();
                    tokio::time::sleep(Duration::from_millis(250)).await;
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
async fn outbound_voice_is_not_blocked_by_slow_actor_commands() {
    tokio::task::LocalSet::new()
        .run_until(async {
            let started = Arc::new(tokio::sync::Notify::new());
            let client = Client::new(
                tsclient_rs::generateIdentity(0),
                "127.0.0.1:9987".into(),
                "test".into(),
                tsclient_rs::ClientOptions {
                    command_middleware: vec![Box::new(SlowDirectory(Arc::clone(&started)))],
                    ..Default::default()
                },
            );
            client.mark_connected();
            let mut actor = audio_actor();
            actor.active_server_id = Some("127.0.0.1:9987".into());
            actor.client = Some(Arc::new(client));
            actor.state = SessionState::Connected {
                client_id: 1,
                channel_id: 1,
            };
            actor.self_channel_id = 1;
            actor.capture_active = true;
            // 容量为 1：若 audio_events 在慢命令期间不被消费，连续发送 4 个包必然超时阻塞。
            let (audio, audio_rx) = mpsc::channel(1);
            actor.audio_events = audio_rx;
            let (commands, rx) = mpsc::unbounded_channel();
            let task = tokio::task::spawn_local(async move {
                actor.run(rx).await;
            });

            let (reply, mut list_rx) = oneshot::channel();
            commands
                .send(SessionCommand::ListChannels { reply })
                .unwrap();
            started.notified().await;

            for _ in 0..4 {
                tokio::time::timeout(
                    Duration::from_millis(50),
                    audio.send(AudioEvent::Outbound {
                        codec: VOICE_CODEC,
                        data: vec![1, 2, 3, 4],
                        produced_at: Instant::now(),
                    }),
                )
                .await
                .expect("sending audio packets should not be blocked by a slow command")
                .unwrap();
            }
            // 此时 ListChannels 仍在阻塞中，证明音频发包真正绕开了慢等待。
            assert!(matches!(
                list_rx.try_recv(),
                Err(oneshot::error::TryRecvError::Empty)
            ));

            commands.send(SessionCommand::Shutdown).unwrap();
            task.await.unwrap();
        })
        .await;
}
