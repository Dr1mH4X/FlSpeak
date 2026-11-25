//! Opus 编解码：编码器按频道 codec 重建（4 单声道 / 5 立体声），解码器统一按立体声初始化。

use rusty_opus::{
    Application, Error as OpusError, OpusDecoder as RawDecoder, OpusEncoder as RawEncoder,
    SignalType,
};

use crate::format::{
    FRAME_SAMPLES, FRAME_SAMPLES_PER_CHANNEL, MAX_OPUS_SAMPLES, MAX_OPUS_SAMPLES_PER_CHANNEL,
    MAX_PACKET_BYTES, MUSIC_BITRATE_BPS, MUSIC_CODEC, OPUS_STEREO, VOICE_BITRATE_BPS, VOICE_CODEC,
    codec_channels,
};
use crate::{AudioError, CodecError};

/// 语音编码默认预期丢包率（%），驱动 SILK LBRR 带内 FEC。
pub const DEFAULT_VOICE_PACKET_LOSS_PERC: u8 = 15;

pub struct OpusEncoder {
    inner: RawEncoder,
    channels: u16,
    codec: i32,
    packet_loss_perc: u8,
    reset_count: u64,
}

impl OpusEncoder {
    pub fn new(codec: i32) -> Result<Self, AudioError> {
        let channels = codec_channels(codec).ok_or(AudioError::UnsupportedCodec(codec))?;
        let packet_loss_perc = if codec == VOICE_CODEC {
            DEFAULT_VOICE_PACKET_LOSS_PERC
        } else {
            0
        };
        let inner = build_raw_encoder(codec, channels, packet_loss_perc)?;
        Ok(Self {
            inner,
            channels,
            codec,
            packet_loss_perc,
            reset_count: 0,
        })
    }

    pub fn codec(&self) -> i32 {
        self.codec
    }

    pub fn channels(&self) -> u16 {
        self.channels
    }

    pub fn packet_loss_perc(&self) -> u8 {
        self.packet_loss_perc
    }

    pub fn reset_count(&self) -> u64 {
        self.reset_count
    }

    /// 运行时更新编码器预期丢包率（0..=100），用于结合网络遥测在 10..=25 间微调 FEC 强度。
    pub fn set_packet_loss_perc(&mut self, perc: u8) {
        let clamped = perc.min(100);
        self.packet_loss_perc = clamped;
        self.inner.packet_loss_perc = i32::from(clamped);
    }

    /// 语音段开始时重置编码器状态，避免上一段的尾音污染新段，同时保留当前丢包率配置。
    pub fn reset(&mut self) -> Result<(), AudioError> {
        self.inner = build_raw_encoder(self.codec, self.channels, self.packet_loss_perc)?;
        self.reset_count += 1;
        Ok(())
    }

    /// 编码一帧 20ms f32 交织 PCM，返回写入 `output` 的字节数（严格不超过 `MAX_PACKET_BYTES`）。
    pub fn encode(&mut self, pcm: &[f32], output: &mut [u8]) -> Result<usize, AudioError> {
        if pcm.len() != FRAME_SAMPLES_PER_CHANNEL * self.channels as usize {
            return Err(CodecError::Opus(format!(
                "PCM length {} does not match {} channels",
                pcm.len(),
                self.channels
            ))
            .into());
        }
        let capacity = output.len().min(MAX_PACKET_BYTES);
        if capacity < 2 {
            return Err(CodecError::BufferTooSmall {
                capacity,
                max_data_bytes: MAX_PACKET_BYTES,
            }
            .into());
        }
        let written = self
            .inner
            .encode(pcm, FRAME_SAMPLES_PER_CHANNEL, &mut output[..capacity])
            .map_err(codec_error)?;
        if written > MAX_PACKET_BYTES {
            return Err(CodecError::Opus(format!(
                "encoded output length {written} exceeds the packet budget {MAX_PACKET_BYTES}"
            ))
            .into());
        }
        Ok(written)
    }
}

