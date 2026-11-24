//! 音频引擎：采集与播放各占一条线程，cpal 回调只搬 `ArrayQueue`。

use std::sync::Arc;
use std::sync::mpsc::{Receiver, RecvTimeoutError, SyncSender, TrySendError, sync_channel};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::AudioError;
use crate::capture::{CapturePipeline, VoicePacer};
use crate::convert::FormatConverter;
use crate::device::{CaptureStream, PlaybackStream, start_capture, start_playback};
use crate::format::{AudioFormat, OPUS_STEREO};
use crate::level::{LevelMeter, LevelReading, MeterClock, SharedMeter, TransmitMeter, rms};
use crate::playback::{MIX_SAMPLES_PER_CHANNEL, PlaybackPipeline, VoiceFrame};
use crate::recovery::{RecoveryFailure, RecoveryState, StreamError, StreamErrorKind};

const CONTROL_CAPACITY: usize = 64;
const INCOMING_CAPACITY: usize = 256;
const IO_TICK_MS: u64 = 10;
const CAPTURE_POLL_MS: u64 = 5;
const PLAYBACK_POLL_MS: u64 = 5;
#[cfg(target_os = "android")]
pub const PLAYBACK_TARGET_WATERMARK_MS: u64 = 40;
#[cfg(not(target_os = "android"))]
pub const PLAYBACK_TARGET_WATERMARK_MS: u64 = 25;

#[cfg(target_os = "android")]
const MAX_PLAYBACK_TICKS_PER_WAKE: usize = 4;
#[cfg(not(target_os = "android"))]
const MAX_PLAYBACK_TICKS_PER_WAKE: usize = 2;
const CATCHUP_PACING_MS: u64 = 2;

