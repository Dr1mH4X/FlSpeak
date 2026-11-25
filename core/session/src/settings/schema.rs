//! 设置 Schema：子结构体挂到 `AppSettings`，全部带 `#[serde(default, rename_all = "camelCase")]`。

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
            schema_version: 5,
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

fn default_true() -> bool {
    true
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
    /// 是否启用 RNNoise 语音降噪（仅对 Opus Voice 单声道生效）。
    #[serde(default = "default_true")]
    pub noise_suppression: bool,
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
            noise_suppression: true,
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
    /// 是否启用深色纯黑背景。
    pub pure_black: bool,
    /// 当前主题种子色（ARGB32）。
    #[serde(
        default = "UiSettings::default_primary_color",
        deserialize_with = "UiSettings::deserialize_primary_color"
    )]
    pub primary_color: u32,
    /// 主题预设与自定义色板列表（ARGB32）。
    #[serde(default = "UiSettings::default_primary_colors")]
    pub primary_colors: Vec<u32>,
    /// 主题色彩生成风格：vivid / tinted / soft / monochrome。
    pub color_style: String,
    /// 窄屏是否启用悬浮底部导航栏（否则停靠底边）。
    pub floating_navigation_bar: bool,
    /// 自定义全局字体族名称（None 表示跟随默认字体）。
    pub font_family: Option<String>,
    /// 是否启用自定义全局字体缩放。
    pub text_scale_enabled: bool,
    /// 自定义字体缩放倍率（0.8 - 1.4）。
    pub text_scale: f64,
    /// 动效设置：system / on / off。
    pub motion: String,
    /// 液态玻璃效果档位：none / standard / ultra。
    pub liquid_glass: String,
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
    /// 屏幕共享默认分辨率档位：720p / 1080p。
    pub screen_share_resolution: String,
    /// 屏幕共享默认帧率档位：30 / 60。
    pub screen_share_frame_rate: u32,
    /// 屏幕共享视频编码与硬件加速偏好：vp8 / h264。
    pub screen_share_codec: String,
    /// 屏幕共享弱网降级策略：maintainResolution / maintainFramerate。
    pub screen_share_degradation: String,
    /// 是否在启动时自动检查更新。
    pub auto_check_update: bool,
    /// 日志等级：debug / info / warning / error。
    pub log_level: String,
}

impl UiSettings {
    /// 默认昵称常量。
    pub const DEFAULT_NICKNAME: &'static str = "FlSpeakUser";

    /// 默认主题主色（ARGB32）。
    pub const DEFAULT_PRIMARY_COLOR: u32 = 0xFFC4_4D78;

    /// 默认色板列表（首项为品牌默认色，其余对齐经典系统色板）。
    pub const DEFAULT_PRIMARY_COLORS: [u32; 9] = [
        Self::DEFAULT_PRIMARY_COLOR,
        0xFF00_7AFF,
        0xFFCB_30E0,
        0xFFFF_2D55,
        0xFFFF_383C,
        0xFFFF_8D28,
        0xFFFF_CC00,
        0xFF34_C759,
        0xFF8E_8E93,
    ];

    pub fn default_primary_color() -> u32 {
        Self::DEFAULT_PRIMARY_COLOR
    }

    pub fn default_primary_colors() -> Vec<u32> {
        Self::DEFAULT_PRIMARY_COLORS.to_vec()
    }

    fn deserialize_primary_color<'de, D>(deserializer: D) -> Result<u32, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        Ok(Option::<u32>::deserialize(deserializer)?.unwrap_or(Self::DEFAULT_PRIMARY_COLOR))
    }

    /// 当前构建形态的默认日志等级。
    pub fn default_log_level() -> &'static str {
        if cfg!(debug_assertions) {
            "debug"
        } else {
            "info"
        }
    }

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
            pure_black: false,
            primary_color: Self::DEFAULT_PRIMARY_COLOR,
            primary_colors: Self::DEFAULT_PRIMARY_COLORS.to_vec(),
            color_style: "vivid".to_string(),
            floating_navigation_bar: true,
            font_family: None,
            text_scale_enabled: false,
            text_scale: 1.0,
            motion: "system".to_string(),
            liquid_glass: "none".to_string(),
            ptt_hotkey: None,
            channel_panel_width: None,
            voice_meter_source: "microphone".to_string(),
            locale: None,
            last_connected: HashMap::new(),
            server_icons: HashMap::new(),
            screen_share_resolution: "720p".to_string(),
            screen_share_frame_rate: 30,
            screen_share_codec: "h264".to_string(),
            screen_share_degradation: "maintainFramerate".to_string(),
            auto_check_update: true,
            log_level: Self::default_log_level().to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{AudioSettings, UiSettings};

    #[test]
    fn audio_settings_noise_suppression_defaults_to_true_and_backfills_legacy_json() {
        assert!(AudioSettings::default().noise_suppression);
        let legacy: AudioSettings =
            serde_json::from_str(r#"{"vadThreshold":0.02,"vadHangoverFrames":10,"pttMode":true}"#)
                .unwrap();
        assert!(legacy.noise_suppression);
        assert_eq!(legacy.vad_threshold, 0.02);
        assert!(legacy.ptt_mode);

        let disabled: AudioSettings =
            serde_json::from_str(r#"{"noiseSuppression":false}"#).unwrap();
        assert!(!disabled.noise_suppression);
    }

    #[test]
    fn ui_settings_screen_share_defaults_match_spec() {
        let ui = UiSettings::default();
        assert_eq!(ui.liquid_glass, "none");
        assert!(!ui.pure_black);
        assert_eq!(ui.primary_color, UiSettings::DEFAULT_PRIMARY_COLOR);
        assert_eq!(ui.primary_colors, UiSettings::DEFAULT_PRIMARY_COLORS);
        assert_eq!(ui.color_style, "vivid");
        assert!(ui.floating_navigation_bar);
        assert_eq!(ui.font_family, None);
        assert!(!ui.text_scale_enabled);
        assert_eq!(ui.text_scale, 1.0);
        assert_eq!(ui.screen_share_resolution, "720p");
        assert_eq!(ui.screen_share_frame_rate, 30);
        assert_eq!(ui.screen_share_codec, "h264");
        assert_eq!(ui.screen_share_degradation, "maintainFramerate");
    }

    #[test]
    fn ui_settings_backfills_missing_theme_fields_from_legacy_json() {
        let ui: UiSettings =
            serde_json::from_str(r#"{"nickname":"Alice","primaryColor":null}"#).unwrap();
        assert_eq!(ui.nickname, "Alice");
        assert_eq!(ui.primary_color, UiSettings::DEFAULT_PRIMARY_COLOR);
        assert_eq!(ui.primary_colors, UiSettings::DEFAULT_PRIMARY_COLORS);
        assert!(ui.floating_navigation_bar);
    }
}