fn build_raw_encoder(
    codec: i32,
    channels: u16,
    packet_loss_perc: u8,
) -> Result<RawEncoder, AudioError> {
    if !matches!(channels, 1 | 2) {
        return Err(AudioError::UnsupportedChannels(channels));
    }
    let sample_rate = OPUS_STEREO.sample_rate_hz as i32;
    let application = if codec == VOICE_CODEC {
        Application::Voip
    } else if codec == MUSIC_CODEC {
        Application::Audio
    } else {
        return Err(AudioError::UnsupportedCodec(codec));
    };

    let mut inner =
        RawEncoder::new(sample_rate, channels as usize, application).map_err(codec_error)?;
    inner.use_cbr = false;
    inner.use_dtx = false;
    if codec == VOICE_CODEC {
        inner.bitrate_bps = VOICE_BITRATE_BPS;
        inner.use_inband_fec = true;
        inner.packet_loss_perc = i32::from(packet_loss_perc.min(100));
        inner.signal_type = Some(SignalType::Voice);
    } else {
        inner.bitrate_bps = MUSIC_BITRATE_BPS;
        inner.use_inband_fec = false;
        inner.packet_loss_perc = 0;
        inner.signal_type = None;
    }
    Ok(inner)
}

pub struct OpusDecoder {
    inner: RawDecoder,
}

impl OpusDecoder {
    pub fn new() -> Result<Self, AudioError> {
        let inner = RawDecoder::new(
            OPUS_STEREO.sample_rate_hz as i32,
            OPUS_STEREO.channels as usize,
        )
        .map_err(codec_error)?;
        Ok(Self { inner })
    }

    /// 正常解码一帧完整语音包，返回每声道样本数。
    ///
    /// `pcm` 必须是至少 `MAX_OPUS_SAMPLES` 的 48kHz 立体声交织缓冲。
    pub fn decode_normal(&mut self, packet: &[u8], pcm: &mut [f32]) -> Result<usize, AudioError> {
        if packet.is_empty() {
            return Err(
                CodecError::Opus("Opus decoding does not accept an empty packet".into()).into(),
            );
        }
        if pcm.len() < MAX_OPUS_SAMPLES {
            return Err(CodecError::Opus(format!(
                "Opus decode buffer too small: {} < {MAX_OPUS_SAMPLES}",
                pcm.len()
            ))
            .into());
        }
        self.inner
            .decode(
                packet,
                MAX_OPUS_SAMPLES_PER_CHANNEL,
                &mut pcm[..MAX_OPUS_SAMPLES],
            )
            .map_err(codec_error)
    }

    /// 利用下一帧载荷中的带内 FEC（SILK LBRR）恢复当前丢失的 20ms 帧。
    ///
    /// 严格请求单帧长度（`FRAME_SAMPLES_PER_CHANNEL` = 960 samples/ch），绝不生成 120ms 长尾。
    pub fn decode_fec(&mut self, next_packet: &[u8], pcm: &mut [f32]) -> Result<usize, AudioError> {
        if next_packet.is_empty() {
            return Err(CodecError::Opus(
                "Opus FEC decoding requires a non-empty next packet".into(),
            )
            .into());
        }
        if pcm.len() < FRAME_SAMPLES {
            return Err(CodecError::Opus(format!(
                "Opus FEC buffer too small: {} < {FRAME_SAMPLES}",
                pcm.len()
            ))
            .into());
        }
        self.inner
            .decode_fec(
                next_packet,
                FRAME_SAMPLES_PER_CHANNEL,
                &mut pcm[..FRAME_SAMPLES],
            )
            .map_err(codec_error)
    }

