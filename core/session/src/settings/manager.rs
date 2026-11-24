//! 设置存储：整仓只有这里对设置 JSON 做文件 IO 与序列化。

use std::path::{Path, PathBuf};
use std::sync::{OnceLock, RwLock};

use crate::settings::schema::{AppSettings, AudioSettings, UiSettings};

static SETTINGS_MANAGER: OnceLock<SettingsManager> = OnceLock::new();
type AudioListener = Box<dyn Fn(&AudioSettings) -> bool + Send + Sync>;
static AUDIO_LISTENERS: OnceLock<RwLock<Vec<AudioListener>>> = OnceLock::new();

/// 设置管理器。
pub struct SettingsManager {
    path: RwLock<PathBuf>,
    inner: RwLock<AppSettings>,
}

impl SettingsManager {
    fn listeners() -> &'static RwLock<Vec<AudioListener>> {
        AUDIO_LISTENERS.get_or_init(|| RwLock::new(Vec::new()))
    }

    /// 订阅音频设置变更；返回 `false` 时自动注销监听器。
    pub fn subscribe_audio(listener: impl Fn(&AudioSettings) -> bool + Send + Sync + 'static) {
        if let Ok(mut guard) = Self::listeners().write() {
            guard.push(Box::new(listener));
        }
    }

    fn notify_audio_listeners(audio: &AudioSettings) {
        if let Ok(mut guard) = Self::listeners().write() {
            guard.retain(|listener| listener(audio));
        }
    }

    /// 初始化或重置全局设置单例（幂等设计，兼容 Flutter Hot Restart）。
    ///
    /// 若单例已存在，将重新读取 `path` 处的配置文件并更新内存缓存，返回已有的单例。
    pub fn init(path: PathBuf) -> Result<&'static Self, String> {
        let loaded = Self::load_and_migrate(&path)?;

        if let Some(existing) = SETTINGS_MANAGER.get() {
            {
                let mut path_guard = existing
                    .path
                    .write()
                    .map_err(|e| format!("failed to acquire the settings path lock: {e}"))?;
                *path_guard = path;
                let mut guard = existing
                    .inner
                    .write()
                    .map_err(|e| format!("failed to acquire the settings write lock: {e}"))?;
                *guard = loaded.clone();
            }
            Self::notify_audio_listeners(&loaded.audio);
            return Ok(existing);
        }

        let manager = Self {
            path: RwLock::new(path),
            inner: RwLock::new(loaded.clone()),
        };

        let _ = SETTINGS_MANAGER.set(manager);
        Self::notify_audio_listeners(&loaded.audio);
        SETTINGS_MANAGER
            .get()
            .ok_or_else(|| "failed to initialize the SettingsManager singleton".to_string())
    }

    /// 获取全局已初始化的单例引用。
    pub fn global() -> Result<&'static Self, String> {
        SETTINGS_MANAGER
            .get()
            .ok_or_else(|| "SettingsManager is not initialized; call init(path) first".to_string())
    }

    /// 设置文件所在目录，供同级的更新缓存等旁路文件使用。
    pub(crate) fn data_dir() -> Result<PathBuf, String> {
        let manager = Self::global()?;
        let path_guard = manager
            .path
            .read()
            .map_err(|e| format!("failed to acquire the settings path lock: {e}"))?;
        path_guard
            .parent()
            .map(Path::to_path_buf)
            .ok_or_else(|| "settings file has no parent directory".to_string())
    }

    /// 只读访问当前设置快照。
    pub fn with<R, F: FnOnce(&AppSettings) -> R>(f: F) -> Result<R, String> {
        let manager = Self::global()?;
        let guard = manager
            .inner
            .read()
            .map_err(|e| format!("failed to acquire the settings read lock: {e}"))?;
        Ok(f(&guard))
    }

    /// 克隆一份完整的当前设置对象。
    pub fn get() -> Result<AppSettings, String> {
        Self::with(|settings| settings.clone())
    }

    /// 修改设置并执行原子写盘保存。
    pub fn update<R, F: FnOnce(&mut AppSettings) -> R>(f: F) -> Result<R, String> {
        Self::update_with_notify(f, true)
    }

    fn update_with_notify<R, F: FnOnce(&mut AppSettings) -> R>(
        f: F,
        notify_audio: bool,
    ) -> Result<R, String> {
        let manager = Self::global()?;
        let (result, changed_audio) = {
            let path_guard = manager
                .path
                .read()
                .map_err(|e| format!("failed to acquire the settings path lock: {e}"))?;
            let mut guard = manager
                .inner
                .write()
                .map_err(|e| format!("failed to acquire the settings write lock: {e}"))?;

            let prev_audio = guard.audio.clone();
            let result = f(&mut guard);
            Self::save_atomic(&path_guard, &guard)?;
            let changed_audio =
                (notify_audio && guard.audio != prev_audio).then(|| guard.audio.clone());
            (result, changed_audio)
        };
        if let Some(audio) = changed_audio {
            Self::notify_audio_listeners(&audio);
        }
        Ok(result)
    }

    /// 局部更新 UI 设置，避免覆盖网络或服务器状态。
    pub fn update_ui<R, F: FnOnce(&mut UiSettings) -> R>(f: F) -> Result<R, String> {
        Self::update(|settings| {
            let res = f(&mut settings.ui);
            settings.ui.normalize_nickname();
            res
        })
    }

    /// 局部更新音频设置。
    pub fn update_audio<R, F: FnOnce(&mut AudioSettings) -> R>(f: F) -> Result<R, String> {
        Self::update(|settings| f(&mut settings.audio))
    }

    /// 由会话 Actor 更新已生效的音频设备 ID 并原子写盘，不反向触发音频设置监听循环。
    pub(crate) fn update_audio_devices(
        input: Option<String>,
        output: Option<String>,
    ) -> Result<(), String> {
        Self::update_with_notify(
            |settings| {
                settings.audio.input_device_id = input;
                settings.audio.output_device_id = output;
            },
            false,
        )
    }

    /// 获取当前完整配置的 JSON 字符串（严格由 manager 内部序列化）。
    pub fn get_json() -> Result<String, String> {
        let settings = Self::get()?;
        serde_json::to_string(&settings).map_err(|e| format!("failed to serialize settings: {e}"))
    }

    /// 从 JSON 字符串更新 UI 设置并原子写盘（严格由 manager 内部反序列化）。
    pub fn update_ui_from_json(json: &str) -> Result<(), String> {
        let mut ui: UiSettings = serde_json::from_str(json)
            .map_err(|e| format!("failed to deserialize UI settings: {e}"))?;
        ui.normalize_nickname();
        Self::update_ui(|current| {
            *current = ui;
        })
    }

    /// 从 JSON 字符串更新音频设置并原子写盘（保留 Actor 管理的设备 ID）。
    pub fn update_audio_from_json(json: &str) -> Result<(), String> {
        let audio: AudioSettings = serde_json::from_str(json)
            .map_err(|e| format!("failed to deserialize audio settings: {e}"))?;
        Self::update_audio(|current| {
            let input_device_id = current.input_device_id.clone();
            let output_device_id = current.output_device_id.clone();
            *current = audio;
            current.input_device_id = input_device_id;
            current.output_device_id = output_device_id;
        })
    }

    /// 从磁盘读取设置；若为旧版平铺格式或缺少字段，自动迁移并原子写回。
    fn load_and_migrate(path: &Path) -> Result<AppSettings, String> {
        if !path.exists() {
            let default_settings = AppSettings::default();
            Self::save_atomic(path, &default_settings)?;
            return Ok(default_settings);
        }

        let raw = std::fs::read_to_string(path)
            .map_err(|e| format!("failed to read the settings file: {e}"))?;
        let parsed: serde_json::Value = serde_json::from_str(&raw)
            .map_err(|e| format!("invalid JSON in the settings file: {e}"))?;

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
            if let Some(audio) = parsed.get("audio")
                && let Ok(audio_settings) = serde_json::from_value::<AudioSettings>(audio.clone())
            {
                migrated.audio = audio_settings;
            } else if let Some(noise_suppression) =
                parsed.get("noiseSuppression").and_then(|v| v.as_bool())
            {
                migrated.audio.noise_suppression = noise_suppression;
            }
            migrated.schema_version = 4;
            migrated
        } else {
            serde_json::from_value(parsed).unwrap_or_default()
        };

        // 规范化 UI 设置（例如空昵称自动回退为默认昵称）
        settings.ui.normalize_nickname();

        // 统一保持最新的 schema 版本并迁移存量配置
        if settings.schema_version < 5 {
            for value in settings.ui.server_icons.values_mut() {
                if value == "community" {
                    *value = "auto".to_string();
                }
            }
            settings.schema_version = 5;
        }

        // 迁移或规范化后写盘一次，固化格式
        Self::save_atomic(path, &settings)?;
        Ok(settings)
    }

    /// 原子写入磁盘：临时文件 + fsync + rename 覆盖。
    fn save_atomic(path: &Path, settings: &AppSettings) -> Result<(), String> {
        let serialized = serde_json::to_vec_pretty(settings)
            .map_err(|e| format!("failed to serialize settings: {e}"))?;

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("failed to create the settings directory: {e}"))?;
        }

        let file_name = path
            .file_name()
            .ok_or_else(|| "file path is missing a file name".to_string())?;
        let mut temp_name = file_name.to_os_string();
        temp_name.push(format!(".{:032x}.tmp", rand::random::<u128>()));
        let temp = path.with_file_name(temp_name);

        {
            use std::io::Write;
            let mut file = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temp)
                .map_err(|e| format!("failed to create a temporary file: {e}"))?;
            file.write_all(&serialized)
                .map_err(|e| format!("failed to write settings: {e}"))?;
            file.sync_all()
                .map_err(|e| format!("failed to sync settings to disk: {e}"))?;
        }

        std::fs::rename(&temp, path)
            .map_err(|e| format!("failed to atomically replace the settings file: {e}"))?;
        Ok(())
    }
}

