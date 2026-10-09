//! 音频格式几何：与 TeamSpeak 语音包一致的 48kHz 立体声 20ms 帧。

use std::time::Duration;

/// 协议层语音/音乐两种编码标识。
pub const VOICE_CODEC: i32 = 4;
pub const MUSIC_CODEC: i32 = 5;

/// TeamSpeak 语音帧长度。
pub const FRAME_MS: u64 = 20;

/// 出站 Opus 码率，与 TeamSpeakClaw 出流参数一致。
pub const OUTBOUND_BITRATE_BPS: i32 = 128_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AudioFormat {
    pub sample_rate_hz: u32,
    pub channels: u16,
}

/// 编解码统一使用 48kHz 立体声，与协议一致，避免收发两侧额外重采样。
pub const OPUS_PCM: AudioFormat = AudioFormat {
    sample_rate_hz: 48_000,
    channels: 2,
};

impl AudioFormat {
    pub const fn samples_per_channel(&self, duration: Duration) -> usize {
        (self.sample_rate_hz as u64 * duration.as_millis() as u64 / 1000) as usize
    }

    pub const fn samples(&self, duration: Duration) -> usize {
        self.samples_per_channel(duration) * self.channels as usize
    }

    pub const fn duration_of(&self, samples: usize) -> Duration {
        let frames = samples / self.channels as usize;
        Duration::from_micros((frames as u64 * 1_000_000) / self.sample_rate_hz as u64)
    }
}

/// 一帧 20ms 的样本数（单声道 / 立体声交织）。
pub const FRAME_SAMPLES_PER_CHANNEL: usize =
    OPUS_PCM.samples_per_channel(Duration::from_millis(FRAME_MS));
pub const FRAME_SAMPLES: usize = OPUS_PCM.samples(Duration::from_millis(FRAME_MS));

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_geometry_matches_pcm_geometry() {
        assert_eq!(FRAME_SAMPLES_PER_CHANNEL, 960);
        assert_eq!(FRAME_SAMPLES, 1920);
        assert_eq!(
            OPUS_PCM.duration_of(FRAME_SAMPLES),
            Duration::from_millis(20)
        );
    }

    #[test]
    fn codec_ids_follow_protocol() {
        assert_eq!(VOICE_CODEC, 4);
        assert_eq!(MUSIC_CODEC, 5);
    }
}
