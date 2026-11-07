use std::collections::{HashMap, VecDeque};
use std::time::Instant;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct NetworkTelemetry {
    pub round_trip_ms: Option<f64>,
    pub jitter_ms: Option<f64>,
    pub recent_failure_percent: f64,
    pub probes_sent: u64,
    pub probes_failed: u64,
    pub connected_seconds: u64,
    /// 服务器统计的空闲时长；客户端从未上报时为 `None`。
    pub idle_seconds: Option<u64>,
    /// 服务器到客户端的丢包百分比；服务器未提供时为 `None`。
    pub loss_in_percent: Option<f64>,
    /// 客户端到服务器的丢包百分比；服务器未提供时为 `None`。
    pub loss_out_percent: Option<f64>,
    pub sampled_at: u64,
}

/// `getconnectioninfo` 返回的连接统计。它比目录探测更接近协议层，
/// 但部分字段依赖服务器能力，缺失时保留 `None`。
#[derive(Debug, Clone, Default)]
struct ConnectionStats {
    ping_ms: Option<f64>,
    jitter_ms: Option<f64>,
    connected_seconds: Option<u64>,
    idle_seconds: Option<u64>,
    loss_in_percent: Option<f64>,
    loss_out_percent: Option<f64>,
}

pub(crate) struct NetworkMonitor {
    connected_at: Instant,
    recent: VecDeque<Option<f64>>,
    probes_sent: u64,
    probes_failed: u64,
    connection: ConnectionStats,
}

impl NetworkMonitor {
    pub(crate) fn new() -> Self {
        Self {
            connected_at: Instant::now(),
            recent: VecDeque::new(),
            probes_sent: 0,
            probes_failed: 0,
            connection: ConnectionStats::default(),
        }
    }

    /// 用服务器返回的 `notifyconnectioninfo` 字段刷新权威统计。
    pub(crate) fn apply_connection_info(&mut self, params: &HashMap<String, String>) {
        let next = ConnectionStats {
            ping_ms: parse_f64(params, "connection_ping"),
            jitter_ms: parse_f64(params, "connection_ping_deviation"),
            connected_seconds: parse_millis_seconds(params, "connection_connected_time"),
            idle_seconds: parse_millis_seconds(params, "connection_idle_time"),
            loss_in_percent: parse_fraction_percent(
                params,
                "connection_server2client_packetloss_total",
            ),
            loss_out_percent: parse_fraction_percent(
                params,
                "connection_client2server_packetloss_total",
            ),
        };
        // 不同服务器版本返回的字段并不齐全；缺字段时保留上一轮已知值。
        self.connection = ConnectionStats {
            ping_ms: next.ping_ms.or(self.connection.ping_ms),
            jitter_ms: next.jitter_ms.or(self.connection.jitter_ms),
            connected_seconds: next.connected_seconds.or(self.connection.connected_seconds),
            idle_seconds: next.idle_seconds.or(self.connection.idle_seconds),
            loss_in_percent: next.loss_in_percent.or(self.connection.loss_in_percent),
            loss_out_percent: next.loss_out_percent.or(self.connection.loss_out_percent),
        };
    }

    pub(crate) fn connection_ping(&self) -> Option<f64> {
        self.connection
            .ping_ms
            .or_else(|| self.recent.back().copied().flatten())
    }

    pub(crate) fn connection_jitter(&self) -> Option<f64> {
        self.connection.jitter_ms.or_else(|| jitter(&self.recent))
    }

    pub(crate) fn record(
        &mut self,
        round_trip_ms: Option<f64>,
        sampled_at: u64,
    ) -> NetworkTelemetry {
        self.probes_sent += 1;
        self.probes_failed += u64::from(round_trip_ms.is_none());
        self.recent.push_back(round_trip_ms);
        if self.recent.len() > 10 {
            self.recent.pop_front();
        }
        self.snapshot_with(sampled_at, round_trip_ms)
    }

    /// 不新增探测，只读取当前已知的连接统计。
    pub(crate) fn snapshot(&self, sampled_at: u64) -> NetworkTelemetry {
        self.snapshot_with(sampled_at, self.connection_ping())
    }

    fn snapshot_with(&self, sampled_at: u64, probe_ms: Option<f64>) -> NetworkTelemetry {
        let failures = self.recent.iter().filter(|sample| sample.is_none()).count();
        NetworkTelemetry {
            // 协议层 ping 是权威值；目录探测只在前者缺失时兜底。
            round_trip_ms: self.connection.ping_ms.or(probe_ms),
            jitter_ms: self.connection_jitter(),
            recent_failure_percent: if self.recent.is_empty() {
                0.0
            } else {
                failures as f64 * 100.0 / self.recent.len() as f64
            },
            probes_sent: self.probes_sent,
            probes_failed: self.probes_failed,
            connected_seconds: self
                .connection
                .connected_seconds
                .unwrap_or_else(|| self.connected_at.elapsed().as_secs()),
            idle_seconds: self.connection.idle_seconds,
            loss_in_percent: self.connection.loss_in_percent,
            loss_out_percent: self.connection.loss_out_percent,
            sampled_at,
        }
    }
}

fn parse_f64(params: &HashMap<String, String>, key: &str) -> Option<f64> {
    params
        .get(key)?
        .parse::<f64>()
        .ok()
        .filter(|value| value.is_finite())
}

