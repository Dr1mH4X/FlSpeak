use super::*;

const NETWORK_SAMPLE_ERROR_LOG_INTERVAL: Duration = Duration::from_secs(30);

impl Actor {
    pub(super) fn record_network_probe(&mut self, started: Instant, reached: bool) {
        let round_trip = self.client.as_ref().and_then(|client| client.round_trip());
        let packet_loss = self.client.as_ref().and_then(|client| client.packet_loss());
        if let Some(monitor) = &mut self.network_monitor {
            monitor.apply_round_trip(round_trip);
            monitor.apply_packet_loss(packet_loss);
            let round_trip_ms = reached.then(|| started.elapsed().as_secs_f64() * 1_000.0);
            let telemetry = monitor.record(round_trip_ms, now_millis());
            self.emit(SessionEvent::Network(telemetry));
        }
    }

    /// 遥测面板打开时按需查询自身连接统计。命令写入仍在 actor 内串行执行，
    /// 只等 `send_command_no_wait` 完成，不等待服务器回包；回包通过
    /// `notifyconnectioninfo` 回到信号队列。
    pub(super) async fn sample_network(&mut self) -> Result<(), SessionError> {
        let client = self.connected()?;
        let client_id = self.self_client_id.ok_or(SessionError::NotConnected)?;
        let result = client
            .send_command_no_wait(&format!("getconnectioninfo clid={client_id}"))
            .await
            .map_err(protocol_error);
        match &result {
            Ok(()) => self.last_network_sample_error = None,
            Err(error) => {
                let now = Instant::now();
                let should_log = self.last_network_sample_error.is_none_or(|last| {
                    now.duration_since(last) >= NETWORK_SAMPLE_ERROR_LOG_INTERVAL
                });
                if should_log {
                    self.last_network_sample_error = Some(now);
                    self.emit(SessionEvent::Log {
                        level: "warn".into(),
                        message: format!("网络遥测查询失败: {error}"),
                    });
                }
            }
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::test_support::*;

    struct RefusedDirectory {
        calls: Arc<std::sync::Mutex<Vec<String>>>,
    }

    impl tsclient_rs::CommandMiddleware for RefusedDirectory {
        fn wrap(&self, _: TestCommandHandler) -> TestCommandHandler {
            let calls = Arc::clone(&self.calls);
            Arc::new(move |command| {
                calls.lock().unwrap().push(command);
                Box::pin(async {
                    Err(tsclient_rs::Error::ServerError {
                        id: "2568".into(),
                        server_message: "insufficient client permissions".into(),
                        extra_message: None,
                    })
                })
            })
        }
    }

    #[tokio::test]
    async fn telemetry_only_samples_existing_directory_requests() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let calls = Arc::new(std::sync::Mutex::new(Vec::new()));
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(RefusedDirectory {
                            calls: Arc::clone(&calls),
                        })],
                        ..Default::default()
                    },
                );
                client.mark_connected();
                let mut actor = audio_actor();
                actor.client = Some(Arc::new(client));
                actor.state = SessionState::Connected {
                    client_id: 1,
                    channel_id: 1,
                };
                actor.network_monitor = Some(crate::network::NetworkMonitor::new());
                let mut events = actor.events.subscribe();
                let (commands, receiver) = mpsc::unbounded_channel();
                let task = tokio::task::spawn_local(async move {
                    actor.run(receiver).await;
                });
                tokio::time::sleep(Duration::from_millis(5_100)).await;
                let idle_calls = calls.lock().unwrap().clone();
                let (reply, result) = oneshot::channel();
                commands
                    .send(SessionCommand::ListChannels { reply })
                    .unwrap();
                assert!(result.await.unwrap().is_err());
                let telemetry = loop {
                    if let SessionEvent::Network(telemetry) = events.recv().await.unwrap() {
                        break telemetry;
                    }
                };
                let directory_calls = calls.lock().unwrap().clone();
                commands.send(SessionCommand::Shutdown).unwrap();
                task.await.unwrap();
                assert!(idle_calls.is_empty());
                assert_eq!(directory_calls.len(), 1);
                assert!(directory_calls[0].starts_with("channellist "));
                assert_eq!(telemetry.probes_sent, 1);
                assert_eq!(telemetry.probes_failed, 0);
                assert!(telemetry.round_trip_ms.is_some());
            })
            .await;
    }

    #[tokio::test]
    async fn network_sampling_sends_through_the_actor_queue() {
        tokio::task::LocalSet::new()
            .run_until(async {
                let calls = Arc::new(std::sync::Mutex::new(Vec::new()));
                let client = Client::new(
                    tsclient_rs::generateIdentity(0),
                    "127.0.0.1:9987".into(),
                    "test".into(),
                    tsclient_rs::ClientOptions {
                        command_middleware: vec![Box::new(RefusedDirectory {
                            calls: Arc::clone(&calls),
                        })],
                        ..Default::default()
                    },
                );
                client.mark_connected();
                let mut actor = audio_actor();
                actor.client = Some(Arc::new(client));
                actor.self_client_id = Some(7);
                let (commands, receiver) = mpsc::unbounded_channel();
                let task = tokio::task::spawn_local(async move {
                    actor.run(receiver).await;
                });

                let (reply, result) = oneshot::channel();
                commands
                    .send(SessionCommand::SampleNetwork { reply })
                    .unwrap();
                assert!(result.await.unwrap().is_err());
                assert_eq!(
                    calls.lock().unwrap().last().map(String::as_str),
                    Some("getconnectioninfo clid=7")
                );

                commands.send(SessionCommand::Shutdown).unwrap();
                task.await.unwrap();
            })
            .await;
    }
}
