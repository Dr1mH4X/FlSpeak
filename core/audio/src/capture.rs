//! 采集侧流水线：设备格式 → 48kHz 目标格式 → VAD/PTT → 20ms Opus 帧。
//!
//! 这里不碰 cpal，也不做线程调度；线程循环在 `engine`，这样流水线可以用合成样本单测。

use std::collections::VecDeque;
use std::time::{Duration, Instant};

use nnnoiseless::DenoiseState;

use crate::codec::OpusEncoder;
use crate::convert::FormatConverter;
use crate::format::{
    AudioFormat, FRAME_SAMPLES_PER_CHANNEL, MAX_PACKET_BYTES, VOICE_CODEC, codec_format,
    frame_samples,
};
use crate::vad::{EnergyVad, Vad};
use crate::{AudioError, CodecError};

/// 采集缓冲上限：约 240ms。超过就丢到两帧，避免延迟累积。
const MAX_PENDING_FRAMES: usize = 12;
const RESYNC_FRAMES: usize = 2;

/// 开口首帧线性淡入时长：5ms @ 48kHz = 240 样本/声道。
pub const FADE_IN_FRAMES_PER_CHANNEL: usize = 240;
/// 停嘴末帧线性淡出时长：7.5ms @ 48kHz = 360 样本/声道（位于 5~10ms 区间）。
pub const FADE_OUT_FRAMES_PER_CHANNEL: usize = 360;
/// 触发编码器重置的连续静默帧阈值：2 秒（100 帧 × 20ms）。
pub const SILENCE_RESET_FRAMES: usize = 100;
/// RNNoise 16-bit PCM 幅值缩放系数。
const DENOISE_SCALE: f32 = 32768.0;

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

    pub fn is_due(&mut self, now: Instant) -> bool {
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

    pub fn due(&mut self, now: Instant, has_packet: bool) -> bool {
        if !has_packet {
            self.reset();
            return false;
        }
        self.is_due(now)
    }

    pub fn advance(&mut self) {
        if let Some(next) = self.next_send_at.take() {
            self.next_send_at = Some(next + self.frame);
        }
    }

    pub fn reset(&mut self) {
        self.next_send_at = None;
    }

    pub fn next_due_at(&self) -> Option<Instant> {
        self.next_send_at
    }
}

struct PendingPacket {
    packet: CapturePacket,
    pcm: Vec<f32>,
}

fn apply_fade_in(samples: &mut [f32], channels: u16) {
    let ch = (channels as usize).max(1);
    let total_frames = samples.len() / ch;
    let fade_frames = total_frames.min(FADE_IN_FRAMES_PER_CHANNEL);
    for i in 0..fade_frames {
        let gain = i as f32 / fade_frames as f32;
        for c in 0..ch {
            samples[i * ch + c] *= gain;
        }
    }
}

fn apply_fade_out(samples: &mut [f32], channels: u16) {
    let ch = (channels as usize).max(1);
    let total_frames = samples.len() / ch;
    if total_frames == 0 {
        return;
    }
    let fade_frames = total_frames.min(FADE_OUT_FRAMES_PER_CHANNEL);
    let start_frame = total_frames - fade_frames;
    let denom = (fade_frames - 1).max(1) as f32;
    for i in 0..fade_frames {
        let gain = (fade_frames - 1 - i) as f32 / denom;
        let idx = (start_frame + i) * ch;
        for c in 0..ch {
            samples[idx + c] *= gain;
        }
    }
}

pub struct CapturePipeline {
    codec: i32,
    encoder: OpusEncoder,
    denoiser: Box<DenoiseState<'static>>,
    noise_suppression: bool,
    target: AudioFormat,
    source: Option<AudioFormat>,
    converter: Option<FormatConverter>,
    converted: Vec<f32>,
    pcm: VecDeque<f32>,
    frame: Vec<f32>,
    preroll: Vec<f32>,
    pending_packets: VecDeque<PendingPacket>,
    last_sent_frame: Vec<f32>,
    last_frame_faded_out: bool,
    silent_frames: usize,
    encoder_dirty: bool,
    vad: Box<dyn Vad>,
    vad_threshold: f32,
    vad_hangover_frames: usize,
    muted: bool,
    deafened: bool,
    ptt_mode: bool,
    ptt_active: bool,
    speaking: bool,
    enabled: bool,
    received_any: bool,
    too_small_streak: usize,
}

