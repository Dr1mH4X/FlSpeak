//! 应用程序设置 Schema 声明层。
//!
//! 所有设置按职责拆分为子结构体，统一挂载到根结构体 `AppSettings` 下。
//! 所有结构体均标记 `#[serde(default, rename_all = "camelCase")]`，
//! 确保在字段缺失或跨版本读取时能够自动回退到默认值。

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use server::ServerProfile;

/// 根配置结构体。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct AppSettings {
    /// 配置 Schema 版本号。
    pub schema_version: u32,
    /// 网络与服务器配置。
    pub network: NetworkSettings,
    /// 音频输入输出与语音感应参数。
    pub audio: AudioSettings,
    /// 用户界面与交互偏好。
    pub ui: UiSettings,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            schema_version: 4,
            network: NetworkSettings::default(),
            audio: AudioSettings::default(),
            ui: UiSettings::default(),
        }
    }
}

/// 网络与服务器配置项。
///
/// 注意：协议与运行常量（如握手超时、快照间隔、历史限制）保持在代码内硬编码，
/// 避免写入配置持久化文件，此处只收纳用户真正可配置的数据。
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct NetworkSettings {
    /// 登记的服务器列表。
    pub servers: Vec<ServerProfile>,
}

/// 音频参数设置。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct AudioSettings {
    /// 语音感应门限能量（VAD threshold）。
    pub vad_threshold: f32,
    /// 语音感应判定静音后的挂断保留帧数（每帧 20ms）。
    pub vad_hangover_frames: usize,
    /// 是否开启按住说话模式。
    pub ptt_mode: bool,
    /// 用户选择的音频输入设备 ID（None 表示系统默认）。
    pub input_device_id: Option<String>,
    /// 用户选择的音频输出设备 ID（None 表示系统默认）。
    pub output_device_id: Option<String>,
}

impl Default for AudioSettings {
    fn default() -> Self {
        Self {
            vad_threshold: 0.015,
            vad_hangover_frames: 15,
            ptt_mode: false,
            input_device_id: None,
            output_device_id: None,
        }
    }
}

/// 界面与交互偏好设置。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct UiSettings {
    /// 客户端昵称。
    pub nickname: String,
    /// 主题模式：system / light / dark。
    pub theme: String,
    /// 动效设置：system / on / off。
    pub motion: String,
    /// 按住说话快捷键键码（LogicalKeyboardKey keyId）。
    pub ptt_hotkey: Option<i64>,
    /// 频道栏宽度（逻辑像素）。
    pub channel_panel_width: Option<f64>,
    /// 电平条跟随源：microphone / received。
    pub voice_meter_source: String,
    /// 语言编码（如 zh / en，None 为跟随系统）。
    pub locale: Option<String>,
    /// 服务器最后连接时间戳映射（server_id -> timestamp ms）。
    pub last_connected: HashMap<String, u64>,
    /// 服务器自定义图标映射（server_id -> icon_id）。
    pub server_icons: HashMap<String, String>,
}

impl UiSettings {
    /// 默认昵称常量。
    pub const DEFAULT_NICKNAME: &'static str = "FlSpeakUser";

    /// 规范化昵称：去除前后空白字符，若为空值则自动回退为默认昵称。
    pub fn normalize_nickname(&mut self) {
        let trimmed = self.nickname.trim();
        if trimmed.is_empty() {
            self.nickname = Self::DEFAULT_NICKNAME.to_string();
        } else {
            self.nickname = trimmed.to_string();
        }
    }
}

impl Default for UiSettings {
    fn default() -> Self {
        Self {
            nickname: Self::DEFAULT_NICKNAME.to_string(),
            theme: "system".to_string(),
            motion: "system".to_string(),
            ptt_hotkey: None,
            channel_panel_width: None,
            voice_meter_source: "microphone".to_string(),
            locale: None,
            last_connected: HashMap::new(),
            server_icons: HashMap::new(),
        }
    }
}
