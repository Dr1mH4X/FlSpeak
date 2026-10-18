//! 采集侧流水线：设备格式 → 48kHz 目标格式 → VAD/PTT → 20ms Opus 帧。
//!
//! 这里不碰 cpal，也不做线程调度；线程循环在 `engine`，这样流水线可以用合成样本单测。

use std::collections::VecDeque;
use std::time::{Duration, Instant};

use crate::AudioError;
use crate::codec::OpusEncoder;
use crate::convert::FormatConverter;
use crate::format::{AudioFormat, MAX_PACKET_BYTES, codec_format, frame_samples};
use crate::vad::{EnergyVad, Vad};

/// 采集缓冲上限：约 240ms。超过就丢到两帧，避免延迟累积。
const MAX_PENDING_FRAMES: usize = 12;
const RESYNC_FRAMES: usize = 2;

/// 一帧待发送的语音包。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapturePacket {
    pub codec: i32,
    pub data: Vec<u8>,
}

/// 发送节拍：空闲复位、稳态 +20ms、落后超过 200ms 重定位。
pub struct VoicePacer {
    next_send_at: Option<Instant>,
    frame: Duration,
    max_lag: Duration,
}

impl VoicePacer {
    pub fn new(frame: Duration) -> Self {
        Self {
            next_send_at: None,
            frame,
            max_lag: Duration::from_millis(200),
        }
    }

    pub fn due(&mut self, now: Instant, has_packet: bool) -> bool {
        if !has_packet {
            self.next_send_at = None;
            return false;
        }
        match self.next_send_at {
            None => {
                self.next_send_at = Some(now);
                true
            }
            Some(next) => {
                if now.saturating_duration_since(next) > self.max_lag {
                    self.next_send_at = Some(now);
                    true
                } else {
                    now >= next
                }
            }
        }
    }

    pub fn advance(&mut self) {
        if let Some(next) = self.next_send_at.take() {
            self.next_send_at = Some(next + self.frame);
        }
    }
}

pub struct CapturePipeline {
    codec: i32,
    encoder: OpusEncoder,
    target: AudioFormat,
    source: Option<AudioFormat>,
    converter: Option<FormatConverter>,
    converted: Vec<f32>,
    pcm: VecDeque<f32>,
    frame: Vec<f32>,
    pcm16: Vec<i16>,
    vad: Box<dyn Vad>,
    muted: bool,
    deafened: bool,
    ptt_mode: bool,
    ptt_active: bool,
    speaking: bool,
    enabled: bool,
    received_any: bool,
}

impl CapturePipeline {
    pub fn new(codec: i32) -> Result<Self, AudioError> {
        let target = codec_format(codec).ok_or(AudioError::UnsupportedCodec(codec))?;
        Ok(Self {
            codec,
            encoder: OpusEncoder::new(codec)?,
            target,
            source: None,
            converter: None,
            converted: Vec::new(),
            pcm: VecDeque::new(),
            frame: Vec::new(),
            pcm16: Vec::new(),
            vad: Box::new(EnergyVad::default()),
            muted: false,
            deafened: false,
            ptt_mode: false,
            ptt_active: false,
            speaking: false,
            enabled: false,
            received_any: false,
        })
    }

    pub fn codec(&self) -> i32 {
        self.codec
    }

    pub fn channels(&self) -> u16 {
        self.target.channels
    }

    pub fn begin(&mut self) {
        self.pcm.clear();
        self.vad.reset();
        self.speaking = false;
        self.enabled = true;
        self.received_any = false;
    }

    pub fn end(&mut self) {
        self.pcm.clear();
        self.vad.reset();
        self.speaking = false;
        self.enabled = false;
        self.received_any = false;
    }

    pub fn set_codec(&mut self, codec: i32) -> Result<(), AudioError> {
        if codec == self.codec {
            return Ok(());
        }
        let target = codec_format(codec).ok_or(AudioError::UnsupportedCodec(codec))?;
        self.encoder = OpusEncoder::new(codec)?;
        self.codec = codec;
        self.target = target;
        self.source = None;
        self.converter = None;
        self.pcm.clear();
        self.vad.reset();
        self.speaking = false;
        self.received_any = false;
        Ok(())
    }

    pub fn set_deafened(&mut self, deafened: bool) {
        self.deafened = deafened;
        if deafened {
            self.pcm.clear();
            self.vad.reset();
            self.speaking = false;
            self.ptt_active = false;
        }
    }

    pub fn set_muted(&mut self, muted: bool) {
        self.muted = muted;
        if muted {
            self.pcm.clear();
            self.vad.reset();
            self.speaking = false;
            self.ptt_active = false;
        }
    }

    pub fn set_ptt_mode(&mut self, enabled: bool) {
        if self.ptt_mode == enabled {
            return;
        }
        self.ptt_mode = enabled;
        self.ptt_active = false;
        self.vad.reset();
        self.speaking = false;
    }

    pub fn set_ptt_active(&mut self, active: bool) {
        self.ptt_active = active;
        if !active {
            self.speaking = false;
        }
    }

    pub fn is_speaking(&self) -> bool {
        self.speaking && !self.muted
    }

