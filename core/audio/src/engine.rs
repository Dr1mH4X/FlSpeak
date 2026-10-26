//! 音频引擎：采集线程 + 播放线程。
//!
//! cpal 回调只搬运 `ArrayQueue` 里的样本；编码/解码/混音都在各自的工作线程。
//! 两条线程之间没有共享锁，控制命令走独立的有界通道，语音包走另一条有界通道。

use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::mpsc::{Receiver, RecvTimeoutError, SyncSender, TrySendError, sync_channel};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::AudioError;
use crate::capture::{CapturePipeline, VoicePacer};
use crate::convert::FormatConverter;
use crate::device::{CaptureStream, PlaybackStream, start_capture, start_playback};
use crate::format::{FRAME_MS, OPUS_STEREO};
use crate::level::{LevelMeter, MeterClock, rms};
use crate::playback::{MIX_FRAME_MS, PlaybackPipeline, VoiceFrame};

const CONTROL_CAPACITY: usize = 64;
const INCOMING_CAPACITY: usize = 256;
const IO_TICK_MS: u64 = 10;

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
    },
    /// 本端 VAD/PTT 是否在发送，低频。
    SelfSpeaking {
        speaking: bool,
    },
    /// 本端采集与远端混音电平（0–1），≤10Hz。
    Levels {
        mic: f32,
        received: f32,
    },
    /// 远端活跃说话人集合变化。
    Talkers {
        client_ids: Vec<i32>,
    },
    CaptureState {
        ready: bool,
        ptt_mode: bool,
        ptt_active: bool,
    },
    PlaybackState {
        ready: bool,
    },
    Error {
        stage: AudioStage,
        message: String,
    },
}

enum CaptureCommand {
    Start { device: Option<String> },
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
    Start { device: Option<String> },
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

/// 音频引擎句柄。Drop 时关闭两条线程并等待 cpal 流释放。
pub struct VoiceEngine {
    capture: SyncSender<CaptureCommand>,
    playback: SyncSender<PlaybackCommand>,
    incoming: IncomingVoiceSender,
    capture_thread: Option<JoinHandle<()>>,
    playback_thread: Option<JoinHandle<()>>,
}

impl VoiceEngine {
    pub fn spawn(sink: impl Fn(AudioEvent) + Send + Sync + 'static) -> Result<Self, AudioError> {
        let sink: EventSink = Arc::new(sink);
        let (capture, capture_rx) = sync_channel(CONTROL_CAPACITY);
        let (playback, playback_rx) = sync_channel(CONTROL_CAPACITY);
        let (incoming, incoming_rx) = sync_channel(INCOMING_CAPACITY);
        // capture 线程写入、playback 线程按 10Hz 读出并合成一个事件。
        let mic_level = Arc::new(AtomicU32::new(0));

        let capture_thread = thread::Builder::new()
            .name("voice-capture".into())
            .spawn({
                let sink = Arc::clone(&sink);
                let mic_level = Arc::clone(&mic_level);
                move || capture_loop(capture_rx, sink, mic_level)
            })
            .map_err(|err| AudioError::Engine(err.to_string()))?;
        let playback_thread = thread::Builder::new()
            .name("voice-playback".into())
            .spawn({
                let sink = Arc::clone(&sink);
                move || playback_loop(playback_rx, incoming_rx, sink, mic_level)
            })
            .map_err(|err| AudioError::Engine(err.to_string()))?;

        Ok(Self {
            capture,
            playback,
            incoming: IncomingVoiceSender { sender: incoming },
            capture_thread: Some(capture_thread),
            playback_thread: Some(playback_thread),
        })
    }

    pub fn incoming_sender(&self) -> IncomingVoiceSender {
        self.incoming.clone()
    }

    pub fn start_playback(&self, device: Option<String>) -> Result<(), AudioError> {
        self.playback
            .try_send(PlaybackCommand::Start { device })
            .map_err(send_error)
    }