impl CapturePipeline {
    pub fn new(codec: i32) -> Result<Self, AudioError> {
        let target = codec_format(codec).ok_or(AudioError::UnsupportedCodec(codec))?;
        let vad = EnergyVad::default();
        let vad_threshold = vad.threshold();
        let vad_hangover_frames = vad.hangover_frames() as usize;
        Ok(Self {
            codec,
            encoder: OpusEncoder::new(codec)?,
            denoiser: DenoiseState::new(),
            noise_suppression: true,
            target,
            source: None,
            converter: None,
            converted: Vec::new(),
            pcm: VecDeque::new(),
            frame: Vec::new(),
            preroll: Vec::new(),
            pending_packets: VecDeque::new(),
            last_sent_frame: Vec::new(),
            last_frame_faded_out: false,
            silent_frames: 0,
            encoder_dirty: false,
            vad: Box::new(vad),
            vad_threshold,
            vad_hangover_frames,
            muted: false,
            deafened: false,
            ptt_mode: false,
            ptt_active: false,
            speaking: false,
            enabled: false,
            received_any: false,
            too_small_streak: 0,
        })
    }

    pub fn codec(&self) -> i32 {
        self.codec
    }

    pub fn channels(&self) -> u16 {
        self.target.channels
    }

    pub fn set_noise_suppression(&mut self, enabled: bool) {
        if self.noise_suppression == enabled {
            return;
        }
        self.noise_suppression = enabled;
        self.denoiser = DenoiseState::new();
        self.preroll.clear();
    }

    pub fn noise_suppression(&self) -> bool {
        self.noise_suppression
    }

    pub fn encoder_reset_count(&self) -> u64 {
        self.encoder.reset_count()
    }

    pub fn last_encoded_pcm(&self) -> &[f32] {
        &self.last_sent_frame
    }

    pub fn has_pending_packets(&self) -> bool {
        !self.pending_packets.is_empty()
    }

    pub fn has_pending_eos(&self) -> bool {
        self.pending_packets
            .front()
            .is_some_and(|pending| pending.packet.data.is_empty())
    }

    pub fn set_vad_config(&mut self, threshold: f32, hangover_frames: usize) {
        let vad = EnergyVad::with_frames(threshold, hangover_frames);
        self.vad_threshold = vad.threshold();
        self.vad_hangover_frames = vad.hangover_frames() as usize;
        self.vad = Box::new(vad);
        if !self.ptt_mode && self.speaking {
            self.finish_speaking_with_tail(1);
        }
    }

    pub fn vad_config(&self) -> (f32, usize) {
        (self.vad_threshold, self.vad_hangover_frames)
    }

    pub fn begin(&mut self) {
        self.pcm.clear();
        self.preroll.clear();
        self.pending_packets.clear();
        self.last_sent_frame.clear();
        self.vad.reset();
        self.denoiser = DenoiseState::new();
        if self.encoder_dirty {
            let _ = self.encoder.reset();
            self.encoder_dirty = false;
        }
        self.speaking = false;
        self.silent_frames = 0;
        self.last_frame_faded_out = false;
        self.enabled = true;
        self.received_any = false;
    }

    pub fn end(&mut self) {
        if self.speaking {
            self.pending_packets.push_back(PendingPacket {
                packet: CapturePacket {
                    codec: self.codec,
                    data: Vec::new(),
                },
                pcm: Vec::new(),
            });
        }
        self.pcm.clear();
        self.preroll.clear();
        self.vad.reset();
        self.speaking = false;
        self.silent_frames = 0;
        self.last_frame_faded_out = false;
        self.enabled = false;
        self.received_any = false;
    }

    pub fn set_codec(&mut self, codec: i32) -> Result<(), AudioError> {
        if codec == self.codec {
            return Ok(());
        }
        let target = codec_format(codec).ok_or(AudioError::UnsupportedCodec(codec))?;
        let next_encoder = OpusEncoder::new(codec)?;
        if self.speaking {
            self.pending_packets.push_back(PendingPacket {
                packet: CapturePacket {
                    codec: self.codec,
                    data: Vec::new(),
                },
                pcm: Vec::new(),
            });
        }
        self.encoder = next_encoder;
        self.denoiser = DenoiseState::new();
        self.codec = codec;
        self.target = target;
        self.source = None;
        self.converter = None;
        self.pcm.clear();
        self.preroll.clear();
        self.last_sent_frame.clear();
        self.vad.reset();
        self.speaking = false;
        self.silent_frames = 0;
        self.encoder_dirty = false;
        self.last_frame_faded_out = false;
        self.received_any = false;
        self.too_small_streak = 0;
        Ok(())
    }

    pub fn set_deafened(&mut self, deafened: bool) {
        let was_deafened = self.deafened;
        self.deafened = deafened;
        if deafened {
            if self.speaking {
                self.finish_speaking_with_tail(1);
            }
            self.pcm.clear();
            self.preroll.clear();
            self.vad.reset();
            self.speaking = false;
            self.ptt_active = false;
        } else if was_deafened && !self.muted {
            self.pcm.clear();
            self.preroll.clear();
        }
    }

    pub fn set_muted(&mut self, muted: bool) {
        let was_muted = self.muted;
        self.muted = muted;
        if muted {
            if self.speaking {
                self.finish_speaking_with_tail(1);
            }
            self.pcm.clear();
            self.preroll.clear();
            self.vad.reset();
            self.speaking = false;
            self.ptt_active = false;
        } else if was_muted && !self.deafened {
            self.pcm.clear();
            self.preroll.clear();
        }
    }