pub fn playback_watermark_samples(format: AudioFormat) -> usize {
    let frames =
        ((format.sample_rate_hz as u64 * PLAYBACK_TARGET_WATERMARK_MS) / 1000).max(1) as usize;
    frames * (format.channels as usize).max(1)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioStage {
    Capture,
    Playback,
    Codec,
}

#[derive(Debug, Clone)]
pub enum AudioEvent {
    /// 已编码的语音包，由 actor 串行调用 `Client::send_voice`。
    Outbound {
        codec: i32,
        data: Vec<u8>,
        produced_at: Instant,
    },
    /// 本端 VAD/PTT 是否在发送，低频。
    SelfSpeaking {
        speaking: bool,
    },
    /// 远端活跃说话人集合变化。
    Talkers {
        client_ids: Vec<i32>,
    },
    CaptureState {
        ready: bool,
    },
    PlaybackState {
        ready: bool,
    },
    /// 用户指定的设备在重连或断流时已不存在，已回退为系统默认设备。
    DeviceFallback {
        stage: AudioStage,
    },
    Error {
        stage: AudioStage,
        message: String,
    },
}

enum CaptureCommand {
    Start {
        device: Option<String>,
        epoch: u64,
    },
    Stop,
    SetDevice {
        device: Option<String>,
    },
    SetMuted(bool),
    SetDeafened(bool),
    SetPttMode(bool),
    SetPttActive(bool),
    SetCodec(i32),
    SetNoiseSuppression(bool),
    GetNoiseSuppression(std::sync::mpsc::Sender<bool>),
    SetVad {
        threshold: f32,
        hangover_frames: usize,
    },
    GetVad(std::sync::mpsc::Sender<(f32, usize)>),
    Shutdown,
}

enum PlaybackCommand {
    Start { device: Option<String>, epoch: u64 },
    Stop,
    SetDevice { device: Option<String> },
    SetDeafened(bool),
    Incoming(VoiceFrame),
    Shutdown,
}

/// 接收侧处理器持有的句柄：只做 try_send，满了就丢包。
#[derive(Clone)]
pub struct IncomingVoiceSender {
    sender: SyncSender<PlaybackCommand>,
}

impl IncomingVoiceSender {
    pub fn send(&self, frame: VoiceFrame) {
        let _ = self.sender.try_send(PlaybackCommand::Incoming(frame));
    }
}

type EventSink = Arc<dyn Fn(AudioEvent) + Send + Sync>;
type LevelSink = Arc<dyn Fn(LevelReading) + Send + Sync>;

/// 音频引擎句柄。Drop 时关闭两条线程并等待 cpal 流释放。
pub struct VoiceEngine {
    capture: SyncSender<CaptureCommand>,
    playback: SyncSender<PlaybackCommand>,
    incoming: IncomingVoiceSender,
    meter: Arc<SharedMeter>,
    capture_thread: Option<JoinHandle<()>>,
    playback_thread: Option<JoinHandle<()>>,
}

impl VoiceEngine {
    pub fn spawn(
        sink: impl Fn(AudioEvent) + Send + Sync + 'static,
        levels: impl Fn(LevelReading) + Send + Sync + 'static,
    ) -> Result<Self, AudioError> {
        let sink: EventSink = Arc::new(sink);
        let levels: LevelSink = Arc::new(levels);
        let meter = Arc::new(SharedMeter::default());
        let (capture, capture_rx) = sync_channel(CONTROL_CAPACITY);
        let (playback, playback_rx) = sync_channel(CONTROL_CAPACITY);
        let (incoming, incoming_rx) = sync_channel(INCOMING_CAPACITY);

        let capture_thread = thread::Builder::new()
            .name("voice-capture".into())
            .spawn({
                let sink = Arc::clone(&sink);
                let meter = Arc::clone(&meter);
                move || capture_loop(capture_rx, sink, meter)
            })
            .map_err(|err| AudioError::Engine(err.to_string()))?;
        let playback_thread = thread::Builder::new()
            .name("voice-playback".into())
            .spawn({
                let sink = Arc::clone(&sink);
                let meter = Arc::clone(&meter);
                move || playback_loop(playback_rx, incoming_rx, sink, levels, meter)
            })
            .map_err(|err| AudioError::Engine(err.to_string()))?;

        Ok(Self {
            capture,
            playback,
            incoming: IncomingVoiceSender { sender: incoming },
            meter,
            capture_thread: Some(capture_thread),
            playback_thread: Some(playback_thread),
        })
    }

    pub fn incoming_sender(&self) -> IncomingVoiceSender {
        self.incoming.clone()
    }

    /// 由会话状态控制指标发布；指标不排入协议 actor 的音频事件队列。
    pub fn set_meter_epoch(&self, epoch: Option<u64>) {
        self.meter.set_epoch(epoch);
    }

    pub fn start_playback(&self, device: Option<String>) -> Result<(), AudioError> {
        self.playback
            .try_send(PlaybackCommand::Start {
                device,
                epoch: self.meter.epoch(),
            })
            .map_err(send_error)
    }

    pub fn stop_playback(&self) -> Result<(), AudioError> {
        self.playback
            .try_send(PlaybackCommand::Stop)
            .map_err(send_error)
    }

    pub fn start_capture(&self, device: Option<String>) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::Start {
                device,
                epoch: self.meter.epoch(),
            })
            .map_err(send_error)
    }

    pub fn stop_capture(&self) -> Result<(), AudioError> {
        self.meter.clear_mic();
        self.capture
            .try_send(CaptureCommand::Stop)
            .map_err(send_error)
    }

    pub fn stop(&self) -> Result<(), AudioError> {
        self.stop_capture()?;
        self.stop_playback()
    }

    pub fn set_input_device(&self, device: Option<String>) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::SetDevice { device })
            .map_err(send_error)
    }

    pub fn set_output_device(&self, device: Option<String>) -> Result<(), AudioError> {
        self.playback
            .try_send(PlaybackCommand::SetDevice { device })
            .map_err(send_error)
    }

    pub fn set_muted(&self, muted: bool) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::SetMuted(muted))
            .map_err(send_error)
    }

    pub fn set_ptt_mode(&self, enabled: bool) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::SetPttMode(enabled))
            .map_err(send_error)
    }

    pub fn set_ptt_active(&self, active: bool) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::SetPttActive(active))
            .map_err(send_error)
    }

    pub fn set_channel_codec(&self, codec: i32) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::SetCodec(codec))
            .map_err(send_error)
    }

    pub fn set_noise_suppression(&self, enabled: bool) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::SetNoiseSuppression(enabled))
            .map_err(send_error)
    }

    pub fn noise_suppression(&self) -> Result<bool, AudioError> {
        let (tx, rx) = std::sync::mpsc::channel();
        self.capture
            .try_send(CaptureCommand::GetNoiseSuppression(tx))
            .map_err(send_error)?;
        rx.recv()
            .map_err(|_| AudioError::Engine("audio thread has stopped".into()))
    }

    pub fn set_vad_config(&self, threshold: f32, hangover_frames: usize) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::SetVad {
                threshold,
                hangover_frames,
            })
            .map_err(send_error)
    }

    pub fn vad_config(&self) -> Result<(f32, usize), AudioError> {
        let (tx, rx) = std::sync::mpsc::channel();
        self.capture
            .try_send(CaptureCommand::GetVad(tx))
            .map_err(send_error)?;
        rx.recv()
            .map_err(|_| AudioError::Engine("audio thread has stopped".into()))
    }

    pub fn set_deafened(&self, deafened: bool) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::SetDeafened(deafened))
            .map_err(send_error)?;
        self.playback
            .try_send(PlaybackCommand::SetDeafened(deafened))
            .map_err(send_error)
    }
}

impl Drop for VoiceEngine {
    fn drop(&mut self) {
        let _ = self.capture.try_send(CaptureCommand::Shutdown);
        let _ = self.playback.try_send(PlaybackCommand::Shutdown);
        if let Some(thread) = self.capture_thread.take() {
            let _ = thread.join();
        }
        if let Some(thread) = self.playback_thread.take() {
            let _ = thread.join();
        }
    }
}

