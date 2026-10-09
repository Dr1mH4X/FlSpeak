//! Opus 编解码。
//!
//! Opus 解码器状态按编码流独立，每个说话人必须持有自己的 `OpusDecoder`。

use audiopus::coder::{Decoder, Encoder};
use audiopus::packet::Packet;
use audiopus::{Application, Bitrate, Channels, MutSignals, SampleRate};

use crate::AudioError;
use crate::format::{FRAME_SAMPLES, OUTBOUND_BITRATE_BPS};

/// 单个 Opus 包的输出缓冲上限。
pub const MAX_PACKET_BYTES: usize = 1500;

pub struct OpusEncoder {
    inner: Encoder,
}

impl OpusEncoder {
    pub fn new() -> Result<Self, AudioError> {
        let mut inner = Encoder::new(SampleRate::Hz48000, Channels::Stereo, Application::Audio)
            .map_err(codec_error)?;
        inner
            .set_bitrate(Bitrate::BitsPerSecond(OUTBOUND_BITRATE_BPS))
            .map_err(codec_error)?;
        Ok(Self { inner })
    }

    /// 编码一帧 20ms 立体声 PCM，返回写入 `output` 的字节数。
    pub fn encode(&mut self, pcm: &[i16], output: &mut [u8]) -> Result<usize, AudioError> {
        debug_assert_eq!(pcm.len(), FRAME_SAMPLES);
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
    /// 返回值是**每声道**样本数（Opus 的约定），交织缓冲的总长度是它的两倍。
    pub fn decode(&mut self, packet: Option<&[u8]>, pcm: &mut [i16]) -> Result<usize, AudioError> {
        debug_assert_eq!(pcm.len(), FRAME_SAMPLES);
        let packet = packet
            .map(Packet::try_from)
            .transpose()
            .map_err(codec_error)?;
        let output = MutSignals::try_from(pcm).map_err(codec_error)?;
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
    use crate::format::{FRAME_SAMPLES, FRAME_SAMPLES_PER_CHANNEL, OPUS_PCM};

    #[test]
    fn round_trips_a_frame() {
        let mut encoder = OpusEncoder::new().unwrap();
        let mut decoder = OpusDecoder::new().unwrap();
        let pcm: Vec<i16> = (0..FRAME_SAMPLES)
            .map(|i| ((i as f32 * 0.05).sin() * 8000.0) as i16)
            .collect();

        let mut packet = [0u8; MAX_PACKET_BYTES];
        let written = encoder.encode(&pcm, &mut packet).unwrap();
        assert!(written > 0 && written < MAX_PACKET_BYTES);

        let mut decoded = vec![0i16; FRAME_SAMPLES];
        let samples = decoder
            .decode(Some(&packet[..written]), &mut decoded)
            .unwrap();
        assert_eq!(samples, FRAME_SAMPLES_PER_CHANNEL);
        assert_eq!(OPUS_PCM.channels, 2);
    }

    #[test]
    fn packet_loss_concealment_produces_a_frame() {
        let mut decoder = OpusDecoder::new().unwrap();
        let mut decoded = vec![0i16; FRAME_SAMPLES];
        assert_eq!(
            decoder.decode(None, &mut decoded).unwrap(),
            FRAME_SAMPLES_PER_CHANNEL
        );
    }
}
