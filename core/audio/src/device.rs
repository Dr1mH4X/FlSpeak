//! cpal 设备后端：枚举设备、采集、播放。
//!
//! 播放缓冲用互斥锁保护的有界队列，回调里逐样本取值；采集回调每帧分配一个 Vec。
//! 这两处在正式出流前都要换成无锁环形缓冲，见 docs/audio.md。

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, Sample, SampleFormat, SizedSample};

use crate::AudioError;
use crate::format::AudioFormat;

/// 播放缓冲上限：2 秒 48kHz 立体声。
const MAX_BUFFERED_SAMPLES: usize = 48_000 * 2 * 2;

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

/// 采集句柄。持有 stream 保证流不被销毁；`take_error` 取回调上报的流错误。
pub struct CaptureHandle {
    pub format: AudioFormat,
    errors: ErrorSlot,
    _stream: cpal::Stream,
}

impl CaptureHandle {
    pub fn take_error(&self) -> Option<String> {
        self.errors.take()
    }
}

/// 播放句柄。`push` 写入交织立体声样本。
pub struct PlaybackHandle {
    pub format: AudioFormat,
    buffer: Arc<Mutex<VecDeque<f32>>>,
    errors: ErrorSlot,
    _stream: cpal::Stream,
}

impl PlaybackHandle {
    pub fn push(&self, samples: &[f32]) {
        let Ok(mut buffer) = self.buffer.lock() else {
            return;
        };
        if samples.len() >= MAX_BUFFERED_SAMPLES {
            buffer.clear();
            buffer.extend(
                samples[samples.len() - MAX_BUFFERED_SAMPLES..]
                    .iter()
                    .copied(),
            );
            return;
        }
        while buffer.len() + samples.len() > MAX_BUFFERED_SAMPLES {
            buffer.pop_front();
        }
        buffer.extend(samples.iter().copied());
    }

    pub fn buffered_samples(&self) -> usize {
        self.buffer.lock().map_or(0, |buffer| buffer.len())
    }

    pub fn take_error(&self) -> Option<String> {
        self.errors.take()
    }
}

pub fn start_capture(
    device_id: Option<&str>,
    on_frame: impl FnMut(&[f32]) + Send + 'static,
) -> Result<CaptureHandle, AudioError> {
    let device = select_device(true, device_id)?;
    let supported = device.default_input_config().map_err(device_error)?;
    let format = AudioFormat {
        sample_rate_hz: supported.sample_rate(),
        channels: supported.channels(),
    };
    let errors = ErrorSlot::default();
    let stream = build_input_stream(
        &device,
        &supported.config(),
        supported.sample_format(),
        Box::new(on_frame),
        errors.clone(),
    )?;
    stream.play().map_err(device_error)?;
    Ok(CaptureHandle {
        format,
        errors,
        _stream: stream,
    })
}

pub fn start_playback(device_id: Option<&str>) -> Result<PlaybackHandle, AudioError> {
    let device = select_device(false, device_id)?;
    let supported = device.default_output_config().map_err(device_error)?;
    let format = AudioFormat {
        sample_rate_hz: supported.sample_rate(),
        channels: supported.channels(),
    };
    let buffer = Arc::new(Mutex::new(VecDeque::<f32>::new()));
    let errors = ErrorSlot::default();
    let stream = build_output_stream(
        &device,
        &supported.config(),
        supported.sample_format(),
        Arc::clone(&buffer),
        errors.clone(),
    )?;
    stream.play().map_err(device_error)?;
    Ok(PlaybackHandle {
        format,
        buffer,
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

/// 采集回调：交出交错排列的 f32 样本。
type FrameSink = Box<dyn FnMut(&[f32]) + Send>;

fn build_input_stream(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    sample_format: SampleFormat,
    on_frame: FrameSink,
    errors: ErrorSlot,
) -> Result<cpal::Stream, AudioError> {
    match sample_format {
        SampleFormat::F32 => spawn_input::<f32>(device, config, on_frame, errors),
        SampleFormat::I16 => spawn_input::<i16>(device, config, on_frame, errors),
        SampleFormat::U16 => spawn_input::<u16>(device, config, on_frame, errors),
        other => Err(AudioError::UnsupportedSampleFormat(other.to_string())),
    }
}

fn spawn_input<T>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    mut on_frame: FrameSink,
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
                let samples: Vec<f32> = data
                    .iter()
                    .map(|sample| f32::from_sample(*sample))
                    .collect();
                on_frame(&samples);
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
    buffer: Arc<Mutex<VecDeque<f32>>>,
    errors: ErrorSlot,
) -> Result<cpal::Stream, AudioError> {
    match sample_format {
        SampleFormat::F32 => spawn_output::<f32>(device, config, buffer, errors),
        SampleFormat::I16 => spawn_output::<i16>(device, config, buffer, errors),
        SampleFormat::U16 => spawn_output::<u16>(device, config, buffer, errors),
        other => Err(AudioError::UnsupportedSampleFormat(other.to_string())),
    }
}

fn spawn_output<T>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    buffer: Arc<Mutex<VecDeque<f32>>>,
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
                let Ok(mut buffer) = buffer.lock() else {
                    return;
                };
                for sample in data.iter_mut() {
                    *sample = T::from_sample(buffer.pop_front().unwrap_or(0.0));
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
