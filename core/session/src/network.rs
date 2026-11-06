use std::collections::VecDeque;
use std::time::Instant;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct NetworkTelemetry {
    pub round_trip_ms: Option<f64>,
    pub jitter_ms: Option<f64>,
    pub recent_failure_percent: f64,
    pub probes_sent: u64,
    pub probes_failed: u64,
    pub connected_seconds: u64,
    pub sampled_at: u64,
}

pub(crate) struct NetworkMonitor {
    connected_at: Instant,
    recent: VecDeque<Option<f64>>,
    probes_sent: u64,
    probes_failed: u64,
}

impl NetworkMonitor {
    pub(crate) fn new() -> Self {
        Self {
            connected_at: Instant::now(),
            recent: VecDeque::new(),
            probes_sent: 0,
            probes_failed: 0,
        }
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
        let samples: Vec<f64> = self.recent.iter().filter_map(|sample| *sample).collect();
        let jitter_ms = (samples.len() > 1).then(|| {
            samples
                .windows(2)
                .map(|pair| (pair[1] - pair[0]).abs())
                .sum::<f64>()
                / (samples.len() - 1) as f64
        });
        let failures = self.recent.iter().filter(|sample| sample.is_none()).count();
        NetworkTelemetry {
            round_trip_ms,
            jitter_ms,
            recent_failure_percent: failures as f64 * 100.0 / self.recent.len() as f64,
            probes_sent: self.probes_sent,
            probes_failed: self.probes_failed,
            connected_seconds: self.connected_at.elapsed().as_secs(),
            sampled_at,
        }
    }
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
}
