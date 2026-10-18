//! 播放侧流水线：按说话人的 jitter buffer + Opus 解码 + 10ms 混音。
//!
//! tsclient-rs 把 UDP 语音包的 16 位序号丢掉了，所以这里只能按到达时间做“固定目标
//! 延迟 + 有界队列”，不能真正重排序。接口保留 `VoiceFrame`，将来拿到 seq 时可以
//! 在 `JitterFrame` 上加序号而不动混音层。

use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant};

use crate::AudioError;
use crate::codec::OpusDecoder;
use crate::format::{MAX_OPUS_SAMPLES, MUSIC_CODEC, VOICE_CODEC};
use crate::softclip::soft_clip;

/// 10ms 混音 tick。
pub const MIX_FRAME_MS: u64 = 10;
pub const MIX_SAMPLES_PER_CHANNEL: usize = 480;
pub const MIX_SAMPLES: usize = MIX_SAMPLES_PER_CHANNEL * 2;

/// 首个包进入后等待的目标延迟；UDP 抖动靠它吸收。
const TARGET_DELAY: Duration = Duration::from_millis(60);
/// 队列上限；超过就丢最旧，避免延迟无限增长。
const MAX_JITTER_FRAMES: usize = 12;
/// 超过这个年龄的包直接丢，防止 60ms 包把延迟堆起来。
const MAX_JITTER_AGE: Duration = Duration::from_millis(200);
/// 连续丢包时最多做多少帧 PLC（30ms），再往后保持静音。
const MAX_PLC_FRAMES: u32 = 3;
/// 说话人无包多久后从混音中移除。
const TALKER_TIMEOUT: Duration = Duration::from_millis(500);
/// 20ms 淡入/淡出，按 10ms tick 每次走 0.5。
const FADE_STEP: f32 = 0.5;

#[derive(Debug, Clone)]
pub struct VoiceFrame {
    pub client_id: i32,
    pub codec: i32,
    pub data: Vec<u8>,
}

#[derive(Debug)]
struct JitterFrame {
    received_at: Instant,
    data: Vec<u8>,
}

struct Talker {
    decoder: OpusDecoder,
    jitter: VecDeque<JitterFrame>,
    pcm: VecDeque<f32>,
    decode_buffer: Vec<i16>,
    last_packet_at: Instant,
    gain: f32,
    plc_frames: u32,
    dropped: u64,
    has_decoded: bool,
}

impl Talker {
    fn new(now: Instant) -> Result<Self, AudioError> {
        Ok(Self {
            decoder: OpusDecoder::new()?,
            jitter: VecDeque::new(),
            pcm: VecDeque::new(),
            decode_buffer: vec![0i16; MAX_OPUS_SAMPLES],
            last_packet_at: now,
            gain: 0.0,
            plc_frames: 0,
            dropped: 0,
            has_decoded: false,
        })
    }

    fn push(&mut self, frame: VoiceFrame, now: Instant) {
        if frame.data.len() <= 1 {
            return;
        }
        if self.jitter.len() >= MAX_JITTER_FRAMES {
            self.jitter.pop_front();
            self.dropped += 1;
        }
        self.jitter.push_back(JitterFrame {
            received_at: now,
            data: frame.data,
        });
        while self
            .jitter
            .front()
            .is_some_and(|frame| now.saturating_duration_since(frame.received_at) > MAX_JITTER_AGE)
        {
            self.jitter.pop_front();
            self.dropped += 1;
        }
        self.last_packet_at = now;
    }

    fn fill(&mut self, now: Instant, needed: usize) -> Result<(), AudioError> {
        while self.pcm.len() < needed {
            if self.jitter.front().is_some_and(|frame| {
                now.saturating_duration_since(frame.received_at) > MAX_JITTER_AGE
            }) {
                self.jitter.pop_front();
                self.dropped += 1;
                continue;
            }
            let ready = self.jitter.front().is_some_and(|frame| {
                self.jitter.len() >= 3
                    || now.saturating_duration_since(frame.received_at) >= TARGET_DELAY
            });
            if ready {
                let frame = self.jitter.pop_front().expect("front checked");
                match self.decode(Some(&frame.data)) {
                    Ok(()) => {
                        self.plc_frames = 0;
                        self.has_decoded = true;
                    }
                    Err(_) => {
                        self.dropped += 1;
                    }
                }
                continue;
            }

            if self.has_decoded
                && self.is_active(now)
                && self.plc_frames < MAX_PLC_FRAMES
                && self.decode(None).is_ok()
            {
                self.plc_frames += 1;
                continue;
            }
            break;
        }
        Ok(())
    }

    fn decode(&mut self, packet: Option<&[u8]>) -> Result<(), AudioError> {
        let samples = self.decoder.decode(packet, &mut self.decode_buffer)?;
        if samples == 0 {
            return Ok(());
        }
        let count = (samples * 2).min(self.decode_buffer.len());
        self.pcm.extend(
            self.decode_buffer[..count]
                .iter()
                .map(|sample| *sample as f32 / 32768.0),
        );

        let max = MAX_OPUS_SAMPLES + MIX_SAMPLES;
        if self.pcm.len() > max {
            let drop = self.pcm.len() - MIX_SAMPLES * 2;
            self.pcm.drain(..drop);
            self.dropped += 1;
        }
        Ok(())
    }