    pub fn stop_playback(&self) -> Result<(), AudioError> {
        self.playback
            .try_send(PlaybackCommand::Stop)
            .map_err(send_error)
    }

    pub fn start_capture(&self, device: Option<String>) -> Result<(), AudioError> {
        self.capture
            .try_send(CaptureCommand::Start { device })
            .map_err(send_error)
    }

    pub fn stop_capture(&self) -> Result<(), AudioError> {
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

fn store_level(slot: &AtomicU32, level: f32) {
    let scaled = (level.clamp(0.0, 1.0) * 1000.0) as u32;
    slot.store(scaled, Ordering::Relaxed);
}

fn load_level(slot: &AtomicU32) -> f32 {
    slot.load(Ordering::Relaxed) as f32 / 1000.0
}

fn capture_loop(commands: Receiver<CaptureCommand>, sink: EventSink, mic_level: Arc<AtomicU32>) {
    let mut pipeline = match CapturePipeline::new(crate::format::VOICE_CODEC) {
        Ok(pipeline) => pipeline,
        Err(err) => {
            sink(AudioEvent::Error {
                stage: AudioStage::Codec,
                message: err.to_string(),
            });
            return;
        }
    };
    let mut stream: Option<CaptureStream> = None;
    let mut device: Option<String> = None;
    let mut muted = false;
    let mut ptt_mode = false;
    let mut ptt_active = false;
    let mut speaking = false;
    let mut pacer = VoicePacer::default();
    let mut raw = Vec::new();
    let mut mic_meter = LevelMeter::default();
    let mut next_frame = Instant::now();
    let tick = Duration::from_millis(IO_TICK_MS);

    loop {
        let now = Instant::now();
        let wait = next_frame.saturating_duration_since(now);
        match commands.recv_timeout(wait.min(tick)) {
            Ok(CaptureCommand::Shutdown) => break,
            Ok(command) => {
                if !handle_capture_command(
                    command,
                    &mut pipeline,
                    &mut stream,
                    &mut device,
                    &mut muted,
                    &mut ptt_mode,
                    &mut ptt_active,
                    &mut speaking,
                    &sink,
                    &mut pacer,
                ) {
                    break;
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break,
        }

        let now = Instant::now();
        if now < next_frame {
            continue;
        }
        next_frame += Duration::from_millis(FRAME_MS);
        if next_frame <= now {
            next_frame = now + Duration::from_millis(FRAME_MS);
        }

        if let Some(stream) = &stream {
            raw.clear();
            stream.drain_into(&mut raw, 48_000 * 2 / 5);
            if !raw.is_empty() {
                pipeline.push_capture(&raw, stream.format);
            }
            if let Some(message) = stream.take_error() {
                sink(AudioEvent::Error {
                    stage: AudioStage::Capture,
                    message,
                });
            }
        }

        let mic = if stream.is_some() && pipeline.is_capturing() {
            mic_meter.update(rms(&raw))
        } else {
            mic_meter.silence()
        };
        // 只是共享给 playback 线程合成事件；跨 FFI 的频率由那边控制。
        store_level(&mic_level, mic);

        match pipeline.take_packet() {
            Ok(Some(packet)) => {
                if pacer.due(now, true) {
                    sink(AudioEvent::Outbound {
                        codec: packet.codec,
                        data: packet.data,
                    });
                    pacer.advance();
                }
            }
            Ok(None) => {
                pacer.due(now, false);
            }
            Err(err) => sink(AudioEvent::Error {
                stage: AudioStage::Codec,
                message: err.to_string(),
            }),
        }

        let now_speaking = pipeline.is_speaking();
        if now_speaking != speaking {
            speaking = now_speaking;
            sink(AudioEvent::SelfSpeaking {
                speaking: now_speaking,
            });
        }
    }

    if let Some(stream) = stream.take() {
        drop(stream);
    }
    sink(AudioEvent::CaptureState {
        ready: false,
        ptt_mode,
        ptt_active: false,
    });
    let _ = muted;
}

#[allow(clippy::too_many_arguments)]
fn handle_capture_command(
    command: CaptureCommand,
    pipeline: &mut CapturePipeline,
    stream: &mut Option<CaptureStream>,
    device: &mut Option<String>,
    muted: &mut bool,
    ptt_mode: &mut bool,
    ptt_active: &mut bool,
    speaking: &mut bool,
    sink: &EventSink,
    pacer: &mut VoicePacer,
) -> bool {
    match command {
        CaptureCommand::Shutdown => return false,
        CaptureCommand::Start { device: next } => {
            *device = next;
            open_capture(
                stream,
                pipeline,
                (*device).clone(),
                *ptt_mode,
                *ptt_active,
                sink,
            );
            *speaking = false;
            pacer.due(Instant::now(), false);
        }
        CaptureCommand::Stop => {
            if let Some(stream) = stream.take() {
                drop(stream);
            }
            pipeline.end();
            *speaking = false;
            sink(AudioEvent::CaptureState {
                ready: false,
                ptt_mode: *ptt_mode,
                ptt_active: *ptt_active,
            });
        }
        CaptureCommand::SetDevice { device: next } => {
            let was_active = stream.is_some();
            *device = next;
            if was_active {
                open_capture(
                    stream,
                    pipeline,
                    (*device).clone(),
                    *ptt_mode,
                    *ptt_active,
                    sink,
                );
            }
        }
        CaptureCommand::SetMuted(next) => {
            *muted = next;
            pipeline.set_muted(next);
        }
        CaptureCommand::SetDeafened(deafened) => pipeline.set_deafened(deafened),
        CaptureCommand::SetPttMode(next) => {
            *ptt_mode = next;
            pipeline.set_ptt_mode(next);
            sink(AudioEvent::CaptureState {
                ready: stream.is_some(),
                ptt_mode: *ptt_mode,
                ptt_active: *ptt_active,
            });
        }
        CaptureCommand::SetPttActive(next) => {
            *ptt_active = next;
            pipeline.set_ptt_active(next);
            sink(AudioEvent::CaptureState {
                ready: stream.is_some(),
                ptt_mode: *ptt_mode,
                ptt_active: *ptt_active,
            });
        }
        CaptureCommand::SetCodec(codec) => match pipeline.set_codec(codec) {
            Ok(()) => {}
            Err(err) => sink(AudioEvent::Error {
                stage: AudioStage::Codec,
                message: err.to_string(),
            }),
        },
    }
    true
}

fn open_capture(
    stream: &mut Option<CaptureStream>,
    pipeline: &mut CapturePipeline,
    device: Option<String>,
    ptt_mode: bool,
    ptt_active: bool,
    sink: &EventSink,
) {
    if let Some(old) = stream.take() {
        drop(old);
    }
    match start_capture(device.as_deref()) {
        Ok(next) => {
            pipeline.begin();
            *stream = Some(next);
            sink(AudioEvent::CaptureState {
                ready: true,
                ptt_mode,
                ptt_active,
            });
        }
        Err(err) => {
            pipeline.end();
            sink(AudioEvent::Error {
                stage: AudioStage::Capture,
                message: err.to_string(),
            });
            sink(AudioEvent::CaptureState {
                ready: false,
                ptt_mode,
                ptt_active,
            });
        }
    }
}

fn playback_loop(
    commands: Receiver<PlaybackCommand>,
    incoming: Receiver<PlaybackCommand>,
    sink: EventSink,
    mic_level: Arc<AtomicU32>,
) {
    let mut pipeline = PlaybackPipeline::new();
    let mut stream: Option<PlaybackStream> = None;
    let mut converter: Option<FormatConverter> = None;
    let mut next_tick = Instant::now();
    let mut last_talkers: Vec<i32> = Vec::new();
    let mut received_meter = LevelMeter::default();
    let mut received_clock = MeterClock::default();

    loop {
        let now = Instant::now();
        let wait = next_tick.saturating_duration_since(now);
        match commands.recv_timeout(wait.min(Duration::from_millis(IO_TICK_MS))) {
            Ok(PlaybackCommand::Shutdown) => break,
            Ok(command) => {
                if !handle_playback_command(
                    command,
                    &mut pipeline,
                    &mut stream,
                    &mut converter,
                    &sink,
                ) {
                    break;
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break,
        }

        // 收包通道与混音节拍解耦：每个 tick 前把已到达的包全部喂给 jitter buffer。
        let now = Instant::now();
        if now >= next_tick {
            let mut drained = 0;
            while drained < 128 {
                match incoming.try_recv() {
                    Ok(PlaybackCommand::Incoming(frame)) => {
                        pipeline.push_incoming(frame, now);
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

            let tick = pipeline.tick(now, crate::playback::MIX_SAMPLES_PER_CHANNEL);
            let received_level = if stream.is_some() && !tick.talkers.is_empty() {
                received_meter.update(rms(&tick.samples))
            } else {
                received_meter.silence()
            };
            if received_clock.due(now) {
                sink(AudioEvent::Levels {
                    mic: load_level(&mic_level),
                    received: received_level,
                });
            }
            if tick.talkers != last_talkers {
                last_talkers = tick.talkers.clone();
                sink(AudioEvent::Talkers {
                    client_ids: last_talkers.clone(),
                });
            }
            if let (Some(stream), Some(converter)) = (&stream, &mut converter) {
                let mut converted = Vec::new();
                converter.process(&tick.samples, &mut converted);
                stream.push(&converted);
                if let Some(message) = stream.take_error() {
                    sink(AudioEvent::Error {
                        stage: AudioStage::Playback,
                        message,
                    });
                }
            }
        }
    }

    if let Some(stream) = stream.take() {
        drop(stream);
    }
    sink(AudioEvent::PlaybackState { ready: false });
}

fn handle_playback_command(
    command: PlaybackCommand,
    pipeline: &mut PlaybackPipeline,
    stream: &mut Option<PlaybackStream>,
    converter: &mut Option<FormatConverter>,
    sink: &EventSink,
) -> bool {
    match command {
        PlaybackCommand::Shutdown => return false,
        PlaybackCommand::Start { device } => {
            *pipeline = PlaybackPipeline::new();
            if let Some(old) = stream.take() {
                drop(old);
            }
            match start_playback(device.as_deref()) {
                Ok(next) => {
                    *converter = Some(FormatConverter::new(OPUS_STEREO, next.format));
                    *stream = Some(next);
                    sink(AudioEvent::PlaybackState { ready: true });
                }
                Err(err) => {
                    *converter = None;
                    sink(AudioEvent::Error {
                        stage: AudioStage::Playback,
                        message: err.to_string(),
                    });
                    sink(AudioEvent::PlaybackState { ready: false });
                }
            }
        }
        PlaybackCommand::Stop => {
            if let Some(stream) = stream.take() {
                drop(stream);
            }
            *converter = None;
            *pipeline = PlaybackPipeline::new();
            sink(AudioEvent::PlaybackState { ready: false });
        }
        PlaybackCommand::SetDevice { device } => {
            let was_active = stream.is_some();
            if was_active {
                if let Some(old) = stream.take() {
                    drop(old);
                }
                match start_playback(device.as_deref()) {
                    Ok(next) => {
                        *converter = Some(FormatConverter::new(OPUS_STEREO, next.format));
                        *stream = Some(next);
                        sink(AudioEvent::PlaybackState { ready: true });
                    }
                    Err(err) => {
                        *converter = None;
                        sink(AudioEvent::Error {
                            stage: AudioStage::Playback,
                            message: err.to_string(),
                        });
                        sink(AudioEvent::PlaybackState { ready: false });
                    }
                }
            }
        }
        PlaybackCommand::SetDeafened(deafened) => pipeline.set_deafened(deafened),
        PlaybackCommand::Incoming(frame) => {
            pipeline.push_incoming(frame, Instant::now());
        }
    }
    true
}
