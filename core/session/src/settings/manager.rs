//! 设置存储与内存管理层。
//!
//! 全局维护单例 `SettingsManager`（OnceLock + RwLock），
//! 严格限制整仓仅由本文件对设置 JSON 执行底层文件 IO 和 `serde_json` 序列化。

use std::path::{Path, PathBuf};
use std::sync::{OnceLock, RwLock};

use crate::settings::schema::{AppSettings, AudioSettings, UiSettings};

static SETTINGS_MANAGER: OnceLock<SettingsManager> = OnceLock::new();

/// 设置管理器。
pub struct SettingsManager {
    path: PathBuf,
    inner: RwLock<AppSettings>,
}

impl SettingsManager {
    /// 初始化或重置全局设置单例（幂等设计，兼容 Flutter Hot Restart）。
    ///
    /// 若单例已存在，将重新读取 `path` 处的配置文件并更新内存缓存，返回已有的单例。
    pub fn init(path: PathBuf) -> Result<&'static Self, String> {
        let loaded = Self::load_and_migrate(&path)?;

        if let Some(existing) = SETTINGS_MANAGER.get() {
            let mut guard = existing
                .inner
                .write()
                .map_err(|e| format!("获取设置写锁失败: {e}"))?;
            *guard = loaded;
            return Ok(existing);
        }

        let manager = Self {
            path,
            inner: RwLock::new(loaded),
        };