    pub fn set_ptt_mode(&mut self, enabled: bool) {
        if self.ptt_mode == enabled {
            return;
        }
        if self.speaking {
            self.finish_speaking_with_tail(1);
        }
        self.ptt_mode = enabled;
        self.ptt_active = false;
        self.vad.reset();
        self.pcm.clear();
        self.preroll.clear();
        self.speaking = false;
    }

    pub fn set_ptt_active(&mut self, active: bool) {
        self.ptt_active = active;
        if !active {
            if self.speaking {
                self.finish_speaking_with_tail(2);
            }
            self.speaking = false;
            self.pcm.clear();
            self.preroll.clear();
        }
    }

    pub fn is_speaking(&self) -> bool {
        self.speaking && !self.muted
    }

    /// 采集链路是否真的在收样本：静音、聋听或未启动时电平应归零。
    pub fn is_capturing(&self) -> bool {
        self.enabled && !self.muted && !self.deafened
    }

    /// 缓冲是否已攒满一帧完整的 20ms PCM，或队列中存在待送出的收尾/Pre-roll 包。
    pub fn has_ready_frame(&self) -> bool {
        !self.pending_packets.is_empty()
            || (self.is_capturing()
                && self.received_any
                && self.pcm.len() >= frame_samples(self.target.channels))
    }

    /// 当前是否正处于主动发包阶段（PTT 按下或 VAD 语音段内）。
    pub fn is_transmitting(&self) -> bool {
        self.is_capturing()
            && if self.ptt_mode {
                self.ptt_active
            } else {
                self.speaking
            }
    }

