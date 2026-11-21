//! 播放侧流水线：基于 `seq` 的自适应抖动缓冲 + FEC/PLC 三层恢复 + 平滑过渡 + 10ms 混音。

use std::collections::{BTreeMap, HashMap, VecDeque};
use std::time::{Duration, Instant};

use crate::AudioError;
use crate::codec::OpusDecoder;
use crate::format::{
    FRAME_MS, FRAME_SAMPLES, FRAME_SAMPLES_PER_CHANNEL, MAX_OPUS_SAMPLES, MUSIC_CODEC, VOICE_CODEC,
};
use crate::softclip::soft_clip;

/// 10ms 混音 tick。
pub const MIX_FRAME_MS: u64 = 10;
pub const MIX_SAMPLES_PER_CHANNEL: usize = 480;
pub const MIX_SAMPLES: usize = MIX_SAMPLES_PER_CHANNEL * 2;

/// 自适应目标延迟下界与上界（40ms..=160ms）。
const MIN_TARGET_DELAY_MS: f64 = 40.0;
const MAX_TARGET_DELAY_MS: f64 = 160.0;
/// Jitter 单次观测上限（ms），防止异常长静音间隔污染 EWMA。
const MAX_JITTER_SAMPLE_MS: f64 = 120.0;
/// 乱序重排窗口（允许领先当前播放序号的最大帧差）。
const MAX_REORDER_WINDOW: i16 = 50;
/// 连续无包且无 FEC 时最多做 4 帧（80ms）20ms PLC。
const MAX_PLC_FRAMES: u32 = 4;
/// 说话人无包多久后超时淡出并移除。
const TALKER_TIMEOUT: Duration = Duration::from_millis(500);
/// 起播、丢包恢复首帧及跳帧边界交叉淡变长度（4ms @ 48kHz）。
const RAMP_FRAMES: usize = 192;
/// 0 字节结束尾包的尾部逐样本淡出长度（7.5ms @ 48kHz，位于 5~10ms 区间）。
const EOS_FADE_FRAMES: usize = 360;
/// 无缓存剩余样本时合成的最短尾音淡出长度（5ms @ 48kHz）。
const MIN_EOS_TAIL_FRAMES: usize = 240;
/// 缓冲深度超出目标延迟的追赶触发余量（60ms）。
const CATCHUP_SLACK: Duration = Duration::from_millis(60);
/// 连续超限次数达到该阈值才执行追赶裁剪，避免瞬时突发误裁。
const CATCHUP_SUSTAINED_TICKS: u32 = 3;
/// 优先裁剪的低能量静音帧平均绝对振幅阈值。
const LOW_ENERGY_THRESHOLD: f32 = 0.008;
/// 第 2 帧 PLC 起的每样本指数衰减系数（约每 20ms 帧衰减至 23.6%）。
const PLC_DECAY_PER_SAMPLE: f32 = 0.9985;

#[derive(Debug, Clone)]
pub struct VoiceFrame {
    pub client_id: i32,
    pub codec: i32,
    pub seq: u16,
    pub received_at: Instant,
    pub is_end_of_stream: bool,
    pub data: Vec<u8>,
}

#[derive(Debug)]
struct JitterFrame {
    received_at: Instant,
    is_end_of_stream: bool,
    data: Vec<u8>,
}

struct Talker {
    decoder: OpusDecoder,
    reorder: BTreeMap<u16, JitterFrame>,
    expected_seq: Option<u16>,
    prebuffering: bool,
    prebuffer_started_at: Instant,
    end_of_stream_reached: bool,
    pcm: VecDeque<f32>,
    decode_buffer: Vec<f32>,
    scratch_buffer: Vec<f32>,
    last_packet_at: Instant,
    last_transit: Option<(u16, Instant)>,
    jitter_ms: f64,
    target_delay_ms: f64,
    plc_frames: u32,
    plc_gain: f32,
    needs_fade_in: bool,
    last_l: f32,
    last_r: f32,
    overload_streak: u32,
    dropped: u64,
    fec_recovered: u64,
    plc_generated: u64,
    has_decoded: bool,
}

impl Talker {
    fn new(now: Instant) -> Result<Self, AudioError> {
        Ok(Self {
            decoder: OpusDecoder::new()?,
            reorder: BTreeMap::new(),
            expected_seq: None,
            prebuffering: true,
            prebuffer_started_at: now,
            end_of_stream_reached: false,
            pcm: VecDeque::new(),
            decode_buffer: vec![0.0f32; MAX_OPUS_SAMPLES],
            scratch_buffer: vec![0.0f32; MAX_OPUS_SAMPLES],
            last_packet_at: now,
            last_transit: None,
            jitter_ms: 0.0,
            target_delay_ms: MIN_TARGET_DELAY_MS,
            plc_frames: 0,
            plc_gain: 1.0,
            needs_fade_in: true,
            last_l: 0.0,
            last_r: 0.0,
            overload_streak: 0,
            dropped: 0,
            fec_recovered: 0,
            plc_generated: 0,
            has_decoded: false,
        })
    }

    fn target_delay(&self) -> Duration {
        Duration::from_secs_f64(
            self.target_delay_ms
                .clamp(MIN_TARGET_DELAY_MS, MAX_TARGET_DELAY_MS)
                / 1000.0,
        )
    }

    fn update_jitter(&mut self, seq: u16, received_at: Instant) {
        if let Some((prev_seq, prev_at)) = self.last_transit {
            let seq_delta = seq.wrapping_sub(prev_seq) as i16;
            if seq_delta != 0 && seq_delta.abs() <= MAX_REORDER_WINDOW {
                let arrival_delta_ms = if received_at >= prev_at {
                    received_at.duration_since(prev_at).as_secs_f64() * 1000.0
                } else {
                    -(prev_at.duration_since(received_at).as_secs_f64() * 1000.0)
                };
                let nominal_delta_ms = f64::from(seq_delta) * FRAME_MS as f64;
                let transit_diff = (arrival_delta_ms - nominal_delta_ms)
                    .abs()
                    .min(MAX_JITTER_SAMPLE_MS);

                // 抬高快（0.25）、回落慢（RFC 3550 1/16），抑制目标延迟高频震荡。
                let alpha = if transit_diff > self.jitter_ms {
                    0.25
                } else {
                    1.0 / 16.0
                };
                self.jitter_ms += (transit_diff - self.jitter_ms) * alpha;

                let desired = (MIN_TARGET_DELAY_MS + 2.0 * self.jitter_ms)
                    .clamp(MIN_TARGET_DELAY_MS, MAX_TARGET_DELAY_MS);
                if desired > self.target_delay_ms {
                    self.target_delay_ms = desired;
                } else {
                    self.target_delay_ms += (desired - self.target_delay_ms) * 0.05;
                }
                self.target_delay_ms = self
                    .target_delay_ms
                    .clamp(MIN_TARGET_DELAY_MS, MAX_TARGET_DELAY_MS);
            }
        }
        self.last_transit = Some((seq, received_at));
    }

