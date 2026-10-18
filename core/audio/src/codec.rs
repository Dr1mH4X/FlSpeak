//! Opus 编解码。
//!
//! 编码器按频道 codec 配置：codec 4 单声道 Voip，codec 5 立体声 Audio。Opus 不支持
//! 中途切换声道数，切频道时必须重建编码器。解码器统一按立体声初始化，Opus 会把
//! 单声道包展开成双声道。

use audiopus::coder::{Decoder, Encoder, GenericCtl};
use audiopus::packet::Packet;
use audiopus::{Application, Bitrate, Channels, MutSignals, SampleRate};

use crate::AudioError;
use crate::format::{
    MAX_OPUS_SAMPLES, MUSIC_BITRATE_BPS, MUSIC_CODEC, VOICE_BITRATE_BPS, VOICE_CODEC,
    codec_channels,
};

pub struct OpusEncoder {
    inner: Encoder,
    channels: u16,
    codec: i32,
}

impl OpusEncoder {
    pub fn new(codec: i32) -> Result<Self, AudioError> {
        let channels = codec_channels(codec).ok_or(AudioError::UnsupportedCodec(codec))?;
        let application = if codec == VOICE_CODEC {
            Application::Voip
        } else {
            Application::Audio
        };
        let bitrate = if codec == MUSIC_CODEC {
            MUSIC_BITRATE_BPS
        } else {
            VOICE_BITRATE_BPS
        };
        let opus_channels = match channels {
            1 => Channels::Mono,
            2 => Channels::Stereo,
            other => return Err(AudioError::UnsupportedChannels(other)),
        };
        let mut inner =
            Encoder::new(SampleRate::Hz48000, opus_channels, application).map_err(codec_error)?;
        inner
            .set_bitrate(Bitrate::BitsPerSecond(bitrate))
            .map_err(codec_error)?;
        Ok(Self {
            inner,
            channels,
            codec,
        })
    }

    pub fn codec(&self) -> i32 {
        self.codec
    }

    pub fn channels(&self) -> u16 {
        self.channels
    }

    /// 语音段开始时重置熵编码状态，避免上一段的尾音影响新段。
    pub fn reset(&mut self) -> Result<(), AudioError> {
        self.inner.reset_state().map_err(codec_error)
    }

    /// 编码一帧 20ms PCM，返回写入 `output` 的字节数。
    pub fn encode(&mut self, pcm: &[i16], output: &mut [u8]) -> Result<usize, AudioError> {
        if pcm.len() != crate::format::FRAME_SAMPLES_PER_CHANNEL * self.channels as usize {
            return Err(AudioError::Codec(format!(
                "PCM 长度 {} 与 {} 声道不匹配",
                pcm.len(),
                self.channels
            )));
        }
        self.inner.encode(pcm, output).map_err(codec_error)
    }
}

pub struct OpusDecoder {
    inner: Decoder,
}

impl OpusDecoder {
    pub fn new() -> Result<Self, AudioError> {
        let inner = Decoder::new(SampleRate::Hz48000, Channels::Stereo).map_err(codec_error)?;
        Ok(Self { inner })
    }

    /// 解码一个包。`packet` 为 `None` 时走丢包隐藏（PLC）。
    ///
    /// 返回值是每声道样本数；`pcm` 必须是至少 `MAX_OPUS_SAMPLES` 的交织缓冲。
    pub fn decode(&mut self, packet: Option<&[u8]>, pcm: &mut [i16]) -> Result<usize, AudioError> {
        if pcm.len() < MAX_OPUS_SAMPLES {
            return Err(AudioError::Codec(format!(
                "Opus 解码缓冲太小: {} < {MAX_OPUS_SAMPLES}",
                pcm.len()
            )));
        }
        let packet = packet
            .map(Packet::try_from)
            .transpose()
            .map_err(codec_error)?;
        let output = MutSignals::try_from(&mut pcm[..MAX_OPUS_SAMPLES]).map_err(codec_error)?;
        self.inner
            .decode(packet, output, false)
            .map_err(codec_error)
    }
}

fn codec_error(err: audiopus::Error) -> AudioError {
    AudioError::Codec(err.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format::{
        FRAME_SAMPLES, FRAME_SAMPLES_PER_CHANNEL, MAX_OPUS_SAMPLES, MAX_PACKET_BYTES, MUSIC_CODEC,
        VOICE_CODEC,
    };

    fn frame(amplitude: f32) -> Vec<i16> {
        (0..FRAME_SAMPLES)
            .map(|index| ((index as f32 * 0.05).sin() * amplitude) as i16)
            .collect()
    }

    #[test]
    fn voice_encoder_is_mono() {
        let encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        assert_eq!(encoder.channels(), 1);
        assert_eq!(encoder.codec(), 4);
    }

    #[test]
    fn music_encoder_is_stereo() {
        let encoder = OpusEncoder::new(MUSIC_CODEC).unwrap();
        assert_eq!(encoder.channels(), 2);
    }

    #[test]
    fn voice_round_trip_decodes_to_stereo() {
        let mut encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        let mono = frame(8000.0);
        let mut packet = [0u8; MAX_PACKET_BYTES];
        let written = encoder
            .encode(&mono[..FRAME_SAMPLES_PER_CHANNEL], &mut packet)
            .unwrap();
        assert!(written > 0 && written < MAX_PACKET_BYTES);

        let mut decoder = OpusDecoder::new().unwrap();
        let mut decoded = vec![0i16; MAX_OPUS_SAMPLES];
        let samples = decoder
            .decode(Some(&packet[..written]), &mut decoded)
            .unwrap();
        assert_eq!(samples, FRAME_SAMPLES_PER_CHANNEL);
    }

    #[test]
    fn music_round_trip() {
        let mut encoder = OpusEncoder::new(MUSIC_CODEC).unwrap();
        let stereo = frame(8000.0);
        let mut packet = [0u8; MAX_PACKET_BYTES];
        let written = encoder.encode(&stereo, &mut packet).unwrap();

        let mut decoder = OpusDecoder::new().unwrap();
        let mut decoded = vec![0i16; MAX_OPUS_SAMPLES];
        assert_eq!(
            decoder
                .decode(Some(&packet[..written]), &mut decoded)
                .unwrap(),
            FRAME_SAMPLES_PER_CHANNEL
        );
    }

    #[test]
    fn packet_loss_concealment_produces_a_frame() {
        let mut decoder = OpusDecoder::new().unwrap();
        let mut decoded = vec![0i16; MAX_OPUS_SAMPLES];
        assert!(decoder.decode(None, &mut decoded).unwrap() > 0);
    }

    #[test]
    fn reset_state_does_not_break_encoding() {
        let mut encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        encoder.reset().unwrap();
        let mut packet = [0u8; MAX_PACKET_BYTES];
        assert!(
            encoder
                .encode(&frame(1000.0)[..FRAME_SAMPLES_PER_CHANNEL], &mut packet)
                .unwrap()
                > 0
        );
    }

    #[test]
    fn unsupported_codec_is_rejected() {
        assert!(matches!(
            OpusEncoder::new(3),
            Err(AudioError::UnsupportedCodec(3))
        ));
    }
}