#[cfg(test)]
pub(crate) static TEST_SETTINGS_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

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
        assert_eq!(settings.schema_version, 5);
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

        // 验证前端 fallback 写入的 audio.noiseSuppression = false 在迁移时不会丢失
        let fallback_json = r#"{
            "nickname": "FallbackUser",
            "noiseSuppression": false,
            "audio": { "noiseSuppression": false }
        }"#;
        std::fs::write(&path, fallback_json).unwrap();
        let migrated = SettingsManager::load_and_migrate(&path).unwrap();
        assert!(!migrated.audio.noise_suppression);

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
            path: RwLock::new(path.clone()),
            inner: RwLock::new(initial),
        };
        {
            let mut guard = manager.inner.write().unwrap();
            guard.ui.nickname = "NewNickname".into();
            let manager_path = manager.path.read().unwrap();
            SettingsManager::save_atomic(&manager_path, &guard).unwrap();
        }

        let reloaded = SettingsManager::load_and_migrate(&path).unwrap();
        assert_eq!(reloaded.ui.nickname, "NewNickname");
        assert_eq!(reloaded.network.servers.len(), 1);
        assert_eq!(reloaded.network.servers[0].id, "ts.example.com:9987");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn nickname_normalization_and_fallback() {
        let dir =
            std::env::temp_dir().join(format!("flspeak-settings-nick-{:x}", rand::random::<u64>()));
        let path = dir.join("settings.json");
        let _ = std::fs::create_dir_all(&dir);

        let initial = AppSettings::default();
        SettingsManager::save_atomic(&path, &initial).unwrap();

        let manager = SettingsManager {
            path: RwLock::new(path.clone()),
            inner: RwLock::new(initial),
        };

        // 1. 测试 update_ui 闭包内设为空，出口处自动规范化为默认昵称
        {
            let mut guard = manager.inner.write().unwrap();
            guard.ui.nickname = "   ".into();
            guard.ui.normalize_nickname();
            let manager_path = manager.path.read().unwrap();
            SettingsManager::save_atomic(&manager_path, &guard).unwrap();
        }
        let reloaded = SettingsManager::load_and_migrate(&path).unwrap();
        assert_eq!(reloaded.ui.nickname, UiSettings::DEFAULT_NICKNAME);

        // 2. 测试带前后空白的昵称自动 trim
        {
            let mut guard = manager.inner.write().unwrap();
            guard.ui.nickname = "  Bob  ".into();
            guard.ui.normalize_nickname();
            let manager_path = manager.path.read().unwrap();
            SettingsManager::save_atomic(&manager_path, &guard).unwrap();
        }
        let reloaded = SettingsManager::load_and_migrate(&path).unwrap();
        assert_eq!(reloaded.ui.nickname, "Bob");

        // 3. 测试 load_and_migrate 加载空昵称时回退
        let empty_nick_json = r#"{
            "schemaVersion": 4,
            "network": { "servers": [] },
            "audio": { "vadThreshold": 0.015, "vadHangoverFrames": 15, "pttMode": false, "inputDeviceId": null, "outputDeviceId": null },
            "ui": { "nickname": "" }
        }"#;
        std::fs::write(&path, empty_nick_json).unwrap();
        let loaded = SettingsManager::load_and_migrate(&path).unwrap();
        assert_eq!(loaded.ui.nickname, UiSettings::DEFAULT_NICKNAME);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn v4_server_icons_migrate_default_community_to_auto_once() {
        let dir = std::env::temp_dir().join(format!(
            "flspeak-settings-icons-{:x}",
            rand::random::<u64>()
        ));
        let path = dir.join("settings.json");
        let _ = std::fs::create_dir_all(&dir);

        let v4_json = r#"{
            "schemaVersion": 4,
            "network": { "servers": [] },
            "audio": { "vadThreshold": 0.015, "vadHangoverFrames": 15, "pttMode": false, "inputDeviceId": null, "outputDeviceId": null },
            "ui": {
                "nickname": "User",
                "serverIcons": {
                    "a:9987": "community",
                    "b:9987": "gaming"
                }
            }
        }"#;
        std::fs::write(&path, v4_json).unwrap();
        let migrated = SettingsManager::load_and_migrate(&path).unwrap();
        assert_eq!(migrated.schema_version, 5);
        assert_eq!(
            migrated.ui.server_icons.get("a:9987").map(String::as_str),
            Some("auto")
        );
        assert_eq!(
            migrated.ui.server_icons.get("b:9987").map(String::as_str),
            Some("gaming")
        );

        // v5 之后用户主动选回 "community" 时必须保留。
        let v5_json = r#"{
            "schemaVersion": 5,
            "network": { "servers": [] },
            "audio": { "vadThreshold": 0.015, "vadHangoverFrames": 15, "pttMode": false, "inputDeviceId": null, "outputDeviceId": null },
            "ui": {
                "nickname": "User",
                "serverIcons": {
                    "a:9987": "community"
                }
            }
        }"#;
        std::fs::write(&path, v5_json).unwrap();
        let reloaded = SettingsManager::load_and_migrate(&path).unwrap();
        assert_eq!(
            reloaded.ui.server_icons.get("a:9987").map(String::as_str),
            Some("community")
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn subscribe_audio_notifies_and_prunes_disconnected_listeners() {
        let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let active = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(true));

        let seen_cb = std::sync::Arc::clone(&seen);
        let active_cb = std::sync::Arc::clone(&active);
        SettingsManager::subscribe_audio(move |audio| {
            if !active_cb.load(std::sync::atomic::Ordering::Relaxed) {
                return false;
            }
            seen_cb
                .lock()
                .unwrap()
                .push((audio.vad_threshold, audio.vad_hangover_frames));
            true
        });

        let first = AudioSettings {
            vad_threshold: 0.032,
            vad_hangover_frames: 9,
            ..AudioSettings::default()
        };
        SettingsManager::notify_audio_listeners(&first);
        assert_eq!(seen.lock().unwrap().as_slice(), &[(0.032, 9)]);

        active.store(false, std::sync::atomic::Ordering::Relaxed);
        let second = AudioSettings {
            vad_threshold: 0.055,
            vad_hangover_frames: 4,
            ..AudioSettings::default()
        };
        SettingsManager::notify_audio_listeners(&second);
        assert_eq!(seen.lock().unwrap().len(), 1);
    }

    #[test]
    fn update_audio_from_json_preserves_actor_managed_device_ids() {
        let _guard = TEST_SETTINGS_LOCK.blocking_lock();
        let dir = std::env::temp_dir().join(format!(
            "flspeak-settings-audio-{:x}",
            rand::random::<u64>()
        ));
        let path = dir.join("preferences.json");
        let _ = std::fs::create_dir_all(&dir);

        SettingsManager::init(path.clone()).unwrap();
        SettingsManager::update_audio_devices(Some("mic-1".into()), Some("out-1".into())).unwrap();
        SettingsManager::update_audio_from_json(
            r#"{"noiseSuppression":false,"inputDeviceId":"clobber","outputDeviceId":null}"#,
        )
        .unwrap();

        let (ns, input, output) = SettingsManager::with(|s| {
            (
                s.audio.noise_suppression,
                s.audio.input_device_id.clone(),
                s.audio.output_device_id.clone(),
            )
        })
        .unwrap();
        assert!(!ns);
        assert_eq!(input.as_deref(), Some("mic-1"));
        assert_eq!(output.as_deref(), Some("out-1"));

        let reloaded = SettingsManager::load_and_migrate(&path).unwrap();
        assert!(!reloaded.audio.noise_suppression);
        assert_eq!(reloaded.audio.input_device_id.as_deref(), Some("mic-1"));
        assert_eq!(reloaded.audio.output_device_id.as_deref(), Some("out-1"));

        let _ = std::fs::remove_dir_all(&dir);
    }
}
