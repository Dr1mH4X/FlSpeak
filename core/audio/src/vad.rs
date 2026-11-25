//! 能量 VAD：按阈值与挂起帧数判定发言，`Vad` 是采集线程唯一依赖的抽象。

use crate::format::FRAME_MS;

/// 归一化平均振幅阈值。TeamSpeakClaw 的同类实现用 0.015；这里略保守。
pub const DEFAULT_THRESHOLD: f32 = 0.012;
/// 说话结束后继续发送的尾音，避免最后一个音节被切掉。
pub const DEFAULT_HANGOVER_MS: u64 = 250;

pub trait Vad {
    /// 判断这一帧是否包含语音。
    fn is_speech(&mut self, frame: &[f32]) -> bool;
    /// 当前帧是否为 VAD 挂断保留期（hangover）的最后一帧。
    fn is_last_hangover_frame(&self) -> bool {
        false
    }
    fn reset(&mut self);
}

pub struct EnergyVad {
    threshold: f32,
    hangover_frames: u32,
    remaining: u32,
    last_hangover_frame: bool,
}

impl EnergyVad {
    pub fn new(threshold: f32, hangover_ms: u64) -> Self {
        Self::with_frames(threshold, (hangover_ms / FRAME_MS).max(1) as usize)
    }

    pub fn with_frames(threshold: f32, hangover_frames: usize) -> Self {
        Self {
            threshold: threshold.max(0.0),
            hangover_frames: u32::try_from(hangover_frames).unwrap_or(u32::MAX),
            remaining: 0,
            last_hangover_frame: false,
        }
    }

    pub fn threshold(&self) -> f32 {
        self.threshold
    }

    pub fn hangover_frames(&self) -> u32 {
        self.hangover_frames
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
            self.last_hangover_frame = false;
            return false;
        }
        let energy = frame.iter().map(|sample| sample.abs()).sum::<f32>() / frame.len() as f32;
        if energy >= self.threshold {
            self.remaining = self.hangover_frames;
            self.last_hangover_frame = false;
            true
        } else if self.remaining > 0 {
            self.remaining -= 1;
            self.last_hangover_frame = self.remaining == 0;
            true
        } else {
            self.last_hangover_frame = false;
            false
        }
    }

    fn is_last_hangover_frame(&self) -> bool {
        self.last_hangover_frame
    }

    fn reset(&mut self) {
        self.remaining = 0;
        self.last_hangover_frame = false;
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
        assert!(!vad.is_last_hangover_frame());
        assert!(vad.is_speech(&quiet()));
        assert!(!vad.is_last_hangover_frame());
        assert!(vad.is_speech(&quiet()));
        assert!(vad.is_last_hangover_frame());
        assert!(!vad.is_speech(&quiet()));
        assert!(!vad.is_last_hangover_frame());
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