    /// 追加设备原生格式的采集样本。
    pub fn push_capture(&mut self, samples: &[f32], source: AudioFormat) {
        if !self.enabled || self.muted || self.deafened || samples.is_empty() {
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

        let channels = (self.target.channels as usize).max(1);
        let frame_len = frame_samples(self.target.channels);
        let max = MAX_PENDING_FRAMES * frame_len;
        if self.pcm.len() > max {
            let keep = RESYNC_FRAMES * frame_len;
            let drop = self.pcm.len() - keep;
            let aligned_drop = drop - (drop % channels);
            self.pcm.drain(..aligned_drop);
        }
    }

    fn denoise_frame(&mut self, frame: &mut [f32]) {
        if self.codec != VOICE_CODEC || !self.noise_suppression {
            return;
        }
        let mut input_subframe = [0.0f32; DenoiseState::FRAME_SIZE];
        let mut output_subframe = [0.0f32; DenoiseState::FRAME_SIZE];
        for subframe in frame.as_chunks_mut::<{ DenoiseState::FRAME_SIZE }>().0 {
            for (dst, &src) in input_subframe.iter_mut().zip(subframe.iter()) {
                *dst = src * DENOISE_SCALE;
            }
            self.denoiser
                .process_frame(&mut output_subframe, &input_subframe);
            for (dst, &src) in subframe.iter_mut().zip(output_subframe.iter()) {
                *dst = (src / DENOISE_SCALE).clamp(-1.0, 1.0);
            }
        }
    }

    fn encode_pcm_frame(&mut self, frame: &mut [f32]) -> Result<Option<CapturePacket>, AudioError> {
        for sample in frame.iter_mut() {
            *sample = sample.clamp(-1.0, 1.0);
        }
        let mut packet = [0u8; MAX_PACKET_BYTES];
        let written = match self.encoder.encode(frame, &mut packet) {
            Ok(written) => {
                self.too_small_streak = 0;
                self.encoder_dirty = true;
                written
            }
            Err(AudioError::Codec(CodecError::BufferTooSmall { capacity: 0, .. })) => {
                crate::log_error!(
                    "encode output buffer capacity is 0, verify capture initialization"
                );
                return Err(AudioError::Codec(CodecError::BufferTooSmall {
                    capacity: 0,
                    max_data_bytes: MAX_PACKET_BYTES,
                }));
            }
            Err(AudioError::Codec(CodecError::BufferTooSmall {
                capacity,
                max_data_bytes,
            })) => {
                crate::log_warn!(capacity = capacity, max_data_bytes = max_data_bytes; "opus frame exceeded budget, degrading");
                self.too_small_streak += 1;
                if self.too_small_streak >= 50 {
                    return Err(AudioError::Codec(CodecError::BufferTooSmall {
                        capacity,
                        max_data_bytes,
                    }));
                }
                return Ok(None);
            }
            Err(err) => return Err(err),
        };
        Ok(Some(CapturePacket {
            codec: self.codec,
            data: packet[..written].to_vec(),
        }))
    }

    fn finish_speaking_with_tail(&mut self, max_full_frames: usize) {
        if !self.speaking {
            return;
        }
        self.speaking = false;
        self.silent_frames = 0;
        let was_faded_out = std::mem::replace(&mut self.last_frame_faded_out, false);

        if !was_faded_out && max_full_frames > 0 {
            let needed = frame_samples(self.target.channels);
            let ch = (self.target.channels as usize).max(1);
            let full_frames = (self.pcm.len() / needed).min(max_full_frames);
            let mut tail = std::mem::take(&mut self.frame);
            if full_frames > 0 {
                for idx in 0..full_frames {
                    tail.clear();
                    tail.extend(self.pcm.drain(..needed));
                    self.denoise_frame(&mut tail);
                    if idx + 1 == full_frames {
                        apply_fade_out(&mut tail, self.target.channels);
                    }
                    if let Ok(Some(pkt)) = self.encode_pcm_frame(&mut tail) {
                        self.pending_packets.push_back(PendingPacket {
                            packet: pkt,
                            pcm: tail.clone(),
                        });
                    }
                }
            } else {
                tail.clear();
                tail.resize(needed, 0.0);
                let avail_frames = (self.pcm.len() / ch).min(FRAME_SAMPLES_PER_CHANNEL);
                if avail_frames > 0 {
                    let count = avail_frames * ch;
                    for (dst, sample) in tail[..count].iter_mut().zip(self.pcm.drain(..count)) {
                        *dst = sample;
                    }
                    self.denoise_frame(&mut tail);
                    tail[count..].fill(0.0);
                    apply_fade_out(&mut tail[..count], self.target.channels);
                    if let Ok(Some(pkt)) = self.encode_pcm_frame(&mut tail) {
                        self.pending_packets.push_back(PendingPacket {
                            packet: pkt,
                            pcm: tail.clone(),
                        });
                    }
                } else {
                    let last_tail = self
                        .pending_packets
                        .back()
                        .filter(|p| !p.pcm.is_empty())
                        .map(|p| p.pcm.as_slice())
                        .unwrap_or(self.last_sent_frame.as_slice());
                    if last_tail.len() >= ch {
                        let base_offset = last_tail.len() - ch;
                        let fade_frames =
                            FADE_OUT_FRAMES_PER_CHANNEL.min(FRAME_SAMPLES_PER_CHANNEL);
                        let denom = (fade_frames - 1).max(1) as f32;
                        for i in 0..fade_frames {
                            let gain = (fade_frames - 1 - i) as f32 / denom;
                            for c in 0..ch {
                                tail[i * ch + c] = last_tail[base_offset + c] * gain;
                            }
                        }
                        if let Ok(Some(pkt)) = self.encode_pcm_frame(&mut tail) {
                            self.pending_packets.push_back(PendingPacket {
                                packet: pkt,
                                pcm: tail.clone(),
                            });
                        }
                    }
                }
            }
            tail.clear();
            self.frame = tail;
        }

        self.pending_packets.push_back(PendingPacket {
            packet: CapturePacket {
                codec: self.codec,
                data: Vec::new(),
            },
            pcm: Vec::new(),
        });
    }

    /// 产出下一帧完整 20ms 语音包（或收尾 EOS 空包）；样本未凑满 20ms 时等待下一批采集，绝不补零。
    pub fn take_packet(&mut self) -> Result<Option<CapturePacket>, AudioError> {
        if let Some(pending) = self.pending_packets.pop_front() {
            if !pending.pcm.is_empty() {
                self.last_sent_frame = pending.pcm;
            }
            return Ok(Some(pending.packet));
        }

        if !self.enabled || self.muted || self.deafened || !self.received_any {
            if self.muted || self.deafened {
                self.pcm.clear();
                self.preroll.clear();
            }
            return Ok(None);
        }

        let needed = frame_samples(self.target.channels);
        if self.pcm.len() < needed {
            return Ok(None);
        }

        let mut frame = std::mem::take(&mut self.frame);
        frame.clear();
        frame.extend(self.pcm.drain(..needed));
        self.denoise_frame(&mut frame);

        let should_send = if self.ptt_mode {
            self.ptt_active
        } else {
            self.vad.is_speech(&frame)
        };

        if !should_send {
            if !self.ptt_mode {
                self.preroll.clear();
                self.preroll.extend_from_slice(&frame);
            }
            let result = if self.speaking {
                self.speaking = false;
                self.silent_frames = 1;
                let was_faded_out = std::mem::replace(&mut self.last_frame_faded_out, false);
                if !was_faded_out {
                    apply_fade_out(&mut frame, self.target.channels);
                    if let Some(pkt) = self.encode_pcm_frame(&mut frame)? {
                        self.pending_packets.push_back(PendingPacket {
                            packet: pkt,
                            pcm: frame.clone(),
                        });
                    }
                }
                self.pending_packets.push_back(PendingPacket {
                    packet: CapturePacket {
                        codec: self.codec,
                        data: Vec::new(),
                    },
                    pcm: Vec::new(),
                });
                if let Some(pending) = self.pending_packets.pop_front() {
                    if !pending.pcm.is_empty() {
                        self.last_sent_frame = pending.pcm;
                    }
                    Some(pending.packet)
                } else {
                    None
                }
            } else {
                self.silent_frames = self.silent_frames.saturating_add(1);
                None
            };
            frame.clear();
            self.frame = frame;
            return Ok(result);
        }

        if !self.speaking {
            if self.encoder_dirty && self.silent_frames > SILENCE_RESET_FRAMES {
                self.encoder.reset()?;
            }
            self.speaking = true;
            self.silent_frames = 0;
            self.last_frame_faded_out = false;

            if !self.ptt_mode && self.preroll.len() == needed {
                let mut preroll = std::mem::take(&mut self.preroll);
                apply_fade_in(&mut preroll, self.target.channels);
                let preroll_pkt = self.encode_pcm_frame(&mut preroll)?;

                if self.vad.is_last_hangover_frame() {
                    apply_fade_out(&mut frame, self.target.channels);
                    self.last_frame_faded_out = true;
                }
                let trigger_pkt = self.encode_pcm_frame(&mut frame)?;

                if let Some(pkt) = preroll_pkt {
                    self.pending_packets.push_back(PendingPacket {
                        packet: pkt,
                        pcm: preroll.clone(),
                    });
                }
                if let Some(pkt) = trigger_pkt {
                    self.pending_packets.push_back(PendingPacket {
                        packet: pkt,
                        pcm: frame.clone(),
                    });
                }

                preroll.clear();
                self.preroll = preroll;
                frame.clear();
                self.frame = frame;

                if let Some(pending) = self.pending_packets.pop_front() {
                    if !pending.pcm.is_empty() {
                        self.last_sent_frame = pending.pcm;
                    }
                    return Ok(Some(pending.packet));
                }
                return Ok(None);
            }

            self.preroll.clear();
            apply_fade_in(&mut frame, self.target.channels);
            if !self.ptt_mode && self.vad.is_last_hangover_frame() {
                apply_fade_out(&mut frame, self.target.channels);
                self.last_frame_faded_out = true;
            }
            let pkt = self.encode_pcm_frame(&mut frame)?;
            if pkt.is_some() {
                self.last_sent_frame.clear();
                self.last_sent_frame.extend_from_slice(&frame);
            }
            frame.clear();
            self.frame = frame;
            return Ok(pkt);
        }

        if self.last_frame_faded_out {
            apply_fade_in(&mut frame, self.target.channels);
            self.last_frame_faded_out = false;
        }
        if !self.ptt_mode && self.vad.is_last_hangover_frame() {
            apply_fade_out(&mut frame, self.target.channels);
            self.last_frame_faded_out = true;
        }
        let pkt = self.encode_pcm_frame(&mut frame)?;
        if pkt.is_some() {
            self.last_sent_frame.clear();
            self.last_sent_frame.extend_from_slice(&frame);
        }
        frame.clear();
        self.frame = frame;
        Ok(pkt)
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

    fn speech_wave(channels: u16, amplitude: f32) -> Vec<f32> {
        let ch = channels as usize;
        let mut out = Vec::with_capacity(FRAME_SAMPLES_PER_CHANNEL * ch);
        for i in 0..FRAME_SAMPLES_PER_CHANNEL {
            let t = i as f32 / 48_000.0;
            let base = (2.0 * std::f32::consts::PI * 180.0 * t).sin()
                + 0.55 * (2.0 * std::f32::consts::PI * 360.0 * t).sin()
                + 0.3 * (2.0 * std::f32::consts::PI * 540.0 * t).sin();
            let sample = (base * 0.55 * amplitude).clamp(-1.0, 1.0);
            for _ in 0..ch {
                out.push(sample);
            }
        }
        out
    }

    fn loud_frame(channels: u16) -> Vec<f32> {
        speech_wave(channels, 0.55)
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
    fn music_talkspurts_fit_transport_and_decode_after_ptt_resets() {
        let mut pipeline = CapturePipeline::new(MUSIC_CODEC).unwrap();
        pipeline.begin();
        pipeline.set_ptt_mode(true);
        let samples: Vec<f32> = (0..frame_samples(2))
            .map(|index| (index as f32 * 0.0007).sin() * 0.92)
            .collect();
        let mut decoder = crate::codec::OpusDecoder::new().unwrap();
        let mut decoded = vec![0.0f32; crate::format::MAX_OPUS_SAMPLES];
        for _ in 0..3 {
            pipeline.set_ptt_active(true);
            pipeline.push_capture(&samples, OPUS_STEREO);
            let packet = pipeline.take_packet().unwrap().unwrap();
            assert!(packet.data.len() <= 484);
            assert_eq!(
                decoder.decode_normal(&packet.data, &mut decoded).unwrap(),
                FRAME_SAMPLES_PER_CHANNEL
            );
            pipeline.set_ptt_active(false);
            let tail = pipeline.take_packet().unwrap().expect("应产出淡出尾帧");
            assert!(tail.data.len() <= 484);
            assert_eq!(
                decoder.decode_normal(&tail.data, &mut decoded).unwrap(),
                FRAME_SAMPLES_PER_CHANNEL
            );
            let eos = pipeline.take_packet().unwrap().expect("应产出 EOS 尾包");
            assert!(eos.data.is_empty());
            assert!(pipeline.take_packet().unwrap().is_none());
        }
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

    #[test]
    fn partial_frames_wait_without_zero_padding_and_keep_phase() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();
        pipeline.set_ptt_mode(true);
        pipeline.set_ptt_active(true);

        // 模拟 512 样本回调（约 10.67ms），不足 960 样本时绝不补零发包。
        let first_half: Vec<f32> = (0..512).map(|i| (i as f32 * 0.03).sin() * 0.5).collect();
        pipeline.push_capture(&first_half, OPUS_MONO);
        assert!(!pipeline.has_ready_frame());
        assert!(pipeline.take_packet().unwrap().is_none());

        // 第二批到达后，512 + 512 = 1024 >= 960，产出完整 20ms 包且保留余下 64 样本。
        let second_half: Vec<f32> = (512..1024).map(|i| (i as f32 * 0.03).sin() * 0.5).collect();
        pipeline.push_capture(&second_half, OPUS_MONO);
        assert!(pipeline.has_ready_frame());
        let packet = pipeline.take_packet().unwrap().expect("凑满 20ms 应产出包");
        assert_eq!(pipeline.pcm.len(), 64);

        let mut decoder = crate::codec::OpusDecoder::new().unwrap();
        let mut decoded = vec![0.0f32; crate::format::MAX_OPUS_SAMPLES];
        let decoded_samples = decoder.decode_normal(&packet.data, &mut decoded).unwrap();
        assert_eq!(decoded_samples, FRAME_SAMPLES_PER_CHANNEL);
    }

    #[test]
    fn silent_frame_does_not_discard_samples_of_next_frame() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();
        // 推入 960 个静音 + 960 个有效语音：第一帧静音不应清空第二帧样本。
        let mut samples = vec![0.0; FRAME_SAMPLES_PER_CHANNEL];
        samples.extend(loud_frame(1));
        pipeline.push_capture(&samples, OPUS_MONO);

        assert!(pipeline.take_packet().unwrap().is_none());
        assert_eq!(pipeline.pcm.len(), FRAME_SAMPLES_PER_CHANNEL);
        assert!(pipeline.take_packet().unwrap().is_some());
    }

    #[test]
    fn vad_config_updates_threshold_and_hangover_frames() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.set_noise_suppression(false);
        pipeline.begin();
        // 提高门限到 0.5、hangover 为 2 帧：低能量帧留在 pre-roll，高能量触发后送出 pre-roll + 触发帧，并在随后 2 帧 hangover 后发 EOS。
        pipeline.set_vad_config(0.5, 2);
        let below = vec![0.3; FRAME_SAMPLES_PER_CHANNEL];
        let above = vec![0.6; FRAME_SAMPLES_PER_CHANNEL];
        let quiet = vec![0.0; FRAME_SAMPLES_PER_CHANNEL];

        pipeline.push_capture(&below, OPUS_MONO);
        assert!(pipeline.take_packet().unwrap().is_none());

        pipeline.push_capture(&above, OPUS_MONO);
        let preroll = pipeline.take_packet().unwrap().expect("pre-roll frame");
        assert!(!preroll.data.is_empty());
        let trigger = pipeline.take_packet().unwrap().expect("trigger frame");
        assert!(!trigger.data.is_empty());
        assert!(pipeline.take_packet().unwrap().is_none());

        pipeline.push_capture(&quiet, OPUS_MONO);
        let h1 = pipeline.take_packet().unwrap().expect("hangover 1");
        assert!(!h1.data.is_empty());

        pipeline.push_capture(&quiet, OPUS_MONO);
        let h2 = pipeline.take_packet().unwrap().expect("hangover 2");
        assert!(!h2.data.is_empty());

        pipeline.push_capture(&quiet, OPUS_MONO);
        let eos = pipeline.take_packet().unwrap().expect("EOS after hangover");
        assert!(eos.data.is_empty());
        assert!(pipeline.take_packet().unwrap().is_none());
    }

    #[test]
    fn vad_ptt_and_mute_emit_fade_out_tail_and_single_eos_packet() {
        // 1. VAD 挂断：末帧做线性淡出，随后紧跟 1 个 0 字节 EOS 尾包。
        let mut vad_pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        vad_pipeline.begin();
        vad_pipeline.set_vad_config(0.015, 1);
        let quiet = vec![0.0; FRAME_SAMPLES_PER_CHANNEL];
        vad_pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        assert!(vad_pipeline.take_packet().unwrap().is_some());

        let mut vad_packets = Vec::new();
        let mut last_non_eos_pcm = Vec::new();
        for _ in 0..5 {
            vad_pipeline.push_capture(&quiet, OPUS_MONO);
            while let Some(pkt) = vad_pipeline.take_packet().unwrap() {
                if !pkt.data.is_empty() {
                    last_non_eos_pcm = vad_pipeline.last_encoded_pcm().to_vec();
                }
                let is_eos = pkt.data.is_empty();
                vad_packets.push(pkt);
                if is_eos {
                    break;
                }
            }
            if vad_packets.last().is_some_and(|p| p.data.is_empty()) {
                break;
            }
        }
        assert!(vad_packets.len() >= 2, "应产出挂断淡出尾帧与 EOS 包");
        assert!(
            vad_packets.last().is_some_and(|p| p.data.is_empty()),
            "应产出 0 字节 EOS 尾包"
        );
        assert!(
            last_non_eos_pcm[FRAME_SAMPLES_PER_CHANNEL - 1].abs() < 1e-5,
            "VAD 挂断末帧末端应淡出至 0"
        );
        assert!(vad_pipeline.take_packet().unwrap().is_none());

        // 2. PTT 松开（包含已采入缓冲的 1 帧和队列无剩余样本两种情况）。
        let mut ptt_pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        ptt_pipeline.begin();
        ptt_pipeline.set_ptt_mode(true);
        ptt_pipeline.set_ptt_active(true);
        ptt_pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        ptt_pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        let first = ptt_pipeline.take_packet().unwrap().expect("PTT 首包");
        assert!(!first.data.is_empty());

        ptt_pipeline.set_ptt_active(false);
        let ptt_tail = ptt_pipeline.take_packet().unwrap().expect("PTT 淡出尾帧");
        assert!(!ptt_tail.data.is_empty());
        assert!(
            ptt_pipeline.last_encoded_pcm()[FRAME_SAMPLES_PER_CHANNEL - 1].abs() < 1e-5,
            "PTT 淡出尾帧末端应衰减至 0"
        );
        let ptt_eos = ptt_pipeline.take_packet().unwrap().expect("PTT EOS 尾包");
        assert!(ptt_eos.data.is_empty());
        assert!(ptt_pipeline.take_packet().unwrap().is_none());

        // 缓冲为空时松开 PTT 仍应补发淡出尾帧与 1 个 EOS 包。
        ptt_pipeline.set_ptt_active(true);
        ptt_pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        assert!(ptt_pipeline.take_packet().unwrap().is_some());
        ptt_pipeline.set_ptt_active(false);
        let synth_tail = ptt_pipeline.take_packet().unwrap().expect("合成淡出尾帧");
        assert!(!synth_tail.data.is_empty());
        assert!(ptt_pipeline.last_encoded_pcm()[FRAME_SAMPLES_PER_CHANNEL - 1].abs() < 1e-5);
        let synth_eos = ptt_pipeline.take_packet().unwrap().expect("合成后 EOS 包");
        assert!(synth_eos.data.is_empty());
        assert!(ptt_pipeline.take_packet().unwrap().is_none());

        // 3. 静音打断通话：同样输出淡出尾帧与 1 个 EOS 包。
        let mut mute_pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        mute_pipeline.begin();
        mute_pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        assert!(mute_pipeline.take_packet().unwrap().is_some());
        mute_pipeline.set_muted(true);
        let mute_tail = mute_pipeline.take_packet().unwrap().expect("静音淡出尾帧");
        assert!(!mute_tail.data.is_empty());
        assert!(mute_pipeline.last_encoded_pcm()[FRAME_SAMPLES_PER_CHANNEL - 1].abs() < 1e-5);
        let mute_eos = mute_pipeline.take_packet().unwrap().expect("静音 EOS 包");
        assert!(mute_eos.data.is_empty());
        assert!(mute_pipeline.take_packet().unwrap().is_none());
    }

    #[test]
    fn short_pause_keeps_opus_encoder_and_long_silence_resets() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();
        pipeline.set_vad_config(0.015, 1);
        let quiet = vec![0.0; FRAME_SAMPLES_PER_CHANNEL];

        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        assert!(pipeline.take_packet().unwrap().is_some());
        assert_eq!(pipeline.encoder_reset_count(), 0);

        // 短停顿 20 帧（400ms < 2s）：走完 hangover 与 EOS 后继续发言，不重建编码器。
        for _ in 0..20 {
            pipeline.push_capture(&quiet, OPUS_MONO);
            while pipeline.take_packet().unwrap().is_some() {}
        }
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        while pipeline.take_packet().unwrap().is_some() {}
        assert_eq!(pipeline.encoder_reset_count(), 0);

        // 长静默 105 帧（2.1s > 2s）：再次发言时重置编码器。
        for _ in 0..105 {
            pipeline.push_capture(&quiet, OPUS_MONO);
            while pipeline.take_packet().unwrap().is_some() {}
        }
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        assert!(pipeline.take_packet().unwrap().is_some());
        assert_eq!(pipeline.encoder_reset_count(), 1);
    }

