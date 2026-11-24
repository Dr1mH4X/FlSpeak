//! 语音模块：纯逻辑部分始终参与构建，设备后端才需要 `audio` feature。

pub mod convert;
pub mod format;
pub mod level;
pub mod logging;
pub mod recovery;
pub mod softclip;
pub mod vad;

#[cfg(feature = "audio")]
pub mod capture;
#[cfg(feature = "audio")]
pub mod codec;
#[cfg(feature = "audio")]
pub mod device;
#[cfg(feature = "audio")]
pub mod engine;
#[cfg(feature = "audio")]
pub mod playback;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum CodecError {
    #[error("Opus encode buffer too small: capacity={capacity}, max_data_bytes={max_data_bytes}")]
    BufferTooSmall {
        capacity: usize,
        max_data_bytes: usize,
    },

    #[error("Opus error: {0}")]
    Opus(String),
}

#[derive(Debug, thiserror::Error)]
pub enum AudioError {
    #[error("audio device unavailable: {0}")]
    Device(String),

    #[error("audio device not found: {0}")]
    DeviceNotFound(String),

    #[error("audio device permission denied: {0}")]
    PermissionDenied(String),

    #[error("audio engine unavailable: {0}")]
    Engine(String),

    #[error("Opus codec failed: {0}")]
    Codec(#[from] CodecError),

    #[error("unsupported sample format: {0}")]
    UnsupportedSampleFormat(String),

    #[error("unsupported channel codec: {0} (only Opus 4/5)")]
    UnsupportedCodec(i32),

    #[error("unsupported channel count: {0}")]
    UnsupportedChannels(u16),
}