    fn resync_talkspurt(&mut self, frame: VoiceFrame, now: Instant) {
        self.reorder.clear();
        self.expected_seq = Some(frame.seq);
        self.prebuffering = self.pcm.is_empty();
        self.prebuffer_started_at = frame.received_at;
        self.end_of_stream_reached = false;
        self.plc_frames = 0;
        self.plc_gain = 1.0;
        self.needs_fade_in = true;
        self.overload_streak = 0;
        self.last_transit = Some((frame.seq, frame.received_at));
        self.last_packet_at = now.max(frame.received_at);
        self.reorder.insert(
            frame.seq,
            JitterFrame {
                received_at: frame.received_at,
                is_end_of_stream: false,
                data: frame.data,
            },
        );
    }

    fn push(&mut self, frame: VoiceFrame, now: Instant) {
        if !frame.is_end_of_stream && frame.data.len() <= 1 {
            return;
        }

        let timed_out = now.saturating_duration_since(self.last_packet_at) >= TALKER_TIMEOUT;
        let Some(exp) = self.expected_seq else {
            if frame.is_end_of_stream {
                return;
            }
            self.resync_talkspurt(frame, now);
            return;
        };

        if timed_out {
            if frame.is_end_of_stream {
                return;
            }
            self.resync_talkspurt(frame, now);
            return;
        }

        let diff = frame.seq.wrapping_sub(exp) as i16;
        if self.end_of_stream_reached {
            if frame.is_end_of_stream || diff < 0 {
                self.dropped += 1;
                return;
            }
            self.resync_talkspurt(frame, now);
            return;
        }

        if diff < 0 {
            self.dropped += 1;
            return;
        }

        if diff > MAX_REORDER_WINDOW {
            if frame.is_end_of_stream {
                self.dropped += 1;
                return;
            }
            self.resync_talkspurt(frame, now);
            return;
        }

        if self.reorder.contains_key(&frame.seq) {
            self.dropped += 1;
            return;
        }

        if !frame.is_end_of_stream {
            self.update_jitter(frame.seq, frame.received_at);
        }
        self.last_packet_at = now.max(frame.received_at);
        self.reorder.insert(
            frame.seq,
            JitterFrame {
                received_at: frame.received_at,
                is_end_of_stream: frame.is_end_of_stream,
                data: frame.data,
            },
        );
    }

    fn next_buffered_seq(&self, exp: u16) -> Option<u16> {
        self.reorder
            .keys()
            .copied()
            .filter(|&seq| (seq.wrapping_sub(exp) as i16) >= 0)
            .min_by_key(|&seq| seq.wrapping_sub(exp))
    }

    fn audio_packet_count(&self) -> usize {
        self.reorder
            .values()
            .filter(|frame| !frame.is_end_of_stream)
            .count()
    }

    fn has_end_of_stream(&self) -> bool {
        self.reorder.values().any(|frame| frame.is_end_of_stream)
    }

    fn buffered_duration(&self) -> Duration {
        let packet_ms = self.audio_packet_count() as u64 * FRAME_MS;
        let pcm_frames = (self.pcm.len() / 2) as u64;
        let pcm_us = pcm_frames * 1_000_000 / 48_000;
        Duration::from_millis(packet_ms) + Duration::from_micros(pcm_us)
    }

    fn apply_eos_fade(&mut self) {
        self.end_of_stream_reached = true;
        self.prebuffering = false;
        self.plc_frames = 0;
        self.overload_streak = 0;

        let available_frames = self.pcm.len() / 2;
        if available_frames > 0 {
            let fade_frames = available_frames.min(EOS_FADE_FRAMES);
            let start = self.pcm.len() - fade_frames * 2;
            for i in 0..fade_frames {
                let gain = (fade_frames - 1 - i) as f32 / fade_frames as f32;
                let idx = start + i * 2;
                self.pcm[idx] *= gain;
                self.pcm[idx + 1] *= gain;
            }
            self.last_l = 0.0;
            self.last_r = 0.0;
        } else if self.last_l.abs() > 1e-5 || self.last_r.abs() > 1e-5 {
            for i in 0..MIN_EOS_TAIL_FRAMES {
                let gain = (MIN_EOS_TAIL_FRAMES - 1 - i) as f32 / MIN_EOS_TAIL_FRAMES as f32;
                self.pcm.push_back(self.last_l * gain);
                self.pcm.push_back(self.last_r * gain);
            }
            self.last_l = 0.0;
            self.last_r = 0.0;
        }
        self.reorder.clear();
    }

    fn consume_eos_if_ready(&mut self) -> bool {
        let Some(exp) = self.expected_seq else {
            return false;
        };
        if self
            .reorder
            .get(&exp)
            .is_some_and(|frame| frame.is_end_of_stream)
        {
            self.reorder.remove(&exp);
            self.expected_seq = Some(exp.wrapping_add(1));
            self.apply_eos_fade();
            return true;
        }
        false
    }

