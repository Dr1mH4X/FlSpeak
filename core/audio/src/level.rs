//! 低频电平聚合：音频线程只把 0–1 的响度送给界面。
//!
//! 语音样本本身仍然不跨 FFI；这里输出的是给电平条用的轻量指标，按
//! [`METER_INTERVAL`] 节流。dB 映射让轻声也有可见高度，噪声门压掉底噪。

#[cfg(any(feature = "audio", test))]
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::time::{Duration, Instant};

/// 聚合电平每 20ms 发布一次，音频样本不随事件传输。
pub const METER_INTERVAL: Duration = Duration::from_millis(20);

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct LevelReading {
    pub connection_epoch: u64,
    pub mic: f32,
    pub received: f32,
}

/// capture 是麦克风电平的唯一写入者；代次在电平之后发布。
#[cfg(any(feature = "audio", test))]
#[derive(Default)]
pub(crate) struct SharedMeter {
    epoch: AtomicU64,
    mic_epoch: AtomicU64,
    mic: AtomicU32,
}

#[cfg(any(feature = "audio", test))]
impl SharedMeter {
    pub fn set_epoch(&self, epoch: Option<u64>) {
        let next = epoch.unwrap_or(0);
        if self.epoch.swap(next, Ordering::AcqRel) != next {
            self.clear_mic();
        }
    }

    pub fn epoch(&self) -> u64 {
        self.epoch.load(Ordering::Acquire)
    }

    pub fn clear_mic(&self) {
        self.mic_epoch.store(0, Ordering::Release);
    }

    pub fn store_mic(&self, epoch: u64, level: f32) {
        self.mic
            .store(level.clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
        self.mic_epoch.store(epoch, Ordering::Release);
    }

    pub fn reading(&self, epoch: u64, received: f32) -> Option<LevelReading> {
        if epoch == 0 || self.epoch() != epoch {
            return None;
        }
        let mic = if self.mic_epoch.load(Ordering::Acquire) == epoch {
            f32::from_bits(self.mic.load(Ordering::Relaxed))
        } else {
            0.0
        };
        (self.epoch() == epoch).then_some(LevelReading {
            connection_epoch: epoch,
            mic,
            received,
        })
    }
}

const FLOOR_DB: f32 = -60.0;
const NOISE_GATE: f32 = 0.05;

/// 一段交织样本的 RMS。
pub fn rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum: f32 = samples.iter().map(|sample| sample * sample).sum();
    (sum / samples.len() as f32).sqrt()
}

/// RMS → 0–1。-60dB 以下归零，-60–0dB 映射到 0–1。
pub fn level_from_rms(rms: f32) -> f32 {
    if !rms.is_finite() || rms <= 0.0 {
        return 0.0;
    }
    let db = 20.0 * rms.log10();
    let normalized = ((db - FLOOR_DB) / -FLOOR_DB).clamp(0.0, 1.0);
    if normalized <= NOISE_GATE {
        return 0.0;
    }
    ((normalized - NOISE_GATE) / (1.0 - NOISE_GATE)).clamp(0.0, 1.0)
}

/// 按 [`METER_INTERVAL`] 放行事件；首次调用立即放行。
#[derive(Debug, Default)]
pub struct MeterClock {
    next: Option<Instant>,
}

impl MeterClock {
    pub fn due(&mut self, now: Instant) -> bool {
        let deadline = self.next.unwrap_or(now);
        if now < deadline {
            return false;
        }
        let next = deadline + METER_INTERVAL;
        // 保持节拍，线程被延后时只报告最新值，不补发过期读数。
        self.next = Some(if next > now {
            next
        } else {
            now + METER_INTERVAL
        });
        true
    }
}

/// 一阶平滑：上升快、回落慢，电平条不会跟着每个采样抖。
#[derive(Debug, Default)]
pub struct LevelMeter {
    level: f32,
}

impl LevelMeter {
    pub fn update(&mut self, rms: f32) -> f32 {
        let target = level_from_rms(rms);
        let coefficient = if target > self.level { 0.85 } else { 0.22 };
        self.level += (target - self.level) * coefficient;
        self.level = self.level.clamp(0.0, 1.0);
        self.level
    }

    pub fn silence(&mut self) -> f32 {
        self.level = 0.0;
        0.0
    }

    pub fn level(&self) -> f32 {
        self.level
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_new_meter_epoch_requires_fresh_capture_and_playback() {
        let meter = SharedMeter::default();
        meter.set_epoch(Some(1));
        meter.store_mic(1, 0.9);
        assert_eq!(meter.reading(1, 0.4).unwrap().mic, 0.9);
        meter.set_epoch(None);
        assert!(meter.reading(1, 0.4).is_none());
        meter.set_epoch(Some(2));
        assert!(meter.reading(1, 0.4).is_none());
        assert_eq!(meter.reading(2, 0.0).unwrap().mic, 0.0);
        meter.store_mic(1, 0.8);
        assert_eq!(meter.reading(2, 0.0).unwrap().mic, 0.0);
        meter.store_mic(2, 0.3);
        assert_eq!(meter.reading(2, 0.0).unwrap().mic, 0.3);
        meter.clear_mic();
        assert_eq!(meter.reading(2, 0.0).unwrap().mic, 0.0);
    }

    #[test]
    fn empty_and_dc_free_rms() {
        assert_eq!(rms(&[]), 0.0);
        assert!((rms(&[0.5, -0.5]) - 0.5).abs() < 1e-6);
        assert_eq!(rms(&[0.0, 0.0]), 0.0);
    }

    #[test]
    fn level_mapping_uses_db_window_and_gate() {
        assert_eq!(level_from_rms(0.0), 0.0);
        // -60dB 落在门限以下。
        assert_eq!(level_from_rms(0.001), 0.0);
        // -40dB 约为 0.3，-20dB 约为 0.65，满幅为 1。
        let quiet = level_from_rms(0.01);
        let loud = level_from_rms(0.1);
        assert!((0.2..0.4).contains(&quiet));
        assert!((0.55..0.75).contains(&loud));
        assert_eq!(level_from_rms(1.0), 1.0);
    }

    #[test]
    fn meter_rises_faster_than_it_falls() {
        let mut meter = LevelMeter::default();
        let attack = meter.update(0.1);
        let release = meter.update(0.0);
        assert!(attack >= level_from_rms(0.1) * 0.8);
        assert!(release > 0.0);
        assert!(release < attack);
        assert_eq!(meter.silence(), 0.0);
    }

    #[test]
    fn clock_limits_events_to_fifty_hertz() {
        let mut clock = MeterClock::default();
        let start = Instant::now();
        assert!(clock.due(start));
        assert!(!clock.due(start + Duration::from_millis(19)));
        assert!(clock.due(start + METER_INTERVAL));
    }

    #[test]
    fn clock_keeps_phase_despite_tick_jitter() {
        let mut clock = MeterClock::default();
        let start = Instant::now();
        assert!(clock.due(start));
        assert!(!clock.due(start + Duration::from_millis(11)));
        assert!(clock.due(start + Duration::from_millis(21)));
        assert!(!clock.due(start + Duration::from_millis(31)));
        assert!(clock.due(start + Duration::from_millis(40)));
    }

    #[test]
    fn clock_does_not_replay_missed_ticks() {
        let mut clock = MeterClock::default();
        let start = Instant::now();
        assert!(clock.due(start));
        assert!(clock.due(start + Duration::from_millis(205)));
        assert!(!clock.due(start + Duration::from_millis(205)));
        assert!(!clock.due(start + Duration::from_millis(215)));
        assert!(clock.due(start + Duration::from_millis(225)));
    }
}
