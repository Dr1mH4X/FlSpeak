//! 语音模块。
//!
//! 默认不启用 `audio` feature：Opus 需要 libopus，设备后端需要系统音频库，都不该
//! 成为整个 workspace 的构建前提。纯逻辑部分（格式常量、重采样、VAD、软削波）
//! 始终参与构建与测试。

pub mod convert;
pub mod format;
pub mod level;
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

#[derive(Debug, thiserror::Error)]
pub enum AudioError {
    #[error("音频设备不可用: {0}")]
    Device(String),

    #[error("音频引擎不可用: {0}")]
    Engine(String),

    #[error("Opus 编解码失败: {0}")]
    Codec(String),

    #[error("不支持的采样格式: {0}")]
    UnsupportedSampleFormat(String),

    #[error("不支持的频道 codec: {0}（只支持 Opus 4/5）")]
    UnsupportedCodec(i32),

    #[error("不支持的声道数: {0}")]
    UnsupportedChannels(u16),
}
