//! cpal 设备后端：枚举设备、采集、播放。
//!
//! 实时回调里零分配、零锁：采集把样本推进 `ArrayQueue`，播放从队列里取；队列满/空
//! 时宁可丢样本也不阻塞音频线程。

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

/// 采集/播放环形队列容量：2 秒 48kHz 立体声 f32。
const SAMPLE_QUEUE_CAPACITY: usize = 48_000 * 2 * 2;

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
    _stream: cpal::Stream,
}

impl CaptureStream {
    /// 把环形队列里已有的样本按完整源帧取到 `output`，最多 `max` 个。
    pub fn drain_into(&self, output: &mut Vec<f32>, max: usize) {
        output.clear();
        let channels = (self.format.channels as usize).max(1);
        let limit = max - (max % channels);
        for _ in 0..limit {
            match self.samples.pop() {
                Some(sample) => output.push(sample),
                None => break,
            }
        }
        let remainder = output.len() % channels;
        if remainder != 0 {
            output.truncate(output.len() - remainder);
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
    _stream: cpal::Stream,
}

impl PlaybackStream {
    pub fn push(&self, samples: &[f32]) {
        for sample in samples {
            if self.samples.push(*sample).is_err() {
                break;
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
    let samples = Arc::new(ArrayQueue::new(SAMPLE_QUEUE_CAPACITY));
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
        _stream: stream,
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
    let samples = Arc::new(ArrayQueue::new(SAMPLE_QUEUE_CAPACITY));
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
        _stream: stream,
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
    device.ok_or_else(|| AudioError::Device("没有可用的默认音频设备".into()))
}

fn select_device(input: bool, device_id: Option<&str>) -> Result<cpal::Device, AudioError> {
    let host = cpal::default_host();
    if let Some(raw) = device_id {
        let id = raw
            .parse::<cpal::DeviceId>()
            .map_err(|_| AudioError::Device(format!("设备 ID 非法: {raw}")))?;
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
    device
        .build_output_stream(
            *config,
            move |data: &mut [T], _: &cpal::OutputCallbackInfo| {
                for target in data.iter_mut() {
                    let sample = samples.pop().unwrap_or(0.0);
                    *target = T::from_sample(sample);
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
