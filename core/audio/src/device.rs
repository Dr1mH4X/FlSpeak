//! cpal 设备后端：实时回调零分配零锁，队列满或空时丢样本而不阻塞音频线程。

use std::sync::Arc;
use std::sync::Mutex;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{DeviceType, FromSample, InterfaceType, Sample, SampleFormat, SizedSample};
use crossbeam_queue::ArrayQueue;

use crate::AudioError;
use crate::format::AudioFormat;
#[cfg(target_os = "android")]
use crate::recovery::{
    AndroidDeviceCandidate, DeviceInterfaceKind, DeviceKind, select_android_device_indices,
};
use crate::recovery::{
    DeviceCandidate, StreamError, StreamErrorKind, is_virtual_default_device_id,
    pick_fallback_default_index,
};

/// 采集环形队列容量：2 秒 48kHz 立体声 f32。
const CAPTURE_QUEUE_CAPACITY: usize = 48_000 * 2 * 2;
/// 播放环形队列容量时长：按输出设备实际采样率与声道数动态分配 120ms。
pub const PLAYBACK_QUEUE_MS: u64 = 120;
const MAX_TRACKED_CHANNELS: usize = 8;
const UNDERRUN_DECAY: f32 = 0.94;
const UNDERRUN_ZERO_THRESHOLD: f32 = 1e-5;

