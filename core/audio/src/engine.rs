//! 音频引擎：采集线程 + 播放线程。
//!
//! cpal 回调只搬运 `ArrayQueue` 里的样本；编码/解码/混音都在各自的工作线程。
//! 两条线程之间没有共享锁，控制命令走独立的有界通道，语音包走另一条有界通道。

use std::sync::Arc;
use std::sync::mpsc::{Receiver, RecvTimeoutError, SyncSender, TrySendError, sync_channel};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::AudioError;
use crate::capture::{CapturePipeline, VoicePacer};
use crate::convert::FormatConverter;
use crate::device::{CaptureStream, PlaybackStream, start_capture, start_playback};
use crate::format::OPUS_STEREO;
use crate::level::{LevelMeter, LevelReading, MeterClock, SharedMeter, rms};
use crate::playback::{MIX_FRAME_MS, PlaybackPipeline, VoiceFrame};
use crate::recovery::{RecoveryFailure, RecoveryState, StreamError, StreamErrorKind};

const CONTROL_CAPACITY: usize = 64;
const INCOMING_CAPACITY: usize = 256;
const IO_TICK_MS: u64 = 10;
const CAPTURE_POLL_MS: u64 = 5;
const CATCHUP_PACING_MS: u64 = 2;

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
    Start { device: Option<String>, epoch: u64 },
    Stop,
    SetDevice { device: Option<String> },
    SetMuted(bool),
    SetDeafened(bool),
    SetPttMode(bool),
    SetPttActive(bool),
    SetCodec(i32),
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
        TrySendError::Full(_) => AudioError::Engine("音频命令队列已满".into()),
        TrySendError::Disconnected(_) => AudioError::Engine("音频线程已退出".into()),
    }
}

struct CaptureLoopState {
    pipeline: CapturePipeline,
    stream: Option<CaptureStream>,
    device: Option<String>,
    want_active: bool,
    recovery: RecoveryState,
    speaking: bool,
    capture_epoch: u64,
    pacer: VoicePacer,
    mic_meter: LevelMeter,
    sink: EventSink,
    meter: Arc<SharedMeter>,
}

impl CaptureLoopState {
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
                self.speaking = false;
                self.pacer.reset();
                (self.sink)(AudioEvent::CaptureState { ready: false });
            }
            CaptureCommand::SetDevice { device } => {
                self.mic_meter.silence();
                self.meter.clear_mic();
                self.device = device;
                if self.want_active {
                    self.recovery.reset();
                    self.open_stream(now);
                    self.speaking = false;
                    self.pacer.reset();
                }
            }
            CaptureCommand::SetMuted(next) => {
                self.pipeline.set_muted(next);
                if next {
                    self.pacer.reset();
                }
            }
            CaptureCommand::SetDeafened(deafened) => {
                self.pipeline.set_deafened(deafened);
                if deafened {
                    self.pacer.reset();
                }
            }
            CaptureCommand::SetPttMode(next) => {
                self.pipeline.set_ptt_mode(next);
                self.pacer.reset();
                (self.sink)(AudioEvent::CaptureState {
                    ready: self.stream.is_some(),
                });
            }
            CaptureCommand::SetPttActive(next) => {
                self.pipeline.set_ptt_active(next);
                if !next {
                    self.pacer.reset();
                }
                (self.sink)(AudioEvent::CaptureState {
                    ready: self.stream.is_some(),
                });
            }
            CaptureCommand::SetCodec(codec) => match self.pipeline.set_codec(codec) {
                Ok(()) => {
                    self.pacer.reset();
                }
                Err(err) => (self.sink)(AudioEvent::Error {
                    stage: AudioStage::Codec,
                    message: err.to_string(),
                }),
            },
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
                self.speaking = false;
                self.pacer.reset();
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
                self.speaking = false;
                self.pacer.reset();
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
        device: None,
        want_active: false,
        recovery: RecoveryState::default(),
        speaking: false,
        capture_epoch: 0,
        pacer: VoicePacer::default(),
        mic_meter: LevelMeter::default(),
        sink,
        meter,
    };
    let mut raw = Vec::new();
    let idle_tick = Duration::from_millis(IO_TICK_MS);
    let poll_tick = Duration::from_millis(CAPTURE_POLL_MS);
    let catchup_spacing = Duration::from_millis(CATCHUP_PACING_MS);

    'capture: loop {
        let now = Instant::now();
        let wait = if let Some(deadline) = state.recovery.next_deadline() {
            deadline.saturating_duration_since(now).min(idle_tick)
        } else if state.stream.is_none() {
            idle_tick
        } else if state.pipeline.has_ready_frame() && state.pipeline.is_transmitting() {
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

        if let Some(stream) = &state.stream {
            raw.clear();
            let max_drain = (stream.format.sample_rate_hz as usize)
                .saturating_mul(stream.format.channels as usize)
                / 2;
            stream.drain_into(&mut raw, max_drain.max(48_000 * 2 / 5));
            if !raw.is_empty() {
                state.pipeline.push_capture(&raw, stream.format);
            }
            if let Some(error) = stream.take_error() {
                state.handle_stream_error(error, now);
            }
        }

        let mic = if state.stream.is_some() && state.pipeline.is_capturing() {
            if raw.is_empty() {
                state.mic_meter.level()
            } else {
                state.mic_meter.update(rms(&raw))
            }
        } else {
            state.mic_meter.silence()
        };
        // 只是共享给 playback 线程合成事件；跨 FFI 的频率由那边控制。
        state.meter.store_mic(state.capture_epoch, mic);

        let now = Instant::now();
        while state.pipeline.has_ready_frame() {
            if state.pipeline.is_transmitting() && !state.pacer.is_due(now) {
                break;
            }
            match state.pipeline.take_packet() {
                Ok(Some(packet)) => {
                    let _ = state.pacer.is_due(now);
                    (state.sink)(AudioEvent::Outbound {
                        codec: packet.codec,
                        data: packet.data,
                        produced_at: now,
                    });
                    state.pacer.advance();
                    break;
                }
                Ok(None) => {
                    state.pacer.reset();
                }
                Err(err) => {
                    (state.sink)(AudioEvent::Error {
                        stage: AudioStage::Codec,
                        message: err.to_string(),
                    });
                    break;
                }
            }
        }
        if !state.pipeline.is_capturing() {
            state.pacer.reset();
        }

        let now_speaking = state.pipeline.is_speaking();
        if now_speaking != state.speaking {
            state.speaking = now_speaking;
            (state.sink)(AudioEvent::SelfSpeaking {
                speaking: now_speaking,
            });
        }
    }

    drop(state.stream.take());
    state.meter.clear_mic();
    (state.sink)(AudioEvent::CaptureState { ready: false });
}