    /// 追加设备原生格式的采集样本。
    pub fn push_capture(&mut self, samples: &[f32], source: AudioFormat) {
        if !self.enabled || samples.is_empty() {
            return;
        }
        if self.source != Some(source) {
            self.source = Some(source);
            self.converter = Some(FormatConverter::new(source, self.target));
            self.converted.clear();
        }
        let Some(converter) = &mut self.converter else {
            return;
        };
        self.converted.clear();
        converter.process(samples, &mut self.converted);
        if self.converted.is_empty() {
            return;
        }
        self.pcm.extend(self.converted.iter().copied());
        self.received_any = true;

        let max = MAX_PENDING_FRAMES * frame_samples(self.target.channels);
        if self.pcm.len() > max {
            let keep = RESYNC_FRAMES * frame_samples(self.target.channels);
            let drop = self.pcm.len() - keep;
            self.pcm.drain(..drop);
        }
    }

    /// 产出下一帧。调用方按 20ms 节拍调用；数据不足时补零。
    pub fn take_packet(&mut self) -> Result<Option<CapturePacket>, AudioError> {
        if !self.enabled || self.muted || self.deafened || !self.received_any {
            if self.muted || self.deafened {
                self.pcm.clear();
            }
            return Ok(None);
        }

        let needed = frame_samples(self.target.channels);
        self.frame.clear();
        for _ in 0..needed {
            self.frame.push(self.pcm.pop_front().unwrap_or(0.0));
        }

        let should_send = if self.ptt_mode {
            self.ptt_active
        } else {
            self.vad.is_speech(&self.frame)
        };

        if !should_send {
            self.speaking = false;
            self.pcm.clear();
            return Ok(None);
        }

        if !self.speaking {
            // 一段语音开始时重置编码器，避免上一段的尾音污染新段。
            self.encoder.reset()?;
        }
        self.speaking = true;

        self.pcm16.clear();
        self.pcm16.extend(
            self.frame
                .iter()
                .map(|sample| (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16),
        );

        let mut packet = [0u8; MAX_PACKET_BYTES];
        let written = self.encoder.encode(&self.pcm16, &mut packet)?;
        Ok(Some(CapturePacket {
            codec: self.codec,
            data: packet[..written].to_vec(),
        }))
    }
}

impl Default for VoicePacer {
    fn default() -> Self {
        Self::new(Duration::from_millis(crate::format::FRAME_MS))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format::{
        FRAME_SAMPLES_PER_CHANNEL, MUSIC_CODEC, OPUS_MONO, OPUS_STEREO, VOICE_CODEC,
    };

    fn loud_frame(channels: u16) -> Vec<f32> {
        vec![0.3; FRAME_SAMPLES_PER_CHANNEL * channels as usize]
    }

    #[test]
    fn pacer_idle_reset_and_relocate() {
        let mut pacer = VoicePacer::default();
        let t0 = Instant::now();
        assert!(pacer.due(t0, true));
        pacer.advance();
        assert!(!pacer.due(t0 + Duration::from_millis(5), true));
        assert!(!pacer.due(t0 + Duration::from_millis(5), false));
        assert!(pacer.due(t0 + Duration::from_millis(10), true));
        pacer.advance();
        let late = t0 + Duration::from_millis(250);
        assert!(pacer.due(late, true));
    }

    #[test]
    fn voice_pipeline_encodes_one_frame() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        let packet = pipeline.take_packet().unwrap().expect("应当产出语音包");
        assert_eq!(packet.codec, VOICE_CODEC);
        assert!(!packet.data.is_empty());
        assert!(packet.data.len() < MAX_PACKET_BYTES);
    }

    #[test]
    fn music_pipeline_encodes_stereo() {
        let mut pipeline = CapturePipeline::new(MUSIC_CODEC).unwrap();
        pipeline.begin();
        pipeline.push_capture(&loud_frame(2), OPUS_STEREO);
        let packet = pipeline.take_packet().unwrap().expect("应当产出音乐包");
        assert_eq!(packet.codec, MUSIC_CODEC);
    }

    #[test]
    fn muted_pipeline_does_not_send() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        pipeline.set_muted(true);
        assert!(pipeline.take_packet().unwrap().is_none());
        pipeline.set_muted(false);
        // 解静音后必须等新样本，不能补发静音期间的音频。
        assert!(pipeline.take_packet().unwrap().is_none());
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        assert!(pipeline.take_packet().unwrap().is_some());
    }

    #[test]
    fn deafen_blocks_transmit() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        pipeline.set_deafened(true);
        assert!(pipeline.take_packet().unwrap().is_none());
        pipeline.set_deafened(false);
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        assert!(pipeline.take_packet().unwrap().is_some());
    }

    #[test]
    fn ptt_mode_ignores_vad_until_pressed() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();
        pipeline.set_ptt_mode(true);
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        assert!(pipeline.take_packet().unwrap().is_none());

        pipeline.set_ptt_active(true);
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        assert!(pipeline.take_packet().unwrap().is_some());
    }

    #[test]
    fn codec_switch_rebuilds_encoder_and_target() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        assert_eq!(pipeline.channels(), 1);
        pipeline.set_codec(MUSIC_CODEC).unwrap();
        assert_eq!(pipeline.channels(), 2);
        assert_eq!(pipeline.codec(), MUSIC_CODEC);
        pipeline.begin();
        pipeline.push_capture(&loud_frame(2), OPUS_STEREO);
        assert!(pipeline.take_packet().unwrap().is_some());
    }

    #[test]
    fn unsupported_codec_is_rejected() {
        assert!(matches!(
            CapturePipeline::new(3),
            Err(AudioError::UnsupportedCodec(3))
        ));
    }

    #[test]
    fn buffer_is_bounded() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();
        for _ in 0..20 {
            pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        }
        assert!(pipeline.pcm.len() <= MAX_PENDING_FRAMES * FRAME_SAMPLES_PER_CHANNEL);
    }
}