    fn is_active(&self, now: Instant) -> bool {
        now.saturating_duration_since(self.last_packet_at) < TALKER_TIMEOUT || !self.pcm.is_empty()
    }

    fn is_done(&self, now: Instant) -> bool {
        !self.is_active(now) && self.pcm.is_empty() && self.gain <= 0.0
    }

    fn mix_into(&mut self, now: Instant, mix: &mut [f32]) {
        // 淡出只看最近是否有包，不看 PCM 余量；否则缓冲里的旧音频会拖住淡出。
        let target = if now.saturating_duration_since(self.last_packet_at) < TALKER_TIMEOUT {
            1.0
        } else {
            0.0
        };
        if self.gain < target {
            self.gain = (self.gain + FADE_STEP).min(target);
        } else if self.gain > target {
            self.gain = (self.gain - FADE_STEP).max(target);
        }

        let gain = self.gain;
        if gain <= 0.0 {
            if now.saturating_duration_since(self.last_packet_at) >= TALKER_TIMEOUT {
                self.pcm.clear();
                self.jitter.clear();
            }
            return;
        }
        for (target, sample) in mix.iter_mut().zip(self.pcm.iter()) {
            *target += *sample * gain;
        }
        let consumed = mix.len().min(self.pcm.len());
        self.pcm.drain(..consumed);
    }
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

    pub fn dropped_frames(&self) -> u64 {
        self.dropped
    }

    pub fn push_incoming(&mut self, frame: VoiceFrame, now: Instant) {
        if self.deafened
            || !matches!(frame.codec, VOICE_CODEC | MUSIC_CODEC)
            || frame.data.len() <= 1
        {
            return;
        }
        let client_id = frame.client_id;
        if let std::collections::hash_map::Entry::Vacant(entry) = self.talkers.entry(client_id) {
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
        let pcm: Vec<i16> = (0..FRAME_SAMPLES)
            .map(|index| ((index as f32 * 0.05 + tone).sin() * 12000.0) as i16)
            .collect();
        let mut output = [0u8; MAX_PACKET_BYTES];
        let written = encoder.encode(&pcm, &mut output).unwrap();
        output[..written].to_vec()
    }

    fn frame(client_id: i32, data: Vec<u8>) -> VoiceFrame {
        VoiceFrame {
            client_id,
            codec: MUSIC_CODEC,
            data,
        }
    }

    #[test]
    fn waits_for_target_delay_then_plays() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        pipeline.push_incoming(frame(1, packet(0.0)), t0);

        assert!(
            pipeline
                .tick(t0, MIX_SAMPLES_PER_CHANNEL)
                .samples
                .iter()
                .all(|sample| *sample == 0.0)
        );

        let tick = pipeline.tick(
            t0 + TARGET_DELAY + Duration::from_millis(10),
            MIX_SAMPLES_PER_CHANNEL,
        );
        assert!(tick.samples.iter().any(|sample| sample.abs() > 0.001));
        assert_eq!(tick.talkers, vec![1]);
    }

    #[test]
    fn burst_prebuffer_plays_without_waiting() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        for _ in 0..3 {
            pipeline.push_incoming(frame(2, packet(0.5)), t0);
        }
        let tick = pipeline.tick(t0, MIX_SAMPLES_PER_CHANNEL);
        assert!(tick.samples.iter().any(|sample| sample.abs() > 0.001));
    }

    #[test]
    fn silence_after_packets_uses_plc_then_stops() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        pipeline.push_incoming(frame(3, packet(0.2)), t0);
        let mut now = t0;
        for _ in 0..8 {
            now += Duration::from_millis(MIX_FRAME_MS);
            let tick = pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
            assert!(tick.samples.iter().all(|sample| sample.abs() <= 1.0));
        }
        // 超时后先淡出，再移除说话人。
        now += TALKER_TIMEOUT;
        for _ in 0..10 {
            now += Duration::from_millis(MIX_FRAME_MS);
            pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
        }
        assert!(pipeline.talker_count() == 0);
    }

    #[test]
    fn deafen_clears_and_renders_silence() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        pipeline.push_incoming(frame(4, packet(0.5)), t0);
        pipeline.set_deafened(true);
        let tick = pipeline.tick(
            t0 + TARGET_DELAY + Duration::from_millis(10),
            MIX_SAMPLES_PER_CHANNEL,
        );
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
                data: packet(0.5),
            },
            t0,
        );
        pipeline.push_incoming(frame(6, vec![0]), t0);
        assert_eq!(pipeline.talker_count(), 0);
    }

    #[test]
    fn mixes_multiple_talkers_without_clipping() {
        let mut pipeline = PlaybackPipeline::new();
        let t0 = Instant::now();
        for client_id in [7, 8, 9] {
            pipeline.push_incoming(frame(client_id, packet(client_id as f32)), t0);
        }
        let tick = pipeline.tick(
            t0 + TARGET_DELAY + Duration::from_millis(10),
            MIX_SAMPLES_PER_CHANNEL,
        );
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
}