    #[test]
    fn vad_preroll_prepends_one_frame_with_5ms_fade_in() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();
        pipeline.set_vad_config(0.05, 2);

        // 第 1 帧低能量（< 0.05）但非零：降噪后存入 pre-roll，暂不发包。
        let soft_onset = speech_wave(1, 0.03);
        pipeline.push_capture(&soft_onset, OPUS_MONO);
        assert!(pipeline.take_packet().unwrap().is_none());

        // 第 2 帧触发 VAD：一次产出 pre-roll + 触发帧共 2 包，且首帧前 5ms 从 0.0 线性淡入。
        pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        let preroll_pkt = pipeline.take_packet().unwrap().expect("应先输出 pre-roll");
        assert!(!preroll_pkt.data.is_empty());
        let preroll_pcm = pipeline.last_encoded_pcm().to_vec();
        assert_eq!(preroll_pcm[0], 0.0);
        assert!(
            preroll_pcm[FADE_IN_FRAMES_PER_CHANNEL..]
                .iter()
                .any(|s| s.abs() > 1e-4),
            "pre-roll 后段应保留有效音频"
        );
        assert!(
            preroll_pcm[1..FADE_IN_FRAMES_PER_CHANNEL]
                .iter()
                .map(|s| s.abs())
                .sum::<f32>()
                < preroll_pcm[FADE_IN_FRAMES_PER_CHANNEL..FADE_IN_FRAMES_PER_CHANNEL * 2]
                    .iter()
                    .map(|s| s.abs())
                    .sum::<f32>(),
            "前 5ms 应当处于淡入包络内"
        );