    /// 无包丢包隐藏（PLC），严格预测单帧 20ms（960 samples/ch），禁止传入 `MAX_OPUS_SAMPLES`。
    pub fn decode_plc(&mut self, pcm: &mut [f32]) -> Result<usize, AudioError> {
        if pcm.len() < FRAME_SAMPLES {
            return Err(CodecError::Opus(format!(
                "Opus PLC buffer too small: {} < {FRAME_SAMPLES}",
                pcm.len()
            ))
            .into());
        }
        self.inner
            .decode(&[], FRAME_SAMPLES_PER_CHANNEL, &mut pcm[..FRAME_SAMPLES])
            .map_err(codec_error)
    }
}

fn codec_error(err: OpusError) -> AudioError {
    match err {
        OpusError::BufferTooSmall(_) => CodecError::BufferTooSmall {
            capacity: 0,
            max_data_bytes: MAX_PACKET_BYTES,
        }
        .into(),
        other => CodecError::Opus(other.to_string()).into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format::{
        FRAME_SAMPLES, FRAME_SAMPLES_PER_CHANNEL, MAX_OPUS_SAMPLES, MAX_PACKET_BYTES, MUSIC_CODEC,
        VOICE_CODEC,
    };

    fn frame(amplitude: f32) -> Vec<f32> {
        (0..FRAME_SAMPLES)
            .map(|index| (index as f32 * 0.05).sin() * amplitude)
            .collect()
    }

    fn synthetic_speech_frame(frame_index: usize, channels: usize) -> Vec<f32> {
        // 模拟含基频共振峰调制的语音波形，触发 SILK LBRR 语音活跃度阈值。
        let f0 = 135.0 + ((frame_index % 17) as f32) * 3.0;
        let envelope = if frame_index % 25 < 20 { 0.45 } else { 0.05 };
        let mut out = Vec::with_capacity(FRAME_SAMPLES_PER_CHANNEL * channels);
        for i in 0..FRAME_SAMPLES_PER_CHANNEL {
            let t = (frame_index * FRAME_SAMPLES_PER_CHANNEL + i) as f32 / 48_000.0;
            let glottal = (2.0 * std::f32::consts::PI * f0 * t).sin()
                + 0.6 * (2.0 * std::f32::consts::PI * (f0 * 2.0) * t).sin()
                + 0.35 * (2.0 * std::f32::consts::PI * 520.0 * t).sin();
            let sample = (glottal * 0.35 * envelope).clamp(-1.0, 1.0);
            for ch in 0..channels {
                out.push(if ch == 0 { sample } else { -sample * 0.9 });
            }
        }
        out
    }

    #[test]
    fn voice_encoder_is_mono_with_fec_defaults() {
        let mut encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        assert_eq!(encoder.channels(), 1);
        assert_eq!(encoder.codec(), 4);
        assert_eq!(encoder.packet_loss_perc(), DEFAULT_VOICE_PACKET_LOSS_PERC);
        assert!(encoder.inner.use_inband_fec);
        assert!(!encoder.inner.use_cbr);
        assert!(!encoder.inner.use_dtx);
        assert_eq!(encoder.inner.bitrate_bps, VOICE_BITRATE_BPS);

        encoder.set_packet_loss_perc(22);
        assert_eq!(encoder.packet_loss_perc(), 22);
        assert_eq!(encoder.inner.packet_loss_perc, 22);
        encoder.reset().unwrap();
        assert_eq!(encoder.packet_loss_perc(), 22);
        assert_eq!(encoder.inner.packet_loss_perc, 22);
    }

    #[test]
    fn music_encoder_is_stereo_without_fec() {
        let encoder = OpusEncoder::new(MUSIC_CODEC).unwrap();
        assert_eq!(encoder.channels(), 2);
        assert_eq!(encoder.codec(), 5);
        assert!(!encoder.inner.use_inband_fec);
        assert!(!encoder.inner.use_cbr);
        assert!(!encoder.inner.use_dtx);
        assert_eq!(encoder.inner.bitrate_bps, MUSIC_BITRATE_BPS);
    }

    #[test]
    fn voice_round_trip_decodes_to_stereo() {
        let mut encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        let mono = frame(0.35);
        let mut packet = [0u8; MAX_PACKET_BYTES];
        let written = encoder
            .encode(&mono[..FRAME_SAMPLES_PER_CHANNEL], &mut packet)
            .unwrap();
        assert!(written > 1 && written <= MAX_PACKET_BYTES);

        let mut decoder = OpusDecoder::new().unwrap();
        let mut decoded = vec![0.0f32; MAX_OPUS_SAMPLES];
        let samples = decoder
            .decode_normal(&packet[..written], &mut decoded)
            .unwrap();
        assert_eq!(samples, FRAME_SAMPLES_PER_CHANNEL);
    }

    #[test]
    fn music_round_trip() {
        let mut encoder = OpusEncoder::new(MUSIC_CODEC).unwrap();
        let stereo = frame(0.35);
        let mut packet = [0u8; MAX_PACKET_BYTES];
        let written = encoder.encode(&stereo, &mut packet).unwrap();
        assert!(written > 1 && written <= MAX_PACKET_BYTES);

        let mut decoder = OpusDecoder::new().unwrap();
        let mut decoded = vec![0.0f32; MAX_OPUS_SAMPLES];
        assert_eq!(
            decoder
                .decode_normal(&packet[..written], &mut decoded)
                .unwrap(),
            FRAME_SAMPLES_PER_CHANNEL
        );
    }

    #[test]
    fn variable_bitrate_packets_fit_transport_after_talkspurt_resets() {
        for codec in [VOICE_CODEC, MUSIC_CODEC] {
            let mut encoder = OpusEncoder::new(codec).unwrap();
            let mut decoder = OpusDecoder::new().unwrap();
            // 调用方可能传入大于传输预算的缓冲；编码器必须硬截断到 484 字节以内。
            let mut packet = [0u8; 1275];
            let mut decoded = vec![0.0f32; MAX_OPUS_SAMPLES];
            let mut noise = 0x1234_5678u32;
            for frame_index in 0..240 {
                if frame_index % 12 == 0 {
                    encoder.reset().unwrap();
                }
                let pcm: Vec<f32> = (0..FRAME_SAMPLES_PER_CHANNEL * encoder.channels() as usize)
                    .map(|index| {
                        noise ^= noise << 13;
                        noise ^= noise >> 17;
                        noise ^= noise << 5;
                        match frame_index % 4 {
                            0 => (index as f32 * (frame_index as f32 + 1.0) * 0.0007).sin() * 0.92,
                            1 => (noise as i16) as f32 / 32768.0,
                            2 => {
                                if index % 80 < 40 {
                                    0.85
                                } else {
                                    -0.85
                                }
                            }
                            _ => 0.0,
                        }
                    })
                    .collect();
                let written = encoder.encode(&pcm, &mut packet).unwrap();
                assert!(
                    written <= MAX_PACKET_BYTES,
                    "codec {codec}, frame {frame_index}: {written} byte payload exceeds transport"
                );
                assert_eq!(
                    decoder
                        .decode_normal(&packet[..written], &mut decoded)
                        .unwrap(),
                    FRAME_SAMPLES_PER_CHANNEL
                );
            }
        }
    }

    #[test]
    fn voice_5000_frames_cvbr_and_inband_fec_stress_test() {
        let mut encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        let mut decoder = OpusDecoder::new().unwrap();
        let mut packet_buf = [0u8; 1275];
        let mut packets: Vec<Vec<u8>> = Vec::with_capacity(5000);

        for frame_index in 0..5000 {
            if frame_index % 250 == 0 {
                let perc = 10 + ((frame_index / 250) % 16) as u8;
                encoder.set_packet_loss_perc(perc);
            }
            if frame_index % 500 == 0 {
                encoder.reset().unwrap();
            }
            let pcm = synthetic_speech_frame(frame_index, 1);
            let written = encoder.encode(&pcm, &mut packet_buf).unwrap();
            assert!(
                written > 1 && written <= MAX_PACKET_BYTES,
                "frame {frame_index} packet size {written} out of range (1..={MAX_PACKET_BYTES})"
            );
            packets.push(packet_buf[..written].to_vec());
        }

        let mut decoded = vec![0.0f32; MAX_OPUS_SAMPLES];
        let mut fec_recovered = 0usize;
        let mut non_silent_fec = 0usize;
        let mut plc_calls = 0usize;

        let mut i = 0;
        while i < packets.len() {
            if i > 10 && i + 1 < packets.len() && i % 40 == 5 {
                // 单包丢失：利用下一包载荷走 decode_fec 恢复当前 20ms 帧。
                let mut fec_out = vec![0.0f32; FRAME_SAMPLES];
                let n = decoder.decode_fec(&packets[i + 1], &mut fec_out).unwrap();
                assert_eq!(n, FRAME_SAMPLES_PER_CHANNEL);
                if fec_out.iter().any(|s| s.abs() > 1e-4) {
                    non_silent_fec += 1;
                }
                fec_recovered += 1;
                // 紧接着用同一下一包正常解码。
                let next_n = decoder
                    .decode_normal(&packets[i + 1], &mut decoded)
                    .unwrap();
                assert_eq!(next_n, FRAME_SAMPLES_PER_CHANNEL);
                i += 2;
                continue;
            }
            if i > 10 && i % 97 == 0 {
                // 无下一包时走 decode_plc，严格输出 20ms（960 samples/ch）。
                let mut plc_out = vec![0.0f32; MAX_OPUS_SAMPLES];
                let n = decoder.decode_plc(&mut plc_out).unwrap();
                assert_eq!(n, FRAME_SAMPLES_PER_CHANNEL);
                assert!(
                    plc_out[FRAME_SAMPLES..].iter().all(|&s| s == 0.0),
                    "decode_plc must not write beyond one 20 ms frame"
                );
                plc_calls += 1;
            }
            let n = decoder.decode_normal(&packets[i], &mut decoded).unwrap();
            assert_eq!(n, FRAME_SAMPLES_PER_CHANNEL);
            i += 1;
        }

        assert!(fec_recovered >= 100);
        assert!(
            non_silent_fec > 0,
            "SILK LBRR FEC should produce a non-silent recovered waveform"
        );
        assert!(plc_calls >= 40);
    }

    #[test]
    fn packet_loss_concealment_strictly_outputs_single_20ms_frame() {
        let mut encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        let mut packet = [0u8; MAX_PACKET_BYTES];
        let pcm = synthetic_speech_frame(1, 1);
        let written = encoder.encode(&pcm, &mut packet).unwrap();

        let mut decoder = OpusDecoder::new().unwrap();
        let mut decoded = vec![0.0f32; MAX_OPUS_SAMPLES];
        assert_eq!(
            decoder
                .decode_normal(&packet[..written], &mut decoded)
                .unwrap(),
            FRAME_SAMPLES_PER_CHANNEL
        );

        let mut plc = vec![0.0f32; MAX_OPUS_SAMPLES];
        let n = decoder.decode_plc(&mut plc).unwrap();
        assert_eq!(n, FRAME_SAMPLES_PER_CHANNEL);
        assert!(plc[FRAME_SAMPLES..].iter().all(|&s| s == 0.0));
    }

    #[test]
    fn reset_state_does_not_break_encoding() {
        let mut encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        encoder.reset().unwrap();
        let mut packet = [0u8; MAX_PACKET_BYTES];
        assert!(
            encoder
                .encode(&frame(0.1)[..FRAME_SAMPLES_PER_CHANNEL], &mut packet)
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

    #[test]
    fn empty_buffer_returns_buffer_too_small() {
        let mut encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        let pcm = vec![0.0f32; FRAME_SAMPLES_PER_CHANNEL];
        let mut empty = [];
        let err = encoder.encode(&pcm, &mut empty).unwrap_err();
        assert!(matches!(
            err,
            AudioError::Codec(CodecError::BufferTooSmall { capacity: 0, .. })
        ));
    }
}