struct PlaybackLoopState {
    pipeline: PlaybackPipeline,
    stream: Option<PlaybackStream>,
    converter: Option<FormatConverter>,
    device: Option<String>,
    want_active: bool,
    recovery: RecoveryState,
    sink: EventSink,
    levels: LevelSink,
    meter: Arc<SharedMeter>,
    received_meter: LevelMeter,
    received_clock: MeterClock,
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
                self.received_meter.silence();
                self.received_clock = MeterClock::default();
                self.pipeline.restart();
                self.want_active = true;
                self.device = device;
                self.recovery.reset();
                self.open_stream(now);
            }
            PlaybackCommand::Stop => {
                self.playback_epoch = 0;
                self.received_meter.silence();
                self.want_active = false;
                self.recovery.reset();
                drop(self.stream.take());
                self.converter = None;
                self.pipeline = PlaybackPipeline::new();
                (self.sink)(AudioEvent::PlaybackState { ready: false });
            }
            PlaybackCommand::SetDevice { device } => {
                self.received_meter.silence();
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

    fn handle_stream_error(&mut self, error: StreamError, now: Instant) {
        let action = classify_active_stream_error(AudioStage::Playback, error);
        match action {
            ActiveErrorAction::Keep => {}
            ActiveErrorAction::FailPermanent(message) => {
                drop(self.stream.take());
                self.converter = None;
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
        device: None,
        want_active: false,
        recovery: RecoveryState::default(),
        sink,
        levels,
        meter,
        received_meter: LevelMeter::default(),
        received_clock: MeterClock::default(),
        playback_epoch: 0,
        last_talkers: Vec::new(),
    };
    let mut next_tick = Instant::now();

    loop {
        let now = Instant::now();
        let deadline_wait = state
            .recovery
            .next_deadline()
            .map(|deadline| deadline.saturating_duration_since(now))
            .unwrap_or(Duration::from_millis(IO_TICK_MS));
        let wait = next_tick
            .saturating_duration_since(now)
            .min(deadline_wait)
            .min(Duration::from_millis(IO_TICK_MS));
        match commands.recv_timeout(wait) {
            Ok(PlaybackCommand::Shutdown) => break,
            Ok(command) => {
                if !state.handle_command(command) {
                    break;
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break,
        }

        let now = Instant::now();
        if state.want_active && state.stream.is_none() && state.recovery.due_for_retry(now) {
            state.open_stream(now);
        }

        // 收包通道与混音节拍解耦：每个 tick 前把已到达的包全部喂给 jitter buffer。
        let now = Instant::now();
        if now >= next_tick {
            let mut drained = 0;
            while drained < 128 {
                match incoming.try_recv() {
                    Ok(PlaybackCommand::Incoming(frame)) => {
                        state.pipeline.push_incoming(frame, now);
                        drained += 1;
                    }
                    Ok(PlaybackCommand::Shutdown) => return,
                    Ok(_) => {}
                    Err(_) => break,
                }
            }

            next_tick += Duration::from_millis(MIX_FRAME_MS);
            if next_tick <= now {
                next_tick = now + Duration::from_millis(MIX_FRAME_MS);
            }

            let tick = state
                .pipeline
                .tick(now, crate::playback::MIX_SAMPLES_PER_CHANNEL);
            let received_level = if state.stream.is_some() && !tick.talkers.is_empty() {
                state.received_meter.update(rms(&tick.samples))
            } else {
                state.received_meter.silence()
            };
            if state.received_clock.due(now) {
                let epoch = state.meter.epoch();
                let received = if epoch == state.playback_epoch {
                    received_level
                } else {
                    0.0
                };
                if let Some(reading) = state.meter.reading(epoch, received) {
                    (state.levels)(reading);
                }
            }
            if tick.talkers != state.last_talkers {
                state.last_talkers = tick.talkers.clone();
                (state.sink)(AudioEvent::Talkers {
                    client_ids: state.last_talkers.clone(),
                });
            }
            if let (Some(stream), Some(converter)) = (&state.stream, &mut state.converter) {
                let mut converted = Vec::new();
                converter.process(&tick.samples, &mut converted);
                stream.push(&converted);
                if let Some(error) = stream.take_error() {
                    state.handle_stream_error(error, now);
                }
            }
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
}