fn send_error<T>(err: TrySendError<T>) -> AudioError {
    match err {
        TrySendError::Full(_) => AudioError::Engine("audio command queue is full".into()),
        TrySendError::Disconnected(_) => AudioError::Engine("audio thread has stopped".into()),
    }
}

struct CaptureLoopState {
    pipeline: CapturePipeline,
    stream: Option<CaptureStream>,
    raw: Vec<f32>,
    device: Option<String>,
    want_active: bool,
    recovery: RecoveryState,
    speaking: bool,
    capture_epoch: u64,
    pacer: VoicePacer,
    mic_meter: TransmitMeter,
    sink: EventSink,
    meter: Arc<SharedMeter>,
}

impl CaptureLoopState {
    fn drain_stream(&mut self) -> Option<StreamError> {
        self.raw.clear();
        let stream = self.stream.as_ref()?;
        let max_drain = (stream.format.sample_rate_hz as usize)
            .saturating_mul(stream.format.channels as usize)
            / 2;
        stream.drain_into(&mut self.raw, max_drain.max(48_000 * 2 / 5));
        if !self.raw.is_empty() {
            self.pipeline.push_capture(&self.raw, stream.format);
        }
        stream.take_error()
    }

    fn sync_self_speaking(&mut self) {
        let now_speaking = self.pipeline.is_speaking();
        if now_speaking != self.speaking {
            self.speaking = now_speaking;
            (self.sink)(AudioEvent::SelfSpeaking {
                speaking: now_speaking,
            });
        }
    }

    fn meter_outbound(&mut self, is_eos: bool, now: Instant) {
        if is_eos {
            self.mic_meter.end_of_stream();
        } else {
            let level = rms(self.pipeline.last_encoded_pcm());
            self.mic_meter.packet(now, level);
        }
    }

    fn flush_pending_packets(&mut self, now: Instant) {
        while self.pipeline.has_pending_packets() {
            match self.pipeline.take_packet() {
                Ok(Some(packet)) => {
                    self.meter_outbound(packet.data.is_empty(), now);
                    (self.sink)(AudioEvent::Outbound {
                        codec: packet.codec,
                        data: packet.data,
                        produced_at: now,
                    });
                }
                Ok(None) => break,
                Err(err) => {
                    (self.sink)(AudioEvent::Error {
                        stage: AudioStage::Codec,
                        message: err.to_string(),
                    });
                    if !self.pipeline.has_pending_packets() {
                        break;
                    }
                }
            }
        }
        self.pacer.reset();
        self.sync_self_speaking();
    }

    fn handle_command(&mut self, command: CaptureCommand) -> bool {
        let now = Instant::now();
        match command {
            CaptureCommand::Shutdown => return false,
            CaptureCommand::Start { device, epoch } => {
                self.capture_epoch = epoch;
                self.mic_meter.silence();
                self.meter.clear_mic();
                self.want_active = true;
                self.device = device;
                self.recovery.reset();
                self.open_stream(now);
                self.speaking = false;
                self.pacer.reset();
            }
            CaptureCommand::Stop => {
                self.capture_epoch = 0;
                self.mic_meter.silence();
                self.meter.clear_mic();
                self.want_active = false;
                self.recovery.reset();
                drop(self.stream.take());
                self.pipeline.end();
                self.flush_pending_packets(now);
                (self.sink)(AudioEvent::CaptureState { ready: false });
            }
            CaptureCommand::SetDevice { device } => {
                self.mic_meter.silence();
                self.meter.clear_mic();
                self.device = device;
                if self.want_active {
                    self.pipeline.end();
                    self.flush_pending_packets(now);
                    self.recovery.reset();
                    self.open_stream(now);
                    self.speaking = false;
                    self.pacer.reset();
                }
            }
            CaptureCommand::SetMuted(next) => {
                self.pipeline.set_muted(next);
                if next {
                    self.flush_pending_packets(now);
                }
            }
            CaptureCommand::SetDeafened(deafened) => {
                self.pipeline.set_deafened(deafened);
                if deafened {
                    self.flush_pending_packets(now);
                }
            }
            CaptureCommand::SetPttMode(next) => {
                self.pipeline.set_ptt_mode(next);
                self.flush_pending_packets(now);
                (self.sink)(AudioEvent::CaptureState {
                    ready: self.stream.is_some(),
                });
            }
            CaptureCommand::SetPttActive(next) => {
                if !next
                    && self.pipeline.is_capturing()
                    && let Some(error) = self.drain_stream()
                {
                    self.handle_stream_error(error, now);
                }
                let was_transmitting = self.pipeline.is_transmitting();
                self.pipeline.set_ptt_active(next);
                if next && !was_transmitting {
                    self.mic_meter.silence();
                }
                if !next {
                    self.flush_pending_packets(now);
                }
                (self.sink)(AudioEvent::CaptureState {
                    ready: self.stream.is_some(),
                });
            }
            CaptureCommand::SetCodec(codec) => match self.pipeline.set_codec(codec) {
                Ok(()) => {
                    self.flush_pending_packets(now);
                }
                Err(err) => (self.sink)(AudioEvent::Error {
                    stage: AudioStage::Codec,
                    message: err.to_string(),
                }),
            },
            CaptureCommand::SetNoiseSuppression(enabled) => {
                self.pipeline.set_noise_suppression(enabled);
            }
            CaptureCommand::GetNoiseSuppression(reply) => {
                let _ = reply.send(self.pipeline.noise_suppression());
            }
            CaptureCommand::SetVad {
                threshold,
                hangover_frames,
            } => {
                self.pipeline.set_vad_config(threshold, hangover_frames);
                self.flush_pending_packets(now);
            }
            CaptureCommand::GetVad(reply) => {
                let _ = reply.send(self.pipeline.vad_config());
            }
        }
        true
    }