    fn try_catch_up(&mut self) -> Result<bool, AudioError> {
        let Some(exp) = self.expected_seq else {
            return Ok(false);
        };
        let next = exp.wrapping_add(1);
        let both_audio = self.reorder.get(&exp).is_some_and(|f| !f.is_end_of_stream)
            && self.reorder.get(&next).is_some_and(|f| !f.is_end_of_stream);

        if !both_audio {
            if let Some(earliest) = self.next_buffered_seq(exp)
                && earliest != exp
            {
                self.expected_seq = Some(earliest);
                self.needs_fade_in = true;
                self.dropped += 1;
                return Ok(true);
            }
            return Ok(false);
        }

        let first = self.reorder.remove(&exp).expect("checked");
        let n1 = match self
            .decoder
            .decode_normal(&first.data, &mut self.scratch_buffer)
        {
            Ok(n) => n,
            Err(_) => {
                self.expected_seq = Some(next);
                self.dropped += 1;
                return Ok(true);
            }
        };
        let len1 = (n1 * 2).min(self.scratch_buffer.len());
        if mean_abs(&self.scratch_buffer[..len1]) < LOW_ENERGY_THRESHOLD {
            self.expected_seq = Some(next);
            self.needs_fade_in = true;
            self.dropped += 1;
            self.has_decoded = true;
            return Ok(true);
        }

        let second = self.reorder.remove(&next).expect("checked");
        self.expected_seq = Some(next.wrapping_add(1));
        self.has_decoded = true;

        let n2 = match self
            .decoder
            .decode_normal(&second.data, &mut self.decode_buffer)
        {
            Ok(n) => n,
            Err(_) => {
                push_pcm_frames(
                    &mut self.pcm,
                    &mut self.last_l,
                    &mut self.last_r,
                    &self.scratch_buffer[..len1],
                    self.needs_fade_in,
                );
                self.needs_fade_in = false;
                self.dropped += 1;
                return Ok(true);
            }
        };
        let len2 = (n2 * 2).min(self.decode_buffer.len());
        self.dropped += 1;

        if mean_abs(&self.decode_buffer[..len2]) < LOW_ENERGY_THRESHOLD {
            let frames = (len1 / 2).min(len2 / 2);
            let ramp = frames.min(RAMP_FRAMES);
            if ramp > 0 {
                let start_frame = frames - ramp;
                for i in 0..ramp {
                    let alpha = (i + 1) as f32 / ramp as f32;
                    let idx = (start_frame + i) * 2;
                    self.scratch_buffer[idx] =
                        self.scratch_buffer[idx] * (1.0 - alpha) + self.decode_buffer[idx] * alpha;
                    self.scratch_buffer[idx + 1] = self.scratch_buffer[idx + 1] * (1.0 - alpha)
                        + self.decode_buffer[idx + 1] * alpha;
                }
            }
            push_pcm_frames(
                &mut self.pcm,
                &mut self.last_l,
                &mut self.last_r,
                &self.scratch_buffer[..len1],
                self.needs_fade_in,
            );
            self.needs_fade_in = false;
            self.plc_frames = 0;
            self.plc_gain = 1.0;
            return Ok(true);
        }

        // 两帧均为高能量语音：跨整帧线性 Cross-fade 合并为单帧，避免跳帧爆音。
        let frames = (len1 / 2).min(len2 / 2);
        let denom = frames.saturating_sub(1).max(1) as f32;
        for i in 0..frames {
            let w = i as f32 / denom;
            self.scratch_buffer[i * 2] =
                self.scratch_buffer[i * 2] * (1.0 - w) + self.decode_buffer[i * 2] * w;
            self.scratch_buffer[i * 2 + 1] =
                self.scratch_buffer[i * 2 + 1] * (1.0 - w) + self.decode_buffer[i * 2 + 1] * w;
        }
        push_pcm_frames(
            &mut self.pcm,
            &mut self.last_l,
            &mut self.last_r,
            &self.scratch_buffer[..frames * 2],
            self.needs_fade_in,
        );
        self.needs_fade_in = false;
        self.plc_frames = 0;
        self.plc_gain = 1.0;
        Ok(true)
    }

    fn fill(&mut self, now: Instant, needed: usize) -> Result<(), AudioError> {
        if self.end_of_stream_reached {
            return Ok(());
        }
        if self.consume_eos_if_ready() {
            return Ok(());
        }

        let target_delay = self.target_delay();
        if self.prebuffering {
            let buffered_audio = Duration::from_millis(self.audio_packet_count() as u64 * FRAME_MS);
            let elapsed = now.saturating_duration_since(self.prebuffer_started_at);
            if elapsed >= target_delay || buffered_audio >= target_delay || self.has_end_of_stream()
            {
                self.prebuffering = false;
            } else {
                return Ok(());
            }
        }

        if self.buffered_duration() > target_delay + CATCHUP_SLACK {
            self.overload_streak = self.overload_streak.saturating_add(1);
            if self.overload_streak >= CATCHUP_SUSTAINED_TICKS {
                let _ = self.try_catch_up()?;
            }
        } else {
            self.overload_streak = 0;
        }

        while self.pcm.len() < needed {
            if self.consume_eos_if_ready() {
                break;
            }
            let Some(exp) = self.expected_seq else {
                break;
            };

            if let Some(frame) = self.reorder.remove(&exp) {
                self.expected_seq = Some(exp.wrapping_add(1));
                if frame.is_end_of_stream {
                    self.apply_eos_fade();
                    break;
                }
                match self
                    .decoder
                    .decode_normal(&frame.data, &mut self.decode_buffer)
                {
                    Ok(samples) if samples > 0 => {
                        let count = (samples * 2).min(self.decode_buffer.len());
                        let apply_ramp = self.needs_fade_in || self.plc_frames > 0;
                        push_pcm_frames(
                            &mut self.pcm,
                            &mut self.last_l,
                            &mut self.last_r,
                            &self.decode_buffer[..count],
                            apply_ramp,
                        );
                        self.plc_frames = 0;
                        self.plc_gain = 1.0;
                        self.needs_fade_in = false;
                        self.has_decoded = true;
                    }
                    Ok(_) => {
                        self.plc_frames = 0;
                        self.plc_gain = 1.0;
                    }
                    Err(_) => {
                        self.dropped += 1;
                    }
                }
                continue;
            }

            let next_seq = exp.wrapping_add(1);
            if let Some(next_frame) = self.reorder.get(&next_seq) {
                if next_frame.is_end_of_stream {
                    self.reorder.remove(&next_seq);
                    self.expected_seq = Some(next_seq.wrapping_add(1));
                    self.apply_eos_fade();
                    break;
                }
                self.expected_seq = Some(next_seq);
                let fec_result = self
                    .decoder
                    .decode_fec(&next_frame.data, &mut self.decode_buffer[..FRAME_SAMPLES]);
                if let Ok(samples) = fec_result
                    && samples > 0
                {
                    let count = (samples * 2).min(FRAME_SAMPLES);
                    let apply_ramp = self.needs_fade_in || self.plc_frames > 0;
                    push_pcm_frames(
                        &mut self.pcm,
                        &mut self.last_l,
                        &mut self.last_r,
                        &self.decode_buffer[..count],
                        apply_ramp,
                    );
                    self.plc_frames = 0;
                    self.plc_gain = 1.0;
                    self.needs_fade_in = false;
                    self.has_decoded = true;
                    self.fec_recovered += 1;
                } else {
                    self.dropped += 1;
                }
                continue;
            }

            if self.has_decoded && !self.end_of_stream_reached && self.plc_frames < MAX_PLC_FRAMES {
                if let Ok(samples) = self
                    .decoder
                    .decode_plc(&mut self.decode_buffer[..FRAME_SAMPLES])
                {
                    self.plc_frames += 1;
                    self.plc_generated += 1;
                    self.expected_seq = Some(exp.wrapping_add(1));
                    let frames = samples.min(FRAME_SAMPLES_PER_CHANNEL);
                    if frames > 0 {
                        if self.plc_frames >= 2 {
                            let tail_start = if self.plc_frames == MAX_PLC_FRAMES {
                                frames.saturating_sub(RAMP_FRAMES)
                            } else {
                                frames
                            };
                            for i in 0..frames {
                                self.plc_gain *= PLC_DECAY_PER_SAMPLE;
                                let tail_fade = if i >= tail_start && frames > tail_start {
                                    (frames - 1 - i) as f32 / (frames - tail_start) as f32
                                } else {
                                    1.0
                                };
                                let gain = self.plc_gain * tail_fade;
                                self.decode_buffer[i * 2] *= gain;
                                self.decode_buffer[i * 2 + 1] *= gain;
                            }
                            if self.plc_frames == MAX_PLC_FRAMES {
                                self.plc_gain = 0.0;
                                self.needs_fade_in = true;
                            }
                        }
                        push_pcm_frames(
                            &mut self.pcm,
                            &mut self.last_l,
                            &mut self.last_r,
                            &self.decode_buffer[..frames * 2],
                            false,
                        );
                    }
                    continue;
                }
                break;
            }

            // PLC 耗尽或尚未开播：若重排缓冲中有后续已就绪包，跳到最早可用包继续同步。
            if let Some(earliest) = self.next_buffered_seq(exp) {
                let is_ready = self.reorder.len() >= 2
                    || self.reorder.get(&earliest).is_some_and(|frame| {
                        frame.is_end_of_stream
                            || now.saturating_duration_since(frame.received_at) >= target_delay
                    });
                if is_ready {
                    self.expected_seq = Some(earliest);
                    self.needs_fade_in = true;
                    continue;
                }
            }
            break;
        }

        let _ = self.consume_eos_if_ready();
        Ok(())
    }

