//! cpal 设备后端：枚举设备、采集、播放。
//!
//! 实时回调里零分配、零锁：采集把样本推进 `ArrayQueue`，播放从队列里取；队列满/空
//! 时宁可丢样本也不阻塞音频线程。

use std::sync::Arc;
use std::sync::Mutex;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, Sample, SampleFormat, SizedSample};
use crossbeam_queue::ArrayQueue;

use crate::AudioError;
use crate::format::AudioFormat;

/// 采集/播放环形队列容量：2 秒 48kHz 立体声 f32。
const SAMPLE_QUEUE_CAPACITY: usize = 48_000 * 2 * 2;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceInfo {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

#[derive(Clone, Default)]
struct ErrorSlot(Arc<Mutex<Option<String>>>);

impl ErrorSlot {
    fn set(&self, message: String) {
        if let Ok(mut slot) = self.0.lock() {
            *slot = Some(message);
        }
    }

    fn take(&self) -> Option<String> {
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
    /// 把环形队列里已有的样本取到 `output`，最多 `max` 个。
    pub fn drain_into(&self, output: &mut Vec<f32>, max: usize) {
        output.clear();
        for _ in 0..max {
            match self.samples.pop() {
                Some(sample) => output.push(sample),
                None => break,
            }
        }
    }

    pub fn buffered_samples(&self) -> usize {
        self.samples.len()
    }

    pub fn take_error(&self) -> Option<String> {
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

    pub fn take_error(&self) -> Option<String> {
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

    devices
        .into_iter()
        .map(|device| {
            let id = device.id().map_err(device_error)?.to_string();
            let name = device
                .description()
                .map(|description| description.name().to_string())
                .unwrap_or_else(|_| id.clone());
            let is_default = default_id.as_deref() == Some(id.as_str());
            Ok(DeviceInfo {
                id,
                name,
                is_default,
            })
        })
        .collect()
}

fn select_device(input: bool, device_id: Option<&str>) -> Result<cpal::Device, AudioError> {
    let host = cpal::default_host();
    if let Some(raw) = device_id {
        let id = raw
            .parse::<cpal::DeviceId>()
            .map_err(|_| AudioError::Device(format!("设备 ID 非法: {raw}")))?;
        return host
            .device_by_id(&id)
            .ok_or_else(|| AudioError::Device(format!("找不到设备 {raw}")));
    }
    let device = if input {
        host.default_input_device()
    } else {
        host.default_output_device()
    };
    device.ok_or_else(|| AudioError::Device("没有可用的默认音频设备".into()))
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
    device
        .build_input_stream(
            *config,
            move |data: &[T], _: &cpal::InputCallbackInfo| {
                for sample in data {
                    if samples.push(f32::from_sample(*sample)).is_err() {
                        break;
                    }
                }
            },
            move |err: cpal::Error| error_slot.set(err.to_string()),
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
            move |err: cpal::Error| error_slot.set(err.to_string()),
            None,
        )
        .map_err(device_error)
}

fn device_error(err: cpal::Error) -> AudioError {
    AudioError::Device(err.to_string())
}