pub fn playback_queue_capacity(format: AudioFormat) -> usize {
    let frames = ((format.sample_rate_hz as u64 * PLAYBACK_QUEUE_MS) / 1000).max(1) as usize;
    frames * (format.channels as usize).max(1)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceInfo {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

#[derive(Clone, Default)]
struct ErrorSlot(Arc<Mutex<Option<StreamError>>>);

impl ErrorSlot {
    fn set(&self, err: StreamError) {
        if err.kind == StreamErrorKind::NonFatal {
            return;
        }
        if let Ok(mut slot) = self.0.lock() {
            let keep_existing = matches!(
                slot.as_ref().map(|existing| existing.kind),
                Some(StreamErrorKind::Disconnected | StreamErrorKind::PermissionDenied)
            ) && matches!(
                err.kind,
                StreamErrorKind::DeviceChanged | StreamErrorKind::Other
            );
            if !keep_existing {
                *slot = Some(err);
            }
        }
    }

    fn take(&self) -> Option<StreamError> {
        self.0.lock().ok().and_then(|mut slot| slot.take())
    }
}

pub fn input_devices() -> Result<Vec<DeviceInfo>, AudioError> {
    list_devices(true)
}

pub fn output_devices() -> Result<Vec<DeviceInfo>, AudioError> {
    list_devices(false)
}

/// 采集流。持有 cpal stream 保证它不被销毁；工作线程用 `drain_into` 取样本。
pub struct CaptureStream {
    pub format: AudioFormat,
    samples: Arc<ArrayQueue<f32>>,
    errors: ErrorSlot,
    _stream: Option<cpal::Stream>,
}

impl CaptureStream {
    #[cfg(test)]
    pub(crate) fn new_for_test(format: AudioFormat) -> (Self, Arc<ArrayQueue<f32>>) {
        let samples = Arc::new(ArrayQueue::new(CAPTURE_QUEUE_CAPACITY));
        let stream = Self {
            format,
            samples: Arc::clone(&samples),
            errors: ErrorSlot::default(),
            _stream: None,
        };
        (stream, samples)
    }

    /// 把环形队列里已有的样本按完整源帧取到 `output`，最多 `max` 个。
    pub fn drain_into(&self, output: &mut Vec<f32>, max: usize) {
        output.clear();
        let channels = (self.format.channels as usize).max(1);
        let frames = (self.samples.len() / channels).min(max / channels);
        let count = frames * channels;
        output.reserve(count);
        for _ in 0..count {
            let Some(sample) = self.samples.pop() else {
                break;
            };
            output.push(sample);
        }
    }

    pub fn buffered_samples(&self) -> usize {
        self.samples.len()
    }

    pub fn take_error(&self) -> Option<StreamError> {
        self.errors.take()
    }
}

/// 播放流。工作线程把设备格式的交织 f32 样本推进环；回调只负责取用。
pub struct PlaybackStream {
    pub format: AudioFormat,
    samples: Arc<ArrayQueue<f32>>,
    errors: ErrorSlot,
    _stream: Option<cpal::Stream>,
}

impl PlaybackStream {
    #[cfg(test)]
    pub(crate) fn new_for_test(format: AudioFormat) -> (Self, Arc<ArrayQueue<f32>>) {
        let samples = Arc::new(ArrayQueue::new(playback_queue_capacity(format)));
        let stream = Self {
            format,
            samples: Arc::clone(&samples),
            errors: ErrorSlot::default(),
            _stream: None,
        };
        (stream, samples)
    }

    pub fn push(&self, samples: &[f32]) {
        let channels = (self.format.channels as usize).max(1);
        for frame in samples.chunks_exact(channels) {
            // 仅在剩余空间容纳完整一帧时写入，避免单样本截断导致声道错位。
            if self.samples.len() + channels > self.samples.capacity() {
                break;
            }
            for &sample in frame {
                let _ = self.samples.push(sample);
            }
        }
    }

    pub fn buffered_samples(&self) -> usize {
        self.samples.len()
    }

    pub fn take_error(&self) -> Option<StreamError> {
        self.errors.take()
    }
}

pub fn start_capture(device_id: Option<&str>) -> Result<CaptureStream, AudioError> {
    let device = select_device(true, device_id)?;
    let supported = device.default_input_config().map_err(device_error)?;
    let format = AudioFormat {
        sample_rate_hz: supported.sample_rate(),
        channels: supported.channels(),
    };
    let errors = ErrorSlot::default();
    let samples = Arc::new(ArrayQueue::new(CAPTURE_QUEUE_CAPACITY));
    let stream = build_input_stream(
        &device,
        &supported.config(),
        supported.sample_format(),
        Arc::clone(&samples),
        errors.clone(),
    )?;
    stream.play().map_err(device_error)?;
    Ok(CaptureStream {
        format,
        samples,
        errors,
        _stream: Some(stream),
    })
}

pub fn start_playback(device_id: Option<&str>) -> Result<PlaybackStream, AudioError> {
    let device = select_device(false, device_id)?;
    let supported = device.default_output_config().map_err(device_error)?;
    let format = AudioFormat {
        sample_rate_hz: supported.sample_rate(),
        channels: supported.channels(),
    };
    let errors = ErrorSlot::default();
    let samples = Arc::new(ArrayQueue::new(playback_queue_capacity(format)));
    let stream = build_output_stream(
        &device,
        &supported.config(),
        supported.sample_format(),
        Arc::clone(&samples),
        errors.clone(),
    )?;
    stream.play().map_err(device_error)?;
    Ok(PlaybackStream {
        format,
        samples,
        errors,
        _stream: Some(stream),
    })
}

fn list_devices(input: bool) -> Result<Vec<DeviceInfo>, AudioError> {
    let host = cpal::default_host();
    let default_id = if input {
        host.default_input_device()
    } else {
        host.default_output_device()
    }
    .and_then(|device| device.id().ok())
    .map(|id| id.to_string());

    let devices: Vec<cpal::Device> = if input {
        host.input_devices().map_err(device_error)?.collect()
    } else {
        host.output_devices().map_err(device_error)?.collect()
    };

    let mut entries = Vec::with_capacity(devices.len());
    let mut candidates = Vec::with_capacity(devices.len());
    #[cfg(target_os = "android")]
    let mut descriptions = Vec::with_capacity(devices.len());
    for device in devices {
        let id = device.id().map_err(device_error)?.to_string();
        let description = device.description().ok();
        let name = description
            .as_ref()
            .map(|description| description.name().to_string())
            .unwrap_or_else(|| id.clone());
        let candidate = description.as_ref().map_or(
            DeviceCandidate {
                is_builtin: false,
                is_speaker: false,
                is_microphone: false,
            },
            |desc| DeviceCandidate {
                is_builtin: desc.interface_type() == InterfaceType::BuiltIn,
                is_speaker: desc.device_type() == DeviceType::Speaker,
                is_microphone: desc.device_type() == DeviceType::Microphone,
            },
        );
        let is_default = default_id.as_deref() == Some(id.as_str());
        candidates.push(candidate);
        entries.push(DeviceInfo {
            id,
            name,
            is_default,
        });
        #[cfg(target_os = "android")]
        descriptions.push(description);
    }

    #[cfg(target_os = "android")]
    let (mut entries, candidates) =
        filter_android_devices(input, entries, candidates, &descriptions);
    let matched_default = entries.iter().any(|entry| entry.is_default);

    if !matched_default
        && default_id
            .as_deref()
            .is_some_and(is_virtual_default_device_id)
        && let Some(index) = pick_fallback_default_index(input, &candidates)
    {
        entries[index].is_default = true;
    }

    Ok(entries)
}

#[cfg(target_os = "android")]
fn filter_android_devices(
    input: bool,
    entries: Vec<DeviceInfo>,
    candidates: Vec<DeviceCandidate>,
    descriptions: &[Option<cpal::DeviceDescription>],
) -> (Vec<DeviceInfo>, Vec<DeviceCandidate>) {
    let android_candidates: Vec<AndroidDeviceCandidate<'_>> = entries
        .iter()
        .zip(descriptions.iter())
        .map(|(entry, desc)| {
            let (kind, interface, address) = match desc {
                Some(desc) => (
                    match desc.device_type() {
                        DeviceType::Speaker => DeviceKind::Speaker,
                        DeviceType::Microphone => DeviceKind::Microphone,
                        DeviceType::Earpiece => DeviceKind::Earpiece,
                        DeviceType::Virtual => DeviceKind::Virtual,
                        DeviceType::Tuner => DeviceKind::Tuner,
                        DeviceType::Unknown => DeviceKind::Unknown,
                        _ => DeviceKind::Other,
                    },
                    match desc.interface_type() {
                        InterfaceType::BuiltIn => DeviceInterfaceKind::BuiltIn,
                        InterfaceType::Virtual => DeviceInterfaceKind::Virtual,
                        InterfaceType::Unknown => DeviceInterfaceKind::Unknown,
                        _ => DeviceInterfaceKind::Other,
                    },
                    desc.address(),
                ),
                None => (DeviceKind::Unknown, DeviceInterfaceKind::Unknown, None),
            };
            AndroidDeviceCandidate {
                kind,
                interface,
                is_default: entry.is_default,
                is_virtual_default: is_virtual_default_device_id(&entry.id),
                address,
            }
        })
        .collect();

    let kept = select_android_device_indices(input, &android_candidates);
    let mut entries: Vec<Option<DeviceInfo>> = entries.into_iter().map(Some).collect();
    let mut candidates: Vec<Option<DeviceCandidate>> = candidates.into_iter().map(Some).collect();
    let mut filtered_entries = Vec::with_capacity(kept.len());
    let mut filtered_candidates = Vec::with_capacity(kept.len());
    for index in kept {
        if let (Some(entry), Some(candidate)) = (entries[index].take(), candidates[index].take()) {
            filtered_entries.push(entry);
            filtered_candidates.push(candidate);
        }
    }
    (filtered_entries, filtered_candidates)
}

fn default_device(host: &cpal::Host, input: bool) -> Result<cpal::Device, AudioError> {
    let device = if input {
        host.default_input_device()
    } else {
        host.default_output_device()
    };
    device.ok_or_else(|| AudioError::Device("no default audio device is available".into()))
}

fn select_device(input: bool, device_id: Option<&str>) -> Result<cpal::Device, AudioError> {
    let host = cpal::default_host();
    if let Some(raw) = device_id {
        let id = raw
            .parse::<cpal::DeviceId>()
            .map_err(|_| AudioError::Device(format!("invalid device ID: {raw}")))?;
        if is_virtual_default_device_id(id.id()) {
            return default_device(&host, input);
        }
        return host
            .device_by_id(&id)
            .ok_or_else(|| AudioError::DeviceNotFound(raw.to_string()));
    }
    default_device(&host, input)
}

fn build_input_stream(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    sample_format: SampleFormat,
    samples: Arc<ArrayQueue<f32>>,
    errors: ErrorSlot,
) -> Result<cpal::Stream, AudioError> {
    match sample_format {
        SampleFormat::F32 => spawn_input::<f32>(device, config, samples, errors),
        SampleFormat::I16 => spawn_input::<i16>(device, config, samples, errors),
        SampleFormat::U16 => spawn_input::<u16>(device, config, samples, errors),
        other => Err(AudioError::UnsupportedSampleFormat(other.to_string())),
    }
}

fn spawn_input<T>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    samples: Arc<ArrayQueue<f32>>,
    errors: ErrorSlot,
) -> Result<cpal::Stream, AudioError>
where
    T: SizedSample + Sample,
    f32: FromSample<T>,
{
    let error_slot = errors;
    let channels = (config.channels as usize).max(1);
    device
        .build_input_stream(
            *config,
            move |data: &[T], _: &cpal::InputCallbackInfo| {
                for frame in data.chunks_exact(channels) {
                    if samples.len() + channels > samples.capacity() {
                        break;
                    }
                    for sample in frame {
                        let _ = samples.push(f32::from_sample(*sample));
                    }
                }
            },
            move |err: cpal::Error| {
                error_slot.set(StreamError {
                    kind: classify_cpal_error(&err),
                    message: err.to_string(),
                });
            },
            None,
        )
        .map_err(device_error)
}

fn build_output_stream(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    sample_format: SampleFormat,
    samples: Arc<ArrayQueue<f32>>,
    errors: ErrorSlot,
) -> Result<cpal::Stream, AudioError> {
    match sample_format {
        SampleFormat::F32 => spawn_output::<f32>(device, config, samples, errors),
        SampleFormat::I16 => spawn_output::<i16>(device, config, samples, errors),
        SampleFormat::U16 => spawn_output::<u16>(device, config, samples, errors),
        other => Err(AudioError::UnsupportedSampleFormat(other.to_string())),
    }
}

fn fill_output_buffer<T>(
    data: &mut [T],
    channels: usize,
    samples: &ArrayQueue<f32>,
    last_samples: &mut [f32; MAX_TRACKED_CHANNELS],
) where
    T: SizedSample + FromSample<f32>,
{
    for frame in data.chunks_mut(channels.max(1)) {
        for (ch, target) in frame.iter_mut().enumerate() {
            let sample = if let Some(s) = samples.pop() {
                if let Some(slot) = last_samples.get_mut(ch) {
                    *slot = s;
                }
                s
            } else if let Some(slot) = last_samples.get_mut(ch) {
                let decayed = *slot * UNDERRUN_DECAY;
                *slot = if decayed.abs() < UNDERRUN_ZERO_THRESHOLD {
                    0.0
                } else {
                    decayed
                };
                *slot
            } else {
                0.0
            };
            *target = T::from_sample(sample);
        }
    }
}

fn spawn_output<T>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    samples: Arc<ArrayQueue<f32>>,
    errors: ErrorSlot,
) -> Result<cpal::Stream, AudioError>
where
    T: SizedSample,
    T: FromSample<f32>,
{
    let error_slot = errors;
    let channels = (config.channels as usize).max(1);
    let mut last_samples = [0.0f32; MAX_TRACKED_CHANNELS];
    device
        .build_output_stream(
            *config,
            move |data: &mut [T], _: &cpal::OutputCallbackInfo| {
                fill_output_buffer(data, channels, &samples, &mut last_samples);
            },
            move |err: cpal::Error| {
                error_slot.set(StreamError {
                    kind: classify_cpal_error(&err),
                    message: err.to_string(),
                });
            },
            None,
        )
        .map_err(device_error)
}