    fn is_active(&self, now: Instant) -> bool {
        if self.end_of_stream_reached && self.pcm.is_empty() && self.reorder.is_empty() {
            return false;
        }
        now.saturating_duration_since(self.last_packet_at) < TALKER_TIMEOUT || !self.pcm.is_empty()
    }

    fn is_done(&self, now: Instant) -> bool {
        !self.is_active(now) && self.pcm.is_empty()
    }

    fn mix_into(&mut self, now: Instant, mix: &mut [f32]) {
        if self.pcm.is_empty() {
            if now.saturating_duration_since(self.last_packet_at) >= TALKER_TIMEOUT {
                self.reorder.clear();
            }
            return;
        }

        let timed_out = now.saturating_duration_since(self.last_packet_at) >= TALKER_TIMEOUT;
        if timed_out {
            // 超时收尾做逐样本平滑淡出并清空余量。
            let fade_frames = (self.pcm.len() / 2).min(EOS_FADE_FRAMES);
            for i in 0..fade_frames {
                let gain = (fade_frames - 1 - i) as f32 / fade_frames as f32;
                let idx = i * 2;
                if idx + 1 < mix.len() {
                    mix[idx] += self.pcm[idx] * gain;
                    mix[idx + 1] += self.pcm[idx + 1] * gain;
                }
            }
            self.pcm.clear();
            self.reorder.clear();
            self.last_l = 0.0;
            self.last_r = 0.0;
            return;
        }

        let consumed = mix.len().min(self.pcm.len());
        for (target, sample) in mix.iter_mut().zip(self.pcm.iter()) {
            *target += *sample;
        }
        if consumed >= 2 {
            self.last_l = self.pcm[consumed - 2];
            self.last_r = self.pcm[consumed - 1];
        }
        self.pcm.drain(..consumed);
    }
}

fn push_pcm_frames(
    pcm: &mut VecDeque<f32>,
    last_l: &mut f32,
    last_r: &mut f32,
    samples: &[f32],
    apply_ramp: bool,
) {
    let frames = samples.len() / 2;
    if frames == 0 {
        return;
    }
    let ramp_frames = if apply_ramp {
        frames.min(RAMP_FRAMES)
    } else {
        0
    };
    let (prev_l, prev_r) = if pcm.len() >= 2 {
        let n = pcm.len();
        (pcm[n - 2], pcm[n - 1])
    } else {
        (*last_l, *last_r)
    };
    for i in 0..frames {
        let mut l = samples[i * 2];
        let mut r = samples[i * 2 + 1];
        if i < ramp_frames {
            let alpha = (i + 1) as f32 / ramp_frames as f32;
            l = l * alpha + prev_l * (1.0 - alpha);
            r = r * alpha + prev_r * (1.0 - alpha);
        }
        pcm.push_back(l);
        pcm.push_back(r);
    }
    if let (Some(&l), Some(&r)) = (
        pcm.get(pcm.len().saturating_sub(2)),
        pcm.get(pcm.len().saturating_sub(1)),
    ) {
        *last_l = l;
        *last_r = r;
    }
}

fn mean_abs(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    samples.iter().map(|s| s.abs()).sum::<f32>() / samples.len() as f32
}

/// 一个混音 tick 的产物。
#[derive(Debug, Clone)]
pub struct PlaybackTick {
    /// 48kHz 立体声交织样本，长度固定 `MIX_SAMPLES`。
    pub samples: Vec<f32>,
    /// 本 tick 仍活跃的说话人，用于低频 Speaking 事件。
    pub talkers: Vec<i32>,
}

pub struct PlaybackPipeline {
    talkers: HashMap<i32, Talker>,
    deafened: bool,
    dropped: u64,
}