    fn open_stream(&mut self, now: Instant) {
        drop(self.stream.take());
        match attempt_open_stream(
            &mut self.device,
            AudioStage::Capture,
            &mut self.recovery,
            &self.sink,
            now,
            start_capture,
        ) {
            Some(next) => {
                self.pipeline.begin();
                self.stream = Some(next);
                (self.sink)(AudioEvent::CaptureState { ready: true });
            }
            None => {
                self.pipeline.end();
                (self.sink)(AudioEvent::CaptureState { ready: false });
            }
        }
    }

    fn handle_stream_error(&mut self, error: StreamError, now: Instant) {
        let action = classify_active_stream_error(AudioStage::Capture, error);
        match action {
            ActiveErrorAction::Keep => {}
            ActiveErrorAction::FailPermanent(message) => {
                drop(self.stream.take());
                self.pipeline.end();
                self.flush_pending_packets(now);
                self.recovery.on_open_failed(now, false);
                (self.sink)(AudioEvent::CaptureState { ready: false });
                (self.sink)(AudioEvent::Error {
                    stage: AudioStage::Capture,
                    message,
                });
            }
            ActiveErrorAction::Rebuild => {
                drop(self.stream.take());
                self.pipeline.end();
                self.flush_pending_packets(now);
                (self.sink)(AudioEvent::CaptureState { ready: false });
                if self.want_active {
                    self.recovery.reset();
                    self.open_stream(now);
                }
            }
        }
    }
}

