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