impl PlaybackPipeline {
    pub fn new() -> Self {
        Self {
            talkers: HashMap::new(),
            deafened: false,
            dropped: 0,
        }
    }

    pub fn set_deafened(&mut self, deafened: bool) {
        self.deafened = deafened;
        if deafened {
            self.talkers.clear();
        }
    }

    pub fn restart(&mut self) {
        *self = Self {
            deafened: self.deafened,
            ..Self::new()
        };
    }

    pub fn dropped_frames(&self) -> u64 {
        self.dropped
    }

    pub fn push_incoming(&mut self, frame: VoiceFrame, now: Instant) {
        if self.deafened
            || !matches!(frame.codec, VOICE_CODEC | MUSIC_CODEC)
            || (!frame.is_end_of_stream && frame.data.len() <= 1)
        {
            return;
        }
        let client_id = frame.client_id;
        if let std::collections::hash_map::Entry::Vacant(entry) = self.talkers.entry(client_id) {
            if frame.is_end_of_stream {
                return;
            }
            match Talker::new(now) {
                Ok(talker) => {
                    entry.insert(talker);
                }
                Err(_) => {
                    self.dropped += 1;
                    return;
                }
            }
        }
        if let Some(talker) = self.talkers.get_mut(&client_id) {
            talker.push(frame, now);
        }
    }

    pub fn tick(&mut self, now: Instant, samples_per_channel: usize) -> PlaybackTick {
        let mut mix = vec![0.0f32; samples_per_channel * 2];
        let mut talkers = Vec::new();

        if self.deafened {
            return PlaybackTick {
                samples: mix,
                talkers,
            };
        }

        for (client_id, talker) in &mut self.talkers {
            if talker.fill(now, mix.len()).is_err() {
                self.dropped += 1;
            }
            talker.mix_into(now, &mut mix);
            if talker.is_active(now) {
                talkers.push(*client_id);
            }
        }
        talkers.sort_unstable();

        for sample in &mut mix {
            *sample = soft_clip(*sample);
        }

        self.talkers.retain(|_, talker| !talker.is_done(now));
        PlaybackTick {
            samples: mix,
            talkers,
        }
    }

    pub fn active_talkers(&self) -> Vec<i32> {
        let mut talkers: Vec<i32> = self.talkers.keys().copied().collect();
        talkers.sort_unstable();
        talkers
    }

    pub fn talker_count(&self) -> usize {
        self.talkers.len()
    }
}

impl Default for PlaybackPipeline {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::codec::OpusEncoder;
    use crate::format::{FRAME_SAMPLES, FRAME_SAMPLES_PER_CHANNEL, MAX_PACKET_BYTES, MUSIC_CODEC};

    fn packet(tone: f32) -> Vec<u8> {
        let mut encoder = OpusEncoder::new(MUSIC_CODEC).unwrap();
        let pcm: Vec<f32> = (0..FRAME_SAMPLES)
            .map(|index| (index as f32 * 0.05 + tone).sin() * 0.4)
            .collect();
        let mut output = [0u8; MAX_PACKET_BYTES];
        let written = encoder.encode(&pcm, &mut output).unwrap();
        output[..written].to_vec()
    }

    fn speech_packets(count: usize, amplitude: f32) -> Vec<Vec<u8>> {
        let mut encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        let mut output = [0u8; MAX_PACKET_BYTES];
        (0..count)
            .map(|frame_idx| {
                let pcm: Vec<f32> = (0..FRAME_SAMPLES_PER_CHANNEL)
                    .map(|i| {
                        let t = (frame_idx * FRAME_SAMPLES_PER_CHANNEL + i) as f32 / 48_000.0;
                        ((2.0 * std::f32::consts::PI * 180.0 * t).sin()
                            + 0.5 * (2.0 * std::f32::consts::PI * 540.0 * t).sin())
                            * amplitude
                    })
                    .collect();
                let written = encoder.encode(&pcm, &mut output).unwrap();
                output[..written].to_vec()
            })
            .collect()
    }

    fn frame(client_id: i32, seq: u16, received_at: Instant, data: Vec<u8>) -> VoiceFrame {
        VoiceFrame {
            client_id,
            codec: MUSIC_CODEC,
            seq,
            received_at,
            is_end_of_stream: false,
            data,
        }
    }

    fn voice_frame(client_id: i32, seq: u16, received_at: Instant, data: Vec<u8>) -> VoiceFrame {
        VoiceFrame {
            client_id,
            codec: VOICE_CODEC,
            seq,
            received_at,
            is_end_of_stream: false,
            data,
        }
    }

    fn eos_frame(client_id: i32, seq: u16, received_at: Instant) -> VoiceFrame {
        VoiceFrame {
            client_id,
            codec: VOICE_CODEC,
            seq,
            received_at,
            is_end_of_stream: true,
            data: Vec::new(),
        }
    }

    #[test]
    fn restarting_clears_old_audio_and_preserves_the_deafen_control() {
        for deafened in [false, true] {
            let mut pipeline = PlaybackPipeline::new();
            let now = Instant::now();
            pipeline.push_incoming(frame(1, 0, now, packet(0.0)), now);
            pipeline.set_deafened(deafened);
            pipeline.restart();
            let tick = pipeline.tick(
                now + Duration::from_millis(MIN_TARGET_DELAY_MS as u64),
                MIX_SAMPLES_PER_CHANNEL,
            );
            assert!(tick.talkers.is_empty());
            assert!(tick.samples.iter().all(|sample| *sample == 0.0));
            assert_eq!(pipeline.deafened, deafened);
        }
    }

    #[test]
    fn waits_for_target_delay_then_plays() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        pipeline.push_incoming(frame(1, 0, t0, packet(0.0)), t0);

        assert!(
            pipeline
                .tick(t0, MIX_SAMPLES_PER_CHANNEL)
                .samples
                .iter()
                .all(|sample| *sample == 0.0)
        );