        let _ = SETTINGS_MANAGER.set(manager);
        SETTINGS_MANAGER
            .get()
            .ok_or_else(|| "初始化 SettingsManager 单例失败".to_string())
    }

    /// 获取全局已初始化的单例引用。
    pub fn global() -> Result<&'static Self, String> {
        SETTINGS_MANAGER
            .get()
            .ok_or_else(|| "SettingsManager 尚未初始化，请先调用 init(path)".to_string())
    }

    /// 只读访问当前设置快照。
    pub fn with<R, F: FnOnce(&AppSettings) -> R>(f: F) -> Result<R, String> {
        let manager = Self::global()?;
        let guard = manager
            .inner
            .read()
            .map_err(|e| format!("获取设置读锁失败: {e}"))?;
        Ok(f(&guard))
    }

    /// 克隆一份完整的当前设置对象。
    pub fn get() -> Result<AppSettings, String> {
        Self::with(|settings| settings.clone())
    }

    /// 修改设置并执行原子写盘保存。
    pub fn update<R, F: FnOnce(&mut AppSettings) -> R>(f: F) -> Result<R, String> {
        let manager = Self::global()?;
        let mut guard = manager
            .inner
            .write()
            .map_err(|e| format!("获取设置写锁失败: {e}"))?;

        let result = f(&mut guard);
        Self::save_atomic(&manager.path, &guard)?;
        Ok(result)
    }

    /// 局部更新 UI 设置，避免覆盖网络或服务器状态。
    pub fn update_ui<R, F: FnOnce(&mut UiSettings) -> R>(f: F) -> Result<R, String> {
        Self::update(|settings| f(&mut settings.ui))
    }

    /// 局部更新音频设置。
    pub fn update_audio<R, F: FnOnce(&mut AudioSettings) -> R>(f: F) -> Result<R, String> {
        Self::update(|settings| f(&mut settings.audio))
    }

    /// 获取当前完整配置的 JSON 字符串（严格由 manager 内部序列化）。
    pub fn get_json() -> Result<String, String> {
        let settings = Self::get()?;
        serde_json::to_string(&settings).map_err(|e| format!("序列化设置失败: {e}"))
    }

    /// 从 JSON 字符串更新 UI 设置并原子写盘（严格由 manager 内部反序列化）。
    pub fn update_ui_from_json(json: &str) -> Result<(), String> {
        let ui: UiSettings =
            serde_json::from_str(json).map_err(|e| format!("反序列化 UI 设置失败: {e}"))?;
        Self::update_ui(|current| {
            *current = ui;
        })
    }

    /// 从 JSON 字符串更新音频设置并原子写盘。
    pub fn update_audio_from_json(json: &str) -> Result<(), String> {
        let audio: AudioSettings =
            serde_json::from_str(json).map_err(|e| format!("反序列化音频设置失败: {e}"))?;
        Self::update_audio(|current| {
            *current = audio;
        })
    }

    /// 从磁盘读取设置；若为旧版平铺格式或缺少字段，自动迁移并原子写回。
    fn load_and_migrate(path: &Path) -> Result<AppSettings, String> {
        if !path.exists() {
            let default_settings = AppSettings::default();
            Self::save_atomic(path, &default_settings)?;
            return Ok(default_settings);
        }

        let raw = std::fs::read_to_string(path).map_err(|e| format!("读取配置文件失败: {e}"))?;
        let parsed: serde_json::Value =
            serde_json::from_str(&raw).map_err(|e| format!("配置文件 JSON 语法非法: {e}"))?;

        // 检测是否为旧版平铺格式（根节点存在 nickname/servers/theme 等且无 ui 对象）
        let is_legacy = parsed.is_object()
            && (parsed.get("ui").is_none()
                && (parsed.get("nickname").is_some()
                    || parsed.get("theme").is_some()
                    || parsed.get("servers").is_some()));

        let mut settings: AppSettings = if is_legacy {
            let mut migrated = AppSettings::default();
            if let Some(serde_json::Value::Array(servers)) = parsed.get("servers") {
                migrated.network.servers =
                    serde_json::from_value(serde_json::Value::Array(servers.clone()))
                        .unwrap_or_default();
            }
            if let Some(val) = parsed.get("nickname").and_then(|v| v.as_str()) {
                migrated.ui.nickname = val.to_string();
            }
            if let Some(val) = parsed.get("theme").and_then(|v| v.as_str()) {
                migrated.ui.theme = val.to_string();
            }
            if let Some(val) = parsed.get("motion").and_then(|v| v.as_str()) {
                migrated.ui.motion = val.to_string();
            }
            if let Some(val) = parsed.get("pttHotkey").and_then(|v| v.as_i64()) {
                migrated.ui.ptt_hotkey = Some(val);
            }
            if let Some(val) = parsed.get("channelPanelWidth").and_then(|v| v.as_f64()) {
                migrated.ui.channel_panel_width = Some(val);
            }
            if let Some(val) = parsed.get("voiceMeterSource").and_then(|v| v.as_str()) {
                migrated.ui.voice_meter_source = val.to_string();
            }
            if let Some(val) = parsed.get("locale").and_then(|v| v.as_str()) {
                migrated.ui.locale = Some(val.to_string());
            }
            if let Some(map) = parsed.get("lastConnected") {
                migrated.ui.last_connected =
                    serde_json::from_value(map.clone()).unwrap_or_default();
            }
            if let Some(map) = parsed.get("serverIcons") {
                migrated.ui.server_icons = serde_json::from_value(map.clone()).unwrap_or_default();
            }
            migrated.schema_version = 4;
            migrated
        } else {
            serde_json::from_value(parsed).unwrap_or_default()
        };

        // 统一保持最新的 schema 版本
        if settings.schema_version < 4 {
            settings.schema_version = 4;
        }

        // 迁移或规范化后写盘一次，固化格式
        Self::save_atomic(path, &settings)?;
        Ok(settings)
    }

    /// 原子写入磁盘：临时文件 + fsync + rename 覆盖。
    fn save_atomic(path: &Path, settings: &AppSettings) -> Result<(), String> {
        let serialized =
            serde_json::to_vec_pretty(settings).map_err(|e| format!("序列化设置失败: {e}"))?;

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("创建配置目录失败: {e}"))?;
        }

        let file_name = path
            .file_name()
            .ok_or_else(|| "文件路径缺失文件名".to_string())?;
        let mut temp_name = file_name.to_os_string();
        temp_name.push(format!(".{:032x}.tmp", rand::random::<u128>()));
        let temp = path.with_file_name(temp_name);

        {
            use std::io::Write;
            let mut file = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temp)
                .map_err(|e| format!("创建临时文件失败: {e}"))?;
            file.write_all(&serialized)
                .map_err(|e| format!("写入设置失败: {e}"))?;
            file.sync_all()
                .map_err(|e| format!("同步设置写盘失败: {e}"))?;
        }

        std::fs::rename(&temp, path).map_err(|e| format!("原子替换配置文件失败: {e}"))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_flat_json_migrates_seamlessly_and_retains_data() {
        let dir =
            std::env::temp_dir().join(format!("flspeak-settings-test-{:x}", rand::random::<u64>()));
        let path = dir.join("settings.json");
        let _ = std::fs::create_dir_all(&dir);

        let legacy_json = r#"{
            "schema": 3,
            "nickname": "TestUser",
            "theme": "dark",
            "motion": "off",
            "pttHotkey": 42,
            "servers": [
                {
                    "id": "ts.example.com:9987",
                    "label": "Example Server",
                    "host": "ts.example.com",
                    "port": 9987,
                    "server_password": null,
                    "default_channel": null,
                    "default_channel_password": null
                }
            ]
        }"#;
        std::fs::write(&path, legacy_json).unwrap();

        let settings = SettingsManager::load_and_migrate(&path).unwrap();
        assert_eq!(settings.schema_version, 4);
        assert_eq!(settings.ui.nickname, "TestUser");
        assert_eq!(settings.ui.theme, "dark");
        assert_eq!(settings.ui.motion, "off");
        assert_eq!(settings.ui.ptt_hotkey, Some(42));
        assert_eq!(settings.network.servers.len(), 1);
        assert_eq!(settings.network.servers[0].label, "Example Server");

        // 验证写回的文件已经为嵌套结构
        let raw = std::fs::read_to_string(&path).unwrap();
        let value: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert!(value.get("ui").is_some());
        assert!(value.get("network").is_some());
        assert_eq!(value["ui"]["nickname"], "TestUser");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn atomic_save_leaves_no_temporary_file() {
        let dir =
            std::env::temp_dir().join(format!("flspeak-settings-save-{:x}", rand::random::<u64>()));
        let path = dir.join("settings.json");
        let _ = std::fs::create_dir_all(&dir);

        let mut settings = AppSettings::default();
        settings.ui.nickname = "AtomicUser".to_string();
        SettingsManager::save_atomic(&path, &settings).unwrap();

        assert!(path.exists());
        let read_back = SettingsManager::load_and_migrate(&path).unwrap();
        assert_eq!(read_back.ui.nickname, "AtomicUser");

        // 检查没有留下 tmp 文件
        let entries = std::fs::read_dir(&dir).unwrap();
        let count = entries.filter_map(Result::ok).count();
        assert_eq!(count, 1);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn update_ui_preserves_servers_and_network_state() {
        let dir =
            std::env::temp_dir().join(format!("flspeak-settings-ui-{:x}", rand::random::<u64>()));
        let path = dir.join("settings.json");
        let _ = std::fs::create_dir_all(&dir);

        let mut initial = AppSettings::default();
        initial.network.servers.push(server::ServerProfile {
            id: "ts.example.com:9987".into(),
            label: "Home".into(),
            host: "ts.example.com".into(),
            port: 9987,
            server_password: None,
            default_channel: None,
            default_channel_password: None,
        });
        SettingsManager::save_atomic(&path, &initial).unwrap();

        // 模拟单独更新 UI
        let manager = SettingsManager {
            path: path.clone(),
            inner: RwLock::new(initial),
        };
        {
            let mut guard = manager.inner.write().unwrap();
            guard.ui.nickname = "NewNickname".into();
            SettingsManager::save_atomic(&manager.path, &guard).unwrap();
        }

        let reloaded = SettingsManager::load_and_migrate(&path).unwrap();
        assert_eq!(reloaded.ui.nickname, "NewNickname");
        assert_eq!(reloaded.network.servers.len(), 1);
        assert_eq!(reloaded.network.servers[0].id, "ts.example.com:9987");

        let _ = std::fs::remove_dir_all(&dir);
    }
}