        assert!(pipeline.has_ready_frame());
        let trigger_pkt = pipeline.take_packet().unwrap().expect("紧接着输出触发帧");
        assert!(!trigger_pkt.data.is_empty());
        assert!(pipeline.take_packet().unwrap().is_none());
    }

    #[test]
    fn nnnoiseless_preserves_voice_in_voice_codec_and_bypasses_music_codec() {
        // VOICE_CODEC：启用 RNNoise 降噪（×32768 / ÷32768），正常人声保持可观幅值不被压成静音。
        let mut voice = CapturePipeline::new(VOICE_CODEC).unwrap();
        assert!(voice.noise_suppression());
        voice.begin();
        voice.set_ptt_mode(true);
        voice.set_ptt_active(true);

        let clean_voice = loud_frame(1);
        for _ in 0..3 {
            voice.push_capture(&clean_voice, OPUS_MONO);
            let pkt = voice.take_packet().unwrap().expect("语音帧应编码产出");
            assert!(!pkt.data.is_empty());
        }
        let denoised_rms = {
            let pcm = voice.last_encoded_pcm();
            (pcm.iter().map(|s| s * s).sum::<f32>() / pcm.len() as f32).sqrt()
        };
        assert!(
            denoised_rms > 0.08,
            "RNNoise 正常人声幅值不应被压成静音，实际 rms={denoised_rms}"
        );

        // MUSIC_CODEC：即使 noise_suppression=true 也必须自动旁路，不改变立体声原始波形。
        let mut music = CapturePipeline::new(MUSIC_CODEC).unwrap();
        music.begin();
        music.set_ptt_mode(true);
        music.set_ptt_active(true);
        let stereo = loud_frame(2);
        music.push_capture(&stereo, OPUS_STEREO);
        assert!(music.take_packet().unwrap().is_some());
        music.push_capture(&stereo, OPUS_STEREO);
        assert!(music.take_packet().unwrap().is_some());
        assert_eq!(music.last_encoded_pcm(), stereo.as_slice());
    }

    #[test]
    fn muted_and_deafened_skip_push_capture_without_accumulating_stale_pcm() {
        let mut pipeline = CapturePipeline::new(VOICE_CODEC).unwrap();
        pipeline.begin();

        pipeline.set_muted(true);
        for _ in 0..10 {
            pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        }
        assert!(pipeline.pcm.is_empty());
        assert!(pipeline.preroll.is_empty());
        pipeline.set_muted(false);
        assert!(pipeline.take_packet().unwrap().is_none());

        pipeline.set_deafened(true);
        for _ in 0..10 {
            pipeline.push_capture(&loud_frame(1), OPUS_MONO);
        }
        assert!(pipeline.pcm.is_empty());
        assert!(pipeline.preroll.is_empty());
        pipeline.set_deafened(false);
        assert!(pipeline.take_packet().unwrap().is_none());
    }
}