fn capture_loop(commands: Receiver<CaptureCommand>, sink: EventSink, meter: Arc<SharedMeter>) {
    let pipeline = match CapturePipeline::new(crate::format::VOICE_CODEC) {
        Ok(pipeline) => pipeline,
        Err(err) => {
            sink(AudioEvent::Error {
                stage: AudioStage::Codec,
                message: err.to_string(),
            });
            return;
        }
    };
    let mut state = CaptureLoopState {
        pipeline,
        stream: None,
        raw: Vec::new(),
        device: None,
        want_active: false,
        recovery: RecoveryState::default(),
        speaking: false,
        capture_epoch: 0,
        pacer: VoicePacer::default(),
        mic_meter: TransmitMeter::default(),
        sink,
        meter,
    };
    let idle_tick = Duration::from_millis(IO_TICK_MS);
    let poll_tick = Duration::from_millis(CAPTURE_POLL_MS);
    let catchup_spacing = Duration::from_millis(CATCHUP_PACING_MS);

    'capture: loop {
        let now = Instant::now();
        let wait = if let Some(deadline) = state.recovery.next_deadline() {
            deadline.saturating_duration_since(now).min(idle_tick)
        } else if state.stream.is_none() {
            idle_tick
        } else if state.pipeline.has_ready_frame()
            && state.pipeline.is_transmitting()
            && !state.pipeline.has_pending_eos()
        {
            match state.pacer.next_due_at() {
                Some(due) if due <= now => catchup_spacing,
                Some(due) => due.saturating_duration_since(now).min(poll_tick),
                None => poll_tick,
            }
        } else {
            poll_tick
        };
        match commands.recv_timeout(wait) {
            Ok(command) => {
                if !state.handle_command(command) {
                    break 'capture;
                }
                while let Ok(command) = commands.try_recv() {
                    if !state.handle_command(command) {
                        break 'capture;
                    }
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break 'capture,
        }

        let now = Instant::now();
        if state.want_active && state.stream.is_none() && state.recovery.due_for_retry(now) {
            state.open_stream(now);
        }

        state.raw.clear();
        if state.stream.is_some()
            && let Some(error) = state.drain_stream()
        {
            state.handle_stream_error(error, now);
        }

        let send_now = Instant::now();
        while state.pipeline.has_ready_frame() {
            if state.pipeline.is_transmitting()
                && !state.pipeline.has_pending_eos()
                && !state.pacer.is_due(send_now)
            {
                break;
            }
            match state.pipeline.take_packet() {
                Ok(Some(packet)) => {
                    let is_eos = packet.data.is_empty();
                    state.meter_outbound(is_eos, send_now);
                    if !is_eos {
                        let _ = state.pacer.is_due(send_now);
                    }
                    (state.sink)(AudioEvent::Outbound {
                        codec: packet.codec,
                        data: packet.data,
                        produced_at: send_now,
                    });
                    if is_eos {
                        state.pacer.reset();
                    } else {
                        state.pacer.advance();
                        if !state.pipeline.has_pending_eos() {
                            break;
                        }
                    }
                }
                Ok(None) => {
                    state.pacer.reset();
                }
                Err(err) => {
                    (state.sink)(AudioEvent::Error {
                        stage: AudioStage::Codec,
                        message: err.to_string(),
                    });
                    if !state.pipeline.has_pending_packets() {
                        break;
                    }
                }
            }
        }
        if !state.pipeline.is_capturing() {
            state.pacer.reset();
        }

        let mic = if state.stream.is_some() && state.pipeline.is_capturing() {
            state.mic_meter.tick(Instant::now())
        } else {
            state.mic_meter.silence()
        };
        // 只是共享给 playback 线程合成事件；跨 FFI 的频率由那边控制。
        state.meter.store_mic(state.capture_epoch, mic);

        state.sync_self_speaking();
    }

    drop(state.stream.take());
    state.meter.clear_mic();
    (state.sink)(AudioEvent::CaptureState { ready: false });
}

struct PlaybackLoopState {
    pipeline: PlaybackPipeline,
    stream: Option<PlaybackStream>,
    converter: Option<FormatConverter>,
    converted: Vec<f32>,
    device: Option<String>,
    want_active: bool,
    recovery: RecoveryState,
    sink: EventSink,
    levels: LevelSink,
    meter: Arc<SharedMeter>,
    received_meter: LevelMeter,
    received_clock: MeterClock,
    last_received_level: f32,
    playback_epoch: u64,
    last_talkers: Vec<i32>,
}

impl PlaybackLoopState {
    fn handle_command(&mut self, command: PlaybackCommand) -> bool {
        let now = Instant::now();
        match command {
            PlaybackCommand::Shutdown => return false,
            PlaybackCommand::Start { device, epoch } => {
                self.playback_epoch = epoch;
                self.last_received_level = self.received_meter.silence();
                self.received_clock = MeterClock::default();
                self.pipeline.restart();
                self.want_active = true;
                self.device = device;
                self.recovery.reset();
                self.open_stream(now);
            }
            PlaybackCommand::Stop => {
                self.playback_epoch = 0;
                self.last_received_level = self.received_meter.silence();
                self.want_active = false;
                self.recovery.reset();
                drop(self.stream.take());
                self.converter = None;
                self.pipeline = PlaybackPipeline::new();
                (self.sink)(AudioEvent::PlaybackState { ready: false });
            }
            PlaybackCommand::SetDevice { device } => {
                self.last_received_level = self.received_meter.silence();
                self.device = device;
                if self.want_active {
                    self.recovery.reset();
                    self.open_stream(now);
                }
            }
            PlaybackCommand::SetDeafened(deafened) => self.pipeline.set_deafened(deafened),
            PlaybackCommand::Incoming(frame) => {
                self.pipeline.push_incoming(frame, now);
            }
        }
        true
    }

    fn open_stream(&mut self, now: Instant) {
        drop(self.stream.take());
        match attempt_open_stream(
            &mut self.device,
            AudioStage::Playback,
            &mut self.recovery,
            &self.sink,
            now,
            start_playback,
        ) {
            Some(next) => {
                self.converter = Some(FormatConverter::new(OPUS_STEREO, next.format));
                self.stream = Some(next);
                (self.sink)(AudioEvent::PlaybackState { ready: true });
            }
            None => {
                self.converter = None;
                (self.sink)(AudioEvent::PlaybackState { ready: false });
            }
        }
    }

    fn poll_playback(&mut self, now: Instant) -> usize {
        let mut ticks = 0;
        if let (Some(stream), Some(converter)) = (&self.stream, &mut self.converter) {
            let target_watermark = playback_watermark_samples(stream.format);
            while ticks < MAX_PLAYBACK_TICKS_PER_WAKE
                && stream.buffered_samples() < target_watermark
            {
                let tick = self.pipeline.tick(now, MIX_SAMPLES_PER_CHANNEL);
                self.last_received_level = if !tick.talkers.is_empty() {
                    self.received_meter.update(rms(&tick.samples))
                } else {
                    self.received_meter.silence()
                };
                if tick.talkers != self.last_talkers {
                    self.last_talkers = tick.talkers.clone();
                    (self.sink)(AudioEvent::Talkers {
                        client_ids: self.last_talkers.clone(),
                    });
                }
                self.converted.clear();
                converter.process(&tick.samples, &mut self.converted);
                for sample in &mut self.converted {
                    *sample = sample.clamp(-1.0, 1.0);
                }
                stream.push(&self.converted);
                ticks += 1;
            }
            if let Some(error) = stream.take_error() {
                self.handle_stream_error(error, now);
            }
        } else {
            self.last_received_level = self.received_meter.silence();
        }

        if self.received_clock.due(now) {
            let epoch = self.meter.epoch();
            let received = if epoch == self.playback_epoch {
                self.last_received_level
            } else {
                0.0
            };
            if let Some(reading) = self.meter.reading(epoch, received) {
                (self.levels)(reading);
            }
        }
        ticks
    }

    fn handle_stream_error(&mut self, error: StreamError, now: Instant) {
        let action = classify_active_stream_error(AudioStage::Playback, error);
        match action {
            ActiveErrorAction::Keep => {}
            ActiveErrorAction::FailPermanent(message) => {
                drop(self.stream.take());
                self.converter = None;
                self.last_received_level = self.received_meter.silence();
                self.recovery.on_open_failed(now, false);
                (self.sink)(AudioEvent::PlaybackState { ready: false });
                (self.sink)(AudioEvent::Error {
                    stage: AudioStage::Playback,
                    message,
                });
            }
            ActiveErrorAction::Rebuild => {
                drop(self.stream.take());
                self.converter = None;
                self.last_received_level = self.received_meter.silence();
                (self.sink)(AudioEvent::PlaybackState { ready: false });
                if self.want_active {
                    self.recovery.reset();
                    self.open_stream(now);
                }
            }
        }
    }
}

fn playback_loop(
    commands: Receiver<PlaybackCommand>,
    incoming: Receiver<PlaybackCommand>,
    sink: EventSink,
    levels: LevelSink,
    meter: Arc<SharedMeter>,
) {
    let mut state = PlaybackLoopState {
        pipeline: PlaybackPipeline::new(),
        stream: None,
        converter: None,
        converted: Vec::new(),
        device: None,
        want_active: false,
        recovery: RecoveryState::default(),
        sink,
        levels,
        meter,
        received_meter: LevelMeter::default(),
        received_clock: MeterClock::default(),
        last_received_level: 0.0,
        playback_epoch: 0,
        last_talkers: Vec::new(),
    };
    let poll_tick = Duration::from_millis(PLAYBACK_POLL_MS);
    let mut next_poll = Instant::now();

    'playback: loop {
        let now = Instant::now();
        let deadline_wait = state
            .recovery
            .next_deadline()
            .map(|deadline| deadline.saturating_duration_since(now))
            .unwrap_or(poll_tick);
        let wait = next_poll
            .saturating_duration_since(now)
            .min(deadline_wait)
            .min(poll_tick);
        match commands.recv_timeout(wait) {
            Ok(PlaybackCommand::Shutdown) => break 'playback,
            Ok(command) => {
                if !state.handle_command(command) {
                    break 'playback;
                }
                while let Ok(command) = commands.try_recv() {
                    if !state.handle_command(command) {
                        break 'playback;
                    }
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break 'playback,
        }

        let now = Instant::now();
        if state.want_active && state.stream.is_none() && state.recovery.due_for_retry(now) {
            state.open_stream(now);
        }

        let mut drained = 0;
        while drained < INCOMING_CAPACITY {
            match incoming.try_recv() {
                Ok(PlaybackCommand::Incoming(frame)) => {
                    state.pipeline.push_incoming(frame, now);
                    drained += 1;
                }
                Ok(PlaybackCommand::Shutdown) => break 'playback,
                Ok(_) => {}
                Err(_) => break,
            }
        }

        let now = Instant::now();
        if now >= next_poll {
            next_poll += poll_tick;
            if next_poll <= now {
                next_poll = now + poll_tick;
            }
            state.poll_playback(now);
        }
    }

    drop(state.stream.take());
    (state.sink)(AudioEvent::PlaybackState { ready: false });
}

enum ActiveErrorAction {
    Keep,
    Rebuild,
    FailPermanent(String),
}

fn classify_active_stream_error(stage: AudioStage, error: StreamError) -> ActiveErrorAction {
    match error.kind {
        StreamErrorKind::DeviceChanged => {
            match stage {
                AudioStage::Capture => {
                    crate::log_info!("capture stream automatically rerouted by host");
                }
                AudioStage::Playback => {
                    crate::log_info!("playback stream automatically rerouted by host");
                }
                AudioStage::Codec => {}
            }
            ActiveErrorAction::Keep
        }
        StreamErrorKind::NonFatal => ActiveErrorAction::Keep,
        StreamErrorKind::PermissionDenied => ActiveErrorAction::FailPermanent(error.message),
        StreamErrorKind::Disconnected | StreamErrorKind::Other => {
            match stage {
                AudioStage::Capture => {
                    crate::log_warn!("capture stream disconnected, scheduling rebuild");
                }
                AudioStage::Playback => {
                    crate::log_warn!("playback stream disconnected, scheduling rebuild");
                }
                AudioStage::Codec => {}
            }
            ActiveErrorAction::Rebuild
        }
    }
}

fn attempt_open_stream<S, F>(
    device: &mut Option<String>,
    stage: AudioStage,
    recovery: &mut RecoveryState,
    sink: &EventSink,
    now: Instant,
    open: F,
) -> Option<S>
where
    F: Fn(Option<&str>) -> Result<S, AudioError>,
{
    let first = open(device.as_deref());
    let result = match first {
        Err(AudioError::DeviceNotFound(_)) if device.is_some() => {
            *device = None;
            sink(AudioEvent::DeviceFallback { stage });
            open(None)
        }
        other => other,
    };
    match result {
        Ok(stream) => {
            recovery.on_open_succeeded();
            Some(stream)
        }
        Err(err) => {
            let retryable = !matches!(err, AudioError::PermissionDenied(_));
            if matches!(
                recovery.on_open_failed(now, retryable),
                RecoveryFailure::Exhausted
            ) {
                sink(AudioEvent::Error {
                    stage,
                    message: err.to_string(),
                });
            }
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn level_reporting_does_not_wait_for_the_control_event_consumer() {
        let (control, pending) = sync_channel(1);
        control
            .try_send(AudioEvent::SelfSpeaking { speaking: false })
            .unwrap();
        let (levels, readings) = std::sync::mpsc::channel();
        let engine = VoiceEngine::spawn(
            move |event| {
                let _ = control.try_send(event);
            },
            move |reading| {
                let _ = levels.send((reading.mic, reading.received));
            },
        )
        .unwrap();
        engine.set_meter_epoch(Some(1));

        // 控制事件始终未被消费；未启动任何输入或输出设备。
        assert_eq!(
            readings.recv_timeout(Duration::from_secs(2)),
            Ok((0.0, 0.0))
        );
        assert!(matches!(
            pending.try_recv(),
            Ok(AudioEvent::SelfSpeaking { speaking: false })
        ));
    }

    #[test]
    fn active_stream_error_classification_keeps_reroute_and_xruns() {
        assert!(matches!(
            classify_active_stream_error(
                AudioStage::Playback,
                StreamError {
                    kind: StreamErrorKind::DeviceChanged,
                    message: "rerouted".into(),
                }
            ),
            ActiveErrorAction::Keep
        ));
        assert!(matches!(
            classify_active_stream_error(
                AudioStage::Capture,
                StreamError {
                    kind: StreamErrorKind::NonFatal,
                    message: "xrun".into(),
                }
            ),
            ActiveErrorAction::Keep
        ));
        assert!(matches!(
            classify_active_stream_error(
                AudioStage::Playback,
                StreamError {
                    kind: StreamErrorKind::Disconnected,
                    message: "disconnected".into(),
                }
            ),
            ActiveErrorAction::Rebuild
        ));
        assert!(matches!(
            classify_active_stream_error(
                AudioStage::Capture,
                StreamError {
                    kind: StreamErrorKind::PermissionDenied,
                    message: "denied".into(),
                }
            ),
            ActiveErrorAction::FailPermanent(_)
        ));
    }

    #[test]
    fn open_stream_falls_back_from_missing_device_and_retries_before_emitting_error() {
        let events = Arc::new(std::sync::Mutex::new(Vec::<AudioEvent>::new()));
        let sink: EventSink = {
            let events = Arc::clone(&events);
            Arc::new(move |event| events.lock().unwrap().push(event))
        };

        let mut device = Some("aaudio:99".to_string());
        let mut recovery = RecoveryState::default();
        let t0 = Instant::now();
        let opened = attempt_open_stream(
            &mut device,
            AudioStage::Playback,
            &mut recovery,
            &sink,
            t0,
            |dev| match dev {
                Some(id) => Err(AudioError::DeviceNotFound(id.to_string())),
                None => Ok(42),
            },
        );
        assert_eq!(opened, Some(42));
        assert_eq!(device, None);
        assert_eq!(recovery, RecoveryState::Active);
        {
            let recorded = events.lock().unwrap();
            assert_eq!(recorded.len(), 1);
            assert!(matches!(
                recorded[0],
                AudioEvent::DeviceFallback {
                    stage: AudioStage::Playback
                }
            ));
        }

        // 瞬态失败在重试耗尽前不发 Error，耗尽后仅发一次。
        events.lock().unwrap().clear();
        recovery.reset();
        for attempt in 0..=crate::recovery::RECOVERY_BACKOFF.len() {
            let result: Option<i32> = attempt_open_stream(
                &mut device,
                AudioStage::Playback,
                &mut recovery,
                &sink,
                t0,
                |_| Err(AudioError::Device("busy".into())),
            );
            assert_eq!(result, None);
            let error_count = events
                .lock()
                .unwrap()
                .iter()
                .filter(|ev| matches!(ev, AudioEvent::Error { .. }))
                .count();
            if attempt < crate::recovery::RECOVERY_BACKOFF.len() {
                assert_eq!(error_count, 0);
            } else {
                assert_eq!(error_count, 1);
            }
        }

        // 权限拒绝立即失败，不排入重试。
        events.lock().unwrap().clear();
        recovery.reset();
        let result: Option<i32> = attempt_open_stream(
            &mut device,
            AudioStage::Capture,
            &mut recovery,
            &sink,
            t0,
            |_| Err(AudioError::PermissionDenied("denied".into())),
        );
        assert_eq!(result, None);
        assert_eq!(recovery, RecoveryState::Failed);
        assert_eq!(events.lock().unwrap().len(), 1);
        assert!(matches!(
            events.lock().unwrap()[0],
            AudioEvent::Error {
                stage: AudioStage::Capture,
                ..
            }
        ));
    }

    fn capture_state_with_pipeline(pipeline: CapturePipeline) -> CaptureLoopState {
        CaptureLoopState {
            pipeline,
            stream: None,
            raw: Vec::new(),
            device: None,
            want_active: false,
            recovery: RecoveryState::default(),
            speaking: false,
            capture_epoch: 1,
            pacer: VoicePacer::default(),
            mic_meter: TransmitMeter::default(),
            sink: Arc::new(|_| {}),
            meter: Arc::new(SharedMeter::default()),
        }
    }

    #[test]
    fn transmit_level_follows_outbound_packets_and_ignores_input_without_packets() {
        let mut state =
            capture_state_with_pipeline(CapturePipeline::new(crate::format::VOICE_CODEC).unwrap());
        state.pipeline.begin();
        state.pipeline.set_ptt_mode(true);
        state.pipeline.set_ptt_active(true);

        let samples: Vec<f32> = (0..crate::format::FRAME_SAMPLES_PER_CHANNEL)
            .map(|index| (index as f32 * 0.05).sin() * 0.5)
            .collect();
        state
            .pipeline
            .push_capture(&samples, crate::format::OPUS_MONO);
        let packet = state
            .pipeline
            .take_packet()
            .unwrap()
            .expect("PTT should encode a packet");
        assert!(!packet.data.is_empty());
        assert_eq!(state.mic_meter.level(), 0.0);

        state.meter_outbound(false, Instant::now());
        assert!(state.mic_meter.level() > 0.0);

        // 松开 PTT 后仍持续采到同样的原始输入；没有包就没有电平。
        state.pipeline.set_ptt_active(false);
        while let Some(packet) = state.pipeline.take_packet().unwrap() {
            state.meter_outbound(packet.data.is_empty(), Instant::now());
        }
        assert_eq!(state.mic_meter.level(), 0.0);

        state
            .pipeline
            .push_capture(&samples, crate::format::OPUS_MONO);
        assert!(state.pipeline.take_packet().unwrap().is_none());
        assert_eq!(state.mic_meter.tick(Instant::now()), 0.0);
    }

    #[test]
    fn playback_loop_watermark_caps_queue_depth_and_burst_ticks() {
        let format = OPUS_STEREO;
        let (stream, queue) = PlaybackStream::new_for_test(format);
        let target = playback_watermark_samples(format);
        assert_eq!(target, 2_400);

        let mut state = PlaybackLoopState {
            pipeline: PlaybackPipeline::new(),
            stream: Some(stream),
            converter: Some(FormatConverter::new(OPUS_STEREO, format)),
            converted: Vec::new(),
            device: None,
            want_active: true,
            recovery: RecoveryState::default(),
            sink: Arc::new(|_| {}),
            levels: Arc::new(|_| {}),
            meter: Arc::new(SharedMeter::default()),
            received_meter: LevelMeter::default(),
            received_clock: MeterClock::default(),
            last_received_level: 0.0,
            playback_epoch: 0,
            last_talkers: Vec::new(),
        };

        let mut now = Instant::now();
        // 空队列首次唤醒：低于 25ms 水位，受单次最多 2 帧上限约束，输出 20ms（1920 样本）。
        assert_eq!(state.poll_playback(now), 2);
        assert_eq!(queue.len(), 1_920);

        // 第二次唤醒再补 1 帧达到 30ms（2880 >= 2400），不再继续堆积。
        now += Duration::from_millis(PLAYBACK_POLL_MS);
        assert_eq!(state.poll_playback(now), 1);
        assert_eq!(queue.len(), 2_880);

        // 未被声卡消费时连续多次 5ms 轮询均跳过解码，零延迟堆积。
        for _ in 0..10 {
            now += Duration::from_millis(PLAYBACK_POLL_MS);
            assert_eq!(state.poll_playback(now), 0);
            assert_eq!(queue.len(), 2_880);
        }

        // 模拟声卡消费 10ms（960 样本）跌破水位（1920 < 2400），立刻补回 1 帧。
        for _ in 0..960 {
            assert!(queue.pop().is_some());
        }
        now += Duration::from_millis(PLAYBACK_POLL_MS);
        assert_eq!(state.poll_playback(now), 1);
        assert_eq!(queue.len(), 2_880);
    }
}
