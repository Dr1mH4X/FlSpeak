//! 语音活动检测。
//!
//! v1 用能量 VAD：对机械键盘之类的瞬态噪声会误触发，但胜在没有额外依赖、行为可预测。
//! 采集线程只依赖 [`Vad`] trait，将来换 RNNoise/Speex 只需要替换实现。

use crate::format::FRAME_MS;

/// 归一化平均振幅阈值。TeamSpeakClaw 的同类实现用 0.015；这里略保守。
pub const DEFAULT_THRESHOLD: f32 = 0.012;
/// 说话结束后继续发送的尾音，避免最后一个音节被切掉。
pub const DEFAULT_HANGOVER_MS: u64 = 250;

pub trait Vad {
    /// 判断这一帧是否包含语音。
    fn is_speech(&mut self, frame: &[f32]) -> bool;
    fn reset(&mut self);
}

pub struct EnergyVad {
    threshold: f32,
    hangover_frames: u32,
    remaining: u32,
}

impl EnergyVad {
    pub fn new(threshold: f32, hangover_ms: u64) -> Self {
        Self {
            threshold: threshold.max(0.0),
            hangover_frames: (hangover_ms / FRAME_MS).max(1) as u32,
            remaining: 0,
        }
    }

    pub fn threshold(&self) -> f32 {
        self.threshold
    }
}

impl Default for EnergyVad {
    fn default() -> Self {
        Self::new(DEFAULT_THRESHOLD, DEFAULT_HANGOVER_MS)
    }
}

impl Vad for EnergyVad {
    fn is_speech(&mut self, frame: &[f32]) -> bool {
        if frame.is_empty() {
            return false;
        }
        let energy = frame.iter().map(|sample| sample.abs()).sum::<f32>() / frame.len() as f32;
        if energy >= self.threshold {
            self.remaining = self.hangover_frames;
            true
        } else if self.remaining > 0 {
            self.remaining -= 1;
            true
        } else {
            false
        }
    }

    fn reset(&mut self) {
        self.remaining = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn loud() -> Vec<f32> {
        vec![0.2; 960]
    }

    fn quiet() -> Vec<f32> {
        vec![0.0; 960]
    }

    #[test]
    fn detects_loud_frames_and_hangs_over() {
        let mut vad = EnergyVad::new(0.01, 40); // 2 帧尾音
        assert!(vad.is_speech(&loud()));
        assert!(vad.is_speech(&quiet()));
        assert!(vad.is_speech(&quiet()));
        assert!(!vad.is_speech(&quiet()));
    }

    #[test]
    fn resets_cleanly() {
        let mut vad = EnergyVad::new(0.01, 100);
        assert!(vad.is_speech(&loud()));
        vad.reset();
        assert!(!vad.is_speech(&quiet()));
    }

    #[test]
    fn empty_frame_is_not_speech() {
        let mut vad = EnergyVad::default();
        assert!(!vad.is_speech(&[]));
    }
}