fn classify_cpal_error(err: &cpal::Error) -> StreamErrorKind {
    match err.kind() {
        cpal::ErrorKind::DeviceChanged => StreamErrorKind::DeviceChanged,
        cpal::ErrorKind::DeviceNotAvailable | cpal::ErrorKind::StreamInvalidated => {
            StreamErrorKind::Disconnected
        }
        cpal::ErrorKind::PermissionDenied => StreamErrorKind::PermissionDenied,
        cpal::ErrorKind::Xrun | cpal::ErrorKind::RealtimeDenied => StreamErrorKind::NonFatal,
        _ => StreamErrorKind::Other,
    }
}

fn device_error(err: cpal::Error) -> AudioError {
    match err.kind() {
        cpal::ErrorKind::PermissionDenied => AudioError::PermissionDenied(err.to_string()),
        _ => AudioError::Device(err.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn playback_queue_capacity_scales_with_device_format() {
        assert_eq!(
            playback_queue_capacity(AudioFormat {
                sample_rate_hz: 48_000,
                channels: 2,
            }),
            11_520
        );
        assert_eq!(
            playback_queue_capacity(AudioFormat {
                sample_rate_hz: 44_100,
                channels: 2,
            }),
            10_584
        );
        assert_eq!(
            playback_queue_capacity(AudioFormat {
                sample_rate_hz: 48_000,
                channels: 1,
            }),
            5_760
        );
    }

    #[test]
    fn playback_push_keeps_channel_frame_alignment_when_full() {
        let format = AudioFormat {
            sample_rate_hz: 48_000,
            channels: 2,
        };
        let (stream, queue) = PlaybackStream::new_for_test(format);
        let cap = queue.capacity();
        assert_eq!(cap, 11_520);

        let prefill = vec![0.25f32; cap - 2];
        stream.push(&prefill);
        assert_eq!(queue.len(), cap - 2);
        // 仅剩 1 帧空间时推入 2 帧：写入第 1 帧并整帧丢弃第 2 帧。
        stream.push(&[0.5, -0.5, 0.9, -0.9]);
        assert_eq!(queue.len(), cap);

        // 仅剩 1 个样本槽位（不足 1 个立体声帧）时，必须整帧丢弃，绝不产生单声道错位。
        let odd_queue = Arc::new(ArrayQueue::new(5));
        let odd_stream = PlaybackStream {
            format,
            samples: Arc::clone(&odd_queue),
            errors: ErrorSlot::default(),
            _stream: None,
        };
        odd_stream.push(&[1.0, -1.0, 2.0, -2.0, 3.0, -3.0]);
        assert_eq!(odd_queue.len(), 4);
        assert_eq!(odd_queue.len() % 2, 0);
        odd_stream.push(&[4.0, -4.0]);
        assert_eq!(odd_queue.len(), 4);
        assert_eq!(
            [
                odd_queue.pop(),
                odd_queue.pop(),
                odd_queue.pop(),
                odd_queue.pop(),
            ],
            [Some(1.0), Some(-1.0), Some(2.0), Some(-2.0)]
        );
    }

    #[test]
    fn capture_drain_into_consumes_only_complete_frames_without_channel_shift() {
        let format = AudioFormat {
            sample_rate_hz: 48_000,
            channels: 2,
        };
        let (stream, queue) = CaptureStream::new_for_test(format);
        // 写入 2 个完整立体声帧 + 1 个半帧左声道样本。
        for sample in [1.0, -1.0, 2.0, -2.0, 3.0] {
            queue.push(sample).unwrap();
        }
        let mut out = Vec::new();
        stream.drain_into(&mut out, 100);
        assert_eq!(out, vec![1.0, -1.0, 2.0, -2.0]);
        assert_eq!(stream.buffered_samples(), 1);

        // 补齐右声道及下一帧后，必须保持 [L, R] 声道严格对齐。
        for sample in [-3.0, 4.0, -4.0] {
            queue.push(sample).unwrap();
        }
        stream.drain_into(&mut out, 100);
        assert_eq!(out, vec![3.0, -3.0, 4.0, -4.0]);
        assert_eq!(stream.buffered_samples(), 0);

        // 受 max 上限限制时同样只消费整帧。
        for sample in [5.0, -5.0, 6.0, -6.0, 7.0, -7.0] {
            queue.push(sample).unwrap();
        }
        stream.drain_into(&mut out, 5);
        assert_eq!(out, vec![5.0, -5.0, 6.0, -6.0]);
        assert_eq!(stream.buffered_samples(), 2);
    }

    #[test]
    fn output_callback_underrun_decays_smoothly_to_zero() {
        let queue = Arc::new(ArrayQueue::new(16));
        queue.push(0.8).unwrap();
        queue.push(-0.4).unwrap();

        let mut out = [0.0f32; 400];
        let mut last = [0.0f32; MAX_TRACKED_CHANNELS];
        fill_output_buffer(&mut out, 2, &queue, &mut last);

        assert_eq!(out[0], 0.8);
        assert_eq!(out[1], -0.4);
        assert!((out[2] - 0.8 * UNDERRUN_DECAY).abs() < 1e-6);
        assert!((out[3] - (-0.4 * UNDERRUN_DECAY)).abs() < 1e-6);

        for frame_idx in 1..200 {
            let prev_l = out[(frame_idx - 1) * 2].abs();
            let curr_l = out[frame_idx * 2].abs();
            let prev_r = out[(frame_idx - 1) * 2 + 1].abs();
            let curr_r = out[frame_idx * 2 + 1].abs();
            assert!(curr_l <= prev_l);
            assert!(curr_r <= prev_r);
        }
        assert_eq!(out[398], 0.0);
        assert_eq!(out[399], 0.0);
        assert_eq!(last[0], 0.0);
        assert_eq!(last[1], 0.0);
    }
}