/// 服务器把连接时长和空闲时长都按毫秒返回。
fn parse_millis_seconds(params: &HashMap<String, String>, key: &str) -> Option<u64> {
    parse_f64(params, key).map(|millis| (millis / 1_000.0).round() as u64)
}

/// `notifyconnectioninfo` 的丢包字段是 0–1 的比例，界面按百分比显示。
fn parse_fraction_percent(params: &HashMap<String, String>, key: &str) -> Option<f64> {
    parse_f64(params, key).map(|fraction| (fraction * 100.0).clamp(0.0, 100.0))
}

fn jitter(recent: &VecDeque<Option<f64>>) -> Option<f64> {
    let samples: Vec<f64> = recent.iter().filter_map(|sample| *sample).collect();
    (samples.len() > 1).then(|| {
        samples
            .windows(2)
            .map(|pair| (pair[1] - pair[0]).abs())
            .sum::<f64>()
            / (samples.len() - 1) as f64
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failed_probes_are_not_zero_latency_and_old_failures_leave_the_window() {
        let mut monitor = NetworkMonitor::new();
        let first = monitor.record(Some(20.0), 1);
        assert_eq!(first.jitter_ms, None);
        let second = monitor.record(Some(40.0), 2);
        assert_eq!(second.jitter_ms, Some(20.0));
        let failed = monitor.record(None, 3);
        assert_eq!(failed.round_trip_ms, None);
        assert_eq!(failed.probes_failed, 1);
        assert!(failed.recent_failure_percent > 33.0);
        for timestamp in 4..14 {
            monitor.record(Some(25.0), timestamp);
        }
        let recovered = monitor.record(Some(25.0), 14);
        assert_eq!(recovered.recent_failure_percent, 0.0);
        assert_eq!(recovered.probes_failed, 1);
        assert_eq!(recovered.probes_sent, 14);
    }

    #[test]
    fn server_connection_info_adds_loss_idle_and_ping_without_erasing_probe_history() {
        let mut monitor = NetworkMonitor::new();
        monitor.record(Some(40.0), 1);
        monitor.apply_connection_info(&HashMap::from([
            ("connection_ping".into(), "44.5".into()),
            ("connection_ping_deviation".into(), "1.5".into()),
            ("connection_connected_time".into(), "65000".into()),
            ("connection_idle_time".into(), "3725000".into()),
            (
                "connection_server2client_packetloss_total".into(),
                "0.005".into(),
            ),
            (
                "connection_client2server_packetloss_total".into(),
                "0.01".into(),
            ),
        ]));

        let telemetry = monitor.snapshot(2);
        assert_eq!(telemetry.round_trip_ms, Some(44.5));
        assert_eq!(telemetry.jitter_ms, Some(1.5));
        assert_eq!(telemetry.loss_in_percent, Some(0.5));
        assert_eq!(telemetry.loss_out_percent, Some(1.0));
        assert_eq!(telemetry.idle_seconds, Some(3_725));
        assert_eq!(telemetry.connected_seconds, 65);
        assert_eq!(telemetry.probes_sent, 1);
        assert_eq!(telemetry.probes_failed, 0);
    }

    #[test]
    fn non_finite_connection_info_is_rejected() {
        for value in ["NaN", "inf", "-inf"] {
            let mut monitor = NetworkMonitor::new();
            monitor.apply_connection_info(&HashMap::from([
                ("connection_ping".into(), value.into()),
                ("connection_ping_deviation".into(), value.into()),
                ("connection_connected_time".into(), value.into()),
                ("connection_idle_time".into(), value.into()),
                (
                    "connection_server2client_packetloss_total".into(),
                    value.into(),
                ),
                (
                    "connection_client2server_packetloss_total".into(),
                    value.into(),
                ),
            ]));

            let telemetry = monitor.snapshot(1);
            assert_eq!(telemetry.round_trip_ms, None);
            assert_eq!(telemetry.jitter_ms, None);
            assert_eq!(telemetry.idle_seconds, None);
            assert_eq!(telemetry.loss_in_percent, None);
            assert_eq!(telemetry.loss_out_percent, None);
        }
    }

    #[test]
    fn protocol_ping_wins_over_the_directory_probe() {
        let mut monitor = NetworkMonitor::new();
        monitor.apply_connection_info(&HashMap::from([("connection_ping".into(), "44.5".into())]));

        let telemetry = monitor.record(Some(80.0), 1);
        assert_eq!(telemetry.round_trip_ms, Some(44.5));
        assert_eq!(telemetry.recent_failure_percent, 0.0);

        let mut fallback = NetworkMonitor::new();
        let telemetry = fallback.record(Some(80.0), 1);
        assert_eq!(telemetry.round_trip_ms, Some(80.0));
    }

    #[test]
    fn missing_connection_info_fields_stay_unknown() {
        let mut monitor = NetworkMonitor::new();
        monitor.apply_connection_info(&HashMap::from([(
            "connection_ping".into(),
            "not-a-number".into(),
        )]));

        let telemetry = monitor.snapshot(1);
        assert_eq!(telemetry.round_trip_ms, None);
        assert_eq!(telemetry.loss_in_percent, None);
        assert_eq!(telemetry.loss_out_percent, None);
        assert_eq!(telemetry.idle_seconds, None);
    }
}
