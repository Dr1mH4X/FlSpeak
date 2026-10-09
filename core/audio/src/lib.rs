//! 语音模块。
//!
//! 默认不启用 `audio` feature：Opus 需要 libopus，设备后端需要系统音频库，都不该
//! 成为整个 workspace 的构建前提。纯逻辑部分（格式常量、说话人队列）始终参与构建与测试。

pub mod format;
pub mod queue;

#[cfg(feature = "audio")]
pub mod codec;
#[cfg(feature = "audio")]
pub mod device;

#[derive(Debug, thiserror::Error)]
pub enum AudioError {
    #[error("音频设备不可用: {0}")]
    Device(String),

    #[error("Opus 编解码失败: {0}")]
    Codec(String),

    #[error("不支持的采样格式: {0}")]
    UnsupportedSampleFormat(String),
}