        let tick = pipeline.tick(t0 + Duration::from_millis(45), MIX_SAMPLES_PER_CHANNEL);
        assert!(tick.samples.iter().any(|sample| sample.abs() > 0.001));
        assert_eq!(tick.talkers, vec![1]);
    }

    #[test]
    fn burst_prebuffer_plays_without_waiting() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        for seq in 0..3 {
            pipeline.push_incoming(frame(2, seq, t0, packet(0.5)), t0);
        }
        let tick = pipeline.tick(t0, MIX_SAMPLES_PER_CHANNEL);
        assert!(tick.samples.iter().any(|sample| sample.abs() > 0.001));
    }

    #[test]
    fn out_of_order_packets_are_reordered_without_drops() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        let pkts = speech_packets(6, 0.35);
        // 先到 seq 0，随后 2, 1, 4, 3, 5 乱序到达。
        let order = [0usize, 2, 1, 4, 3, 5];
        for (idx, &seq) in order.iter().enumerate() {
            let at = t0 + Duration::from_millis((idx as u64) * 5);
            pipeline.push_incoming(voice_frame(10, seq as u16, at, pkts[seq].clone()), at);
        }

        let talker = pipeline.talkers.get(&10).unwrap();
        assert_eq!(talker.dropped, 0);
        assert_eq!(talker.reorder.len(), 6);

        let mut now = t0 + Duration::from_millis(45);
        let mut active_samples = 0usize;
        for _ in 0..12 {
            let tick = pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
            active_samples += tick.samples.iter().filter(|s| s.abs() > 0.001).count();
            now += Duration::from_millis(MIX_FRAME_MS);
        }
        assert!(active_samples > 0);
        let talker = pipeline.talkers.get(&10).unwrap();
        assert_eq!(talker.dropped, 0);
        assert_eq!(talker.plc_generated, 0);
        assert_eq!(talker.fec_recovered, 0);
    }

    #[test]
    fn late_and_duplicate_packets_are_dropped_and_counted() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        let pkts = speech_packets(5, 0.3);

        pipeline.push_incoming(voice_frame(11, 10, t0, pkts[0].clone()), t0);
        pipeline.push_incoming(voice_frame(11, 11, t0, pkts[1].clone()), t0);
        // 重排缓冲内的重复包。
        pipeline.push_incoming(voice_frame(11, 11, t0, pkts[1].clone()), t0);
        assert_eq!(pipeline.talkers.get(&11).unwrap().dropped, 1);

        // 推进播放到 expected_seq == 12。
        let mut now = t0 + Duration::from_millis(45);
        for _ in 0..4 {
            pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
            now += Duration::from_millis(MIX_FRAME_MS);
        }
        assert_eq!(pipeline.talkers.get(&11).unwrap().expected_seq, Some(12));

        // 迟到包 seq 9 与 seq 10（diff < 0）均被丢弃并计入统计。
        pipeline.push_incoming(voice_frame(11, 9, now, pkts[2].clone()), now);
        pipeline.push_incoming(voice_frame(11, 10, now, pkts[3].clone()), now);
        assert_eq!(pipeline.talkers.get(&11).unwrap().dropped, 3);
    }

    #[test]
    fn u16_sequence_wraparound_orders_cleanly() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        let pkts = speech_packets(5, 0.35);

        // 围绕 65534 -> 65535 -> 0 -> 1 -> 2 跨界，并故意乱序先送 0、1 再送 65535。
        pipeline.push_incoming(voice_frame(12, 65534, t0, pkts[0].clone()), t0);
        pipeline.push_incoming(
            voice_frame(12, 0, t0 + Duration::from_millis(10), pkts[2].clone()),
            t0 + Duration::from_millis(10),
        );
        pipeline.push_incoming(
            voice_frame(12, 1, t0 + Duration::from_millis(15), pkts[3].clone()),
            t0 + Duration::from_millis(15),
        );
        pipeline.push_incoming(
            voice_frame(12, 65535, t0 + Duration::from_millis(20), pkts[1].clone()),
            t0 + Duration::from_millis(20),
        );
        pipeline.push_incoming(
            voice_frame(12, 2, t0 + Duration::from_millis(25), pkts[4].clone()),
            t0 + Duration::from_millis(25),
        );

        let mut now = t0 + Duration::from_millis(45);
        for _ in 0..10 {
            pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
            now += Duration::from_millis(MIX_FRAME_MS);
        }
        let talker = pipeline.talkers.get(&12).unwrap();
        assert_eq!(talker.dropped, 0);
        assert_eq!(talker.plc_generated, 0);
        assert_eq!(talker.expected_seq, Some(3));
    }

    #[test]
    fn end_of_stream_packet_fades_out_immediately_without_plc_or_500ms_wait() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        let pkts = speech_packets(3, 0.4);

        pipeline.push_incoming(voice_frame(13, 0, t0, pkts[0].clone()), t0);
        pipeline.push_incoming(voice_frame(13, 1, t0, pkts[1].clone()), t0);
        pipeline.push_incoming(
            eos_frame(13, 2, t0 + Duration::from_millis(20)),
            t0 + Duration::from_millis(20),
        );

        // 第 1 个 tick 播放前 10ms，同时 EOS 已消费并做好尾部淡出；无 PLC 触发。
        let mut now = t0 + Duration::from_millis(20);
        let mut ticks = Vec::new();
        for _ in 0..5 {
            ticks.push(pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL));
            now += Duration::from_millis(MIX_FRAME_MS);
        }
        // 40ms（2 帧语音 = 4 个 10ms tick）内播完并平滑归零，远小于 500ms 超时。
        assert_eq!(pipeline.talker_count(), 0);
        let last_non_empty = &ticks[3].samples;
        assert!(last_non_empty[last_non_empty.len() - 1].abs() < 1e-4);
        assert!(ticks[4].samples.iter().all(|s| *s == 0.0));
    }

    #[test]
    fn single_packet_loss_uses_fec_and_burst_loss_decays_plc_then_ramps_recovery() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        let pkts = speech_packets(14, 0.45);

        // 先送 seq 0, 1 正常播放，再丢弃 seq 2，送 seq 3 -> 触发 decode_fec(3) 恢复帧 2。
        pipeline.push_incoming(voice_frame(14, 0, t0, pkts[0].clone()), t0);
        pipeline.push_incoming(
            voice_frame(14, 1, t0 + Duration::from_millis(20), pkts[1].clone()),
            t0 + Duration::from_millis(20),
        );
        pipeline.push_incoming(
            voice_frame(14, 3, t0 + Duration::from_millis(60), pkts[3].clone()),
            t0 + Duration::from_millis(60),
        );

        let mut now = t0 + Duration::from_millis(45);
        for _ in 0..6 {
            pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
            now += Duration::from_millis(MIX_FRAME_MS);
        }
        {
            let talker = pipeline.talkers.get(&14).unwrap();
            assert_eq!(talker.fec_recovered, 1);
            assert_eq!(talker.plc_generated, 0);
        }

        // 随后连续丢包：运行 6 个 20ms 间隔（12 个 10ms tick），先播完队列里的 seq 3，再经历 4 帧 PLC 衰减至静音。
        let mut max_per_plc_tick = Vec::new();
        for _ in 0..12 {
            let tick = pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
            let peak = tick.samples.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
            max_per_plc_tick.push(peak);
            now += Duration::from_millis(MIX_FRAME_MS);
        }
        assert_eq!(
            pipeline.talkers.get(&14).unwrap().plc_generated,
            u64::from(MAX_PLC_FRAMES)
        );
        // 4 帧（8 个 10ms tick）PLC 期间能量应明显衰减，且在耗尽后归零。
        assert!(max_per_plc_tick[9] < max_per_plc_tick[2]);
        assert!(max_per_plc_tick[10] < 1e-4);
        assert!(max_per_plc_tick[11] < 1e-4);

        // 恢复包到达：通过恢复平滑过渡重新出声（样本连续且不跳变超过阈值）。
        pipeline.push_incoming(voice_frame(14, 10, now, pkts[10].clone()), now);
        pipeline.push_incoming(
            voice_frame(14, 11, now + Duration::from_millis(20), pkts[11].clone()),
            now + Duration::from_millis(20),
        );
        let recovered = pipeline.tick(now + Duration::from_millis(50), MIX_SAMPLES_PER_CHANNEL);
        assert!(recovered.samples.iter().any(|s| s.abs() > 0.01));
        assert!(
            recovered.samples[0].abs() < 0.08,
            "the first recovered frame should fade in smoothly"
        );
    }

    #[test]
    fn adaptive_target_delay_rises_quickly_on_jitter_and_decays_slowly() {
        let mut talker = Talker::new(Instant::now()).unwrap();
        let t0 = Instant::now();
        let pkts = speech_packets(8, 0.3);

        talker.push(voice_frame(1, 0, t0, pkts[0].clone()), t0);
        assert!((talker.target_delay_ms - 40.0).abs() < 1e-6);

        // 引入 45ms 突发到达抖动。
        talker.push(
            voice_frame(1, 1, t0 + Duration::from_millis(65), pkts[1].clone()),
            t0 + Duration::from_millis(65),
        );
        let spiked_delay = talker.target_delay_ms;
        assert!(
            spiked_delay > 55.0 && spiked_delay <= MAX_TARGET_DELAY_MS,
            "target_delay should rise quickly: {spiked_delay}"
        );

        // 恢复稳定 20ms 到达节奏，目标延迟缓慢回落且不会单帧归零。
        let mut at = t0 + Duration::from_millis(85);
        for (i, pkt) in pkts.iter().enumerate().take(6).skip(2) {
            talker.push(voice_frame(1, i as u16, at, pkt.clone()), at);
            at += Duration::from_millis(20);
        }
        assert!(talker.target_delay_ms < spiked_delay);
        assert!(talker.target_delay_ms > MIN_TARGET_DELAY_MS + 5.0);
    }

    #[test]
    fn catch_up_trims_silent_frames_first_and_crossfades_speech_backlog() {
        // 1. 低能量静音积压：优先裁剪低能量静音帧。
        let mut silent_encoder = OpusEncoder::new(VOICE_CODEC).unwrap();
        let mut buf = [0u8; MAX_PACKET_BYTES];
        let silent_pcm = vec![0.0f32; FRAME_SAMPLES_PER_CHANNEL];
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        for seq in 0..10u16 {
            let n = silent_encoder.encode(&silent_pcm, &mut buf).unwrap();
            let at = t0 + Duration::from_millis(u64::from(seq) * 20);
            pipeline.push_incoming(voice_frame(20, seq, at, buf[..n].to_vec()), t0);
        }
        // 10 帧 = 200ms > 40ms + 60ms，持续 3 个 tick 后触发静音裁剪。
        for i in 0..4 {
            pipeline.tick(
                t0 + Duration::from_millis(50 + i * 10),
                MIX_SAMPLES_PER_CHANNEL,
            );
        }
        assert!(pipeline.talkers.get(&20).unwrap().dropped > 0);

        // 2. 高能量语音积压：带 Cross-fade 跳帧消耗积压，无爆音削波。
        let mut speech_pipeline = PlaybackPipeline::new();
        let pkts = speech_packets(10, 0.45);
        for (seq, pkt) in pkts.into_iter().enumerate() {
            let at = t0 + Duration::from_millis(seq as u64 * 20);
            speech_pipeline.push_incoming(voice_frame(21, seq as u16, at, pkt), t0);
        }
        for i in 0..4 {
            let tick = speech_pipeline.tick(
                t0 + Duration::from_millis(50 + i * 10),
                MIX_SAMPLES_PER_CHANNEL,
            );
            assert!(tick.samples.iter().all(|s| s.abs() <= 1.0));
        }
        assert!(speech_pipeline.talkers.get(&21).unwrap().dropped > 0);
    }

    #[test]
    fn silence_after_packets_uses_plc_then_stops() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        pipeline.push_incoming(frame(3, 0, t0, packet(0.2)), t0);
        let mut now = t0 + Duration::from_millis(45);
        for _ in 0..10 {
            let tick = pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
            assert!(tick.samples.iter().all(|sample| sample.abs() <= 1.0));
            now += Duration::from_millis(MIX_FRAME_MS);
        }
        // 超时后先淡出，再移除说话人。
        now += TALKER_TIMEOUT;
        for _ in 0..10 {
            now += Duration::from_millis(MIX_FRAME_MS);
            pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
        }
        assert_eq!(pipeline.talker_count(), 0);
    }

    #[test]
    fn deafen_clears_and_renders_silence() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        pipeline.push_incoming(frame(4, 0, t0, packet(0.5)), t0);
        pipeline.set_deafened(true);
        let tick = pipeline.tick(t0 + Duration::from_millis(50), MIX_SAMPLES_PER_CHANNEL);
        assert!(tick.samples.iter().all(|sample| *sample == 0.0));
        assert_eq!(pipeline.talker_count(), 0);
    }

    #[test]
    fn ignores_bad_codec_and_control_frames() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        pipeline.push_incoming(
            VoiceFrame {
                client_id: 5,
                codec: 3,
                seq: 0,
                received_at: t0,
                is_end_of_stream: false,
                data: packet(0.5),
            },
            t0,
        );
        pipeline.push_incoming(frame(6, 0, t0, vec![0]), t0);
        assert_eq!(pipeline.talker_count(), 0);
    }

    #[test]
    fn mixes_multiple_talkers_without_clipping() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        for client_id in [7, 8, 9] {
            pipeline.push_incoming(frame(client_id, 0, t0, packet(client_id as f32)), t0);
        }
        let tick = pipeline.tick(t0 + Duration::from_millis(50), MIX_SAMPLES_PER_CHANNEL);
        assert!(tick.samples.iter().all(|sample| sample.abs() <= 1.0));
        assert!(tick.samples.iter().any(|sample| sample.abs() > 0.001));
    }

    #[test]
    fn output_frame_geometry() {
        let mut pipeline = PlaybackPipeline::new();
        let tick = pipeline.tick(Instant::now(), MIX_SAMPLES_PER_CHANNEL);
        assert_eq!(tick.samples.len(), MIX_SAMPLES);
        assert_eq!(MIX_SAMPLES_PER_CHANNEL, FRAME_SAMPLES_PER_CHANNEL / 2);
    }

    #[test]
    fn intermittent_short_talkspurts_from_capture_to_playback_trigger_no_plc_or_drops() {
        use crate::capture::CapturePipeline;
        use crate::format::OPUS_MONO;

        let mut capture = CapturePipeline::new(VOICE_CODEC).unwrap();
        capture.begin();
        capture.set_vad_config(0.015, 2);

        let mut playback = PlaybackPipeline::new();
        let mut now = Instant::now();
        let mut seq = 0u16;
        let client_id = 42;

        let speech: Vec<f32> = (0..FRAME_SAMPLES_PER_CHANNEL)
            .map(|i| {
                let t = i as f32 / 48_000.0;
                ((2.0 * std::f32::consts::PI * 190.0 * t).sin()
                    + 0.5 * (2.0 * std::f32::consts::PI * 380.0 * t).sin())
                    * 0.35
            })
            .collect();
        let quiet = vec![0.0f32; FRAME_SAMPLES_PER_CHANNEL];

        fn push_capture_packets(
            cap: &mut CapturePipeline,
            playback: &mut PlaybackPipeline,
            client_id: i32,
            seq: &mut u16,
            t: &mut Instant,
            peak: &mut f32,
        ) -> bool {
            let mut saw_eos = false;
            while let Some(pkt) = cap.take_packet().unwrap() {
                let is_eos = pkt.data.is_empty();
                saw_eos |= is_eos;
                playback.push_incoming(
                    VoiceFrame {
                        client_id,
                        codec: pkt.codec,
                        seq: *seq,
                        received_at: *t,
                        is_end_of_stream: is_eos,
                        data: pkt.data,
                    },
                    *t,
                );
                *seq = seq.wrapping_add(1);
                let first_tick = playback.tick(*t, MIX_SAMPLES_PER_CHANNEL);
                for sample in &first_tick.samples {
                    *peak = peak.max(sample.abs());
                }
                if !first_tick.talkers.is_empty() {
                    let second_tick = playback.tick(
                        *t + Duration::from_millis(MIX_FRAME_MS),
                        MIX_SAMPLES_PER_CHANNEL,
                    );
                    for sample in &second_tick.samples {
                        *peak = peak.max(sample.abs());
                    }
                }
                *t += Duration::from_millis(FRAME_MS);
            }
            saw_eos
        }

        // 第 1 段短促发言：3 帧语音 + 静音挂断至 EOS。
        let mut peak_1 = 0.0f32;
        for _ in 0..3 {
            capture.push_capture(&speech, OPUS_MONO);
            push_capture_packets(
                &mut capture,
                &mut playback,
                client_id,
                &mut seq,
                &mut now,
                &mut peak_1,
            );
        }
        let mut eos_1 = false;
        for _ in 0..6 {
            capture.push_capture(&quiet, OPUS_MONO);
            if push_capture_packets(
                &mut capture,
                &mut playback,
                client_id,
                &mut seq,
                &mut now,
                &mut peak_1,
            ) {
                eos_1 = true;
                break;
            }
        }
        assert!(eos_1, "the first utterance should emit an EOS tail packet");
        assert!(
            peak_1 > 0.01,
            "the first short utterance should decode to audible audio"
        );
        if let Some(talker) = playback.talkers.get(&client_id) {
            assert_eq!(talker.plc_generated, 0);
            assert_eq!(talker.dropped, 0);
        }

        // 停顿 120ms（< 500ms）：在余量播完前后均不触发 PLC。
        for _ in 0..12 {
            playback.tick(now, MIX_SAMPLES_PER_CHANNEL);
            if let Some(talker) = playback.talkers.get(&client_id) {
                assert_eq!(talker.plc_generated, 0);
                assert_eq!(talker.dropped, 0);
            }
            now += Duration::from_millis(MIX_FRAME_MS);
        }

        // 第 2 段短促发言：前部 seq 零丢弃且能正常解码出声。
        let mut decoded_peak = 0.0f32;
        for _ in 0..3 {
            capture.push_capture(&speech, OPUS_MONO);
            push_capture_packets(
                &mut capture,
                &mut playback,
                client_id,
                &mut seq,
                &mut now,
                &mut decoded_peak,
            );
        }
        let mut eos_2 = false;
        for _ in 0..6 {
            capture.push_capture(&quiet, OPUS_MONO);
            if push_capture_packets(
                &mut capture,
                &mut playback,
                client_id,
                &mut seq,
                &mut now,
                &mut decoded_peak,
            ) {
                eos_2 = true;
                break;
            }
        }
        assert!(eos_2, "the second utterance should emit an EOS tail packet");
        for _ in 0..10 {
            let tick = playback.tick(now, MIX_SAMPLES_PER_CHANNEL);
            for sample in &tick.samples {
                decoded_peak = decoded_peak.max(sample.abs());
            }
            if let Some(talker) = playback.talkers.get(&client_id) {
                assert_eq!(talker.plc_generated, 0);
                assert_eq!(talker.dropped, 0);
            }
            now += Duration::from_millis(MIX_FRAME_MS);
        }
        assert!(
            decoded_peak > 0.01,
            "the second short utterance should decode to audible audio"
        );
    }
}
