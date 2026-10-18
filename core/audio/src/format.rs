//! 音频格式几何：与 TeamSpeak 语音包一致的 48kHz、20ms 帧。
//!
//! 上行声道数由频道 codec 决定：codec 4（Opus Voice）单声道，codec 5（Opus Music）
//! 立体声。下行统一按立体声解码，Opus 会把单声道包展开成双声道。

use std::time::Duration;

/// 协议层语音/音乐两种编码标识。
pub const VOICE_CODEC: i32 = 4;
pub const MUSIC_CODEC: i32 = 5;

/// 48kHz、20ms 的每声道样本数。
pub const FRAME_SAMPLES_PER_CHANNEL: usize = 960;
/// 48kHz、20ms 的立体声交织样本数。
pub const FRAME_SAMPLES: usize = FRAME_SAMPLES_PER_CHANNEL * 2;
/// 协议层语音帧长度。
pub const FRAME_MS: u64 = 20;

/// Opus 单包最长 120ms，解码缓冲按这个上限准备。
pub const MAX_OPUS_SAMPLES_PER_CHANNEL: usize = 5_760;
pub const MAX_OPUS_SAMPLES: usize = MAX_OPUS_SAMPLES_PER_CHANNEL * 2;

/// Opus 输出缓冲上限；实际发送前还要过 TS 的 500 字节数据报上限。
pub const MAX_PACKET_BYTES: usize = 1_275;

/// 人声 64kbps、音乐 128kbps；两者在 20ms 帧下都远低于 500 字节包上限。
pub const VOICE_BITRATE_BPS: i32 = 64_000;
pub const MUSIC_BITRATE_BPS: i32 = 128_000;

/// 48kHz 立体声：解码与混音的中间格式。
pub const OPUS_STEREO: AudioFormat = AudioFormat {
    sample_rate_hz: 48_000,
    channels: 2,
};

/// 48kHz 单声道：codec 4 的上行格式。
pub const OPUS_MONO: AudioFormat = AudioFormat {
    sample_rate_hz: 48_000,
    channels: 1,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AudioFormat {
    pub sample_rate_hz: u32,
    pub channels: u16,
}

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

pub fn is_supported_codec(codec: i32) -> bool {
    matches!(codec, VOICE_CODEC | MUSIC_CODEC)
}

/// 频道 codec → 上行声道数。未知 codec 返回 `None`。
pub fn codec_channels(codec: i32) -> Option<u16> {
    match codec {
        VOICE_CODEC => Some(1),
        MUSIC_CODEC => Some(2),
        _ => None,
    }
}

/// 频道 codec → 上行格式。
pub fn codec_format(codec: i32) -> Option<AudioFormat> {
    codec_channels(codec).map(|channels| AudioFormat {
        sample_rate_hz: 48_000,
        channels,
    })
}

pub fn frame_samples(channels: u16) -> usize {
    FRAME_SAMPLES_PER_CHANNEL * channels as usize
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_geometry_matches_pcm_geometry() {
        assert_eq!(FRAME_SAMPLES_PER_CHANNEL, 960);
        assert_eq!(FRAME_SAMPLES, 1920);
        assert_eq!(MAX_OPUS_SAMPLES_PER_CHANNEL, 5760);
        assert_eq!(
            OPUS_STEREO.duration_of(FRAME_SAMPLES),
            Duration::from_millis(20)
        );
        assert_eq!(
            OPUS_MONO.duration_of(FRAME_SAMPLES_PER_CHANNEL),
            Duration::from_millis(20)
        );
    }

    #[test]
    fn codec_ids_follow_protocol() {
        assert_eq!(VOICE_CODEC, 4);
        assert_eq!(MUSIC_CODEC, 5);
        assert_eq!(codec_channels(VOICE_CODEC), Some(1));
        assert_eq!(codec_channels(MUSIC_CODEC), Some(2));
        assert_eq!(codec_channels(0), None);
        assert!(is_supported_codec(4));
        assert!(!is_supported_codec(3));
    }
}
