//! 服务器图标与频道自定义图标的统一本地磁盘缓存。
//!
//! 磁盘目录布局与 `store_path` 同级：
//! - 服务器图标存放在 `server-icons/`：`index.json` 记录 `server_id -> icon_id`，`<sha1(server_id)>.bin` 保存原始字节；
//! - 频道图标存放在 `channel-icons/<sha1(server_id)>/<icon_id>.bin`，按单服 256 个 / 16 MiB 的 LRU 预算淘汰；
//! - 两者写盘均通过 `cache::write_atomic` 执行 `sync_all` 原子替换。

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use super::cache::{self, MediaCacheSpec};

const MAX_ICON_BYTES: usize = 1024 * 1024;
const MAX_CHANNEL_ICONS_PER_SERVER: usize = 256;
const MAX_CHANNEL_ICON_BYTES_PER_SERVER: u64 = 16 * 1024 * 1024;

const CHANNEL_ICON_SPEC: MediaCacheSpec = MediaCacheSpec {
    dir_name: "channel-icons",
    max_entry_bytes: MAX_ICON_BYTES,
    max_files_per_server: MAX_CHANNEL_ICONS_PER_SERVER,
    max_bytes_per_server: MAX_CHANNEL_ICON_BYTES_PER_SERVER,
    sync_all: true,
};

#[derive(Debug, Clone, PartialEq, Eq)]
struct CachedServerIcon {
    icon_id: u32,
    bytes: Vec<u8>,
}

/// 管理单服服务器图标（内存索引 + `server-icons/`）与频道图标（`channel-icons/`）的磁盘缓存。
#[derive(Debug, Default)]
pub(crate) struct IconCache {
    server_icons: HashMap<String, CachedServerIcon>,
}

fn server_icons_dir(store_path: &Path) -> PathBuf {
    store_path.with_file_name("server-icons")
}

fn server_icon_index_path(dir: &Path) -> PathBuf {
    dir.join("index.json")
}

fn server_icon_file_path(dir: &Path, server_id: &str) -> PathBuf {
    dir.join(format!("{}.bin", cache::sha1_hex(server_id)))
}

fn channel_icon_file_name(icon_id: u32) -> String {
    format!("{icon_id}.bin")
}

fn write_server_icon_index(
    dir: &Path,
    server_icons: &HashMap<String, CachedServerIcon>,
) -> Result<(), String> {
    let index: HashMap<&str, u32> = server_icons
        .iter()
        .map(|(server_id, entry)| (server_id.as_str(), entry.icon_id))
        .collect();
    let encoded = serde_json::to_vec_pretty(&index)
        .map_err(|err| format!("failed to serialize the server icon index: {err}"))?;
    cache::write_atomic(&server_icon_index_path(dir), &encoded, true, "server icon")
}

fn load_server_icons(
    store_path: &Path,
    active_server_ids: &[&str],
) -> HashMap<String, CachedServerIcon> {
    if store_path.as_os_str().is_empty() {
        return HashMap::new();
    }
    let dir = server_icons_dir(store_path);
    let idx_path = server_icon_index_path(&dir);
    let Ok(raw) = std::fs::read_to_string(&idx_path) else {
        return HashMap::new();
    };
    let Ok(parsed) = serde_json::from_str::<HashMap<String, u32>>(&raw) else {
        return HashMap::new();
    };

    let active: HashSet<&str> = active_server_ids.iter().copied().collect();
    let mut cache = HashMap::new();
    let mut dirty = false;

    for (server_id, icon_id) in parsed {
        if icon_id == 0 || !active.contains(server_id.as_str()) {
            let _ = std::fs::remove_file(server_icon_file_path(&dir, &server_id));
            dirty = true;
            continue;
        }
        let bin_path = server_icon_file_path(&dir, &server_id);
        match std::fs::read(&bin_path) {
            Ok(bytes) if !bytes.is_empty() && bytes.len() <= MAX_ICON_BYTES => {
                cache.insert(server_id, CachedServerIcon { icon_id, bytes });
            }
            _ => {
                let _ = std::fs::remove_file(&bin_path);
                dirty = true;
            }
        }
    }

    if dirty {
        let _ = write_server_icon_index(&dir, &cache);
    }

    cache
}

impl IconCache {
    /// 启动时加载本地服务器图标索引并清理未注册服务器的频道图标目录。
    pub(crate) fn load(store_path: &Path, active_server_ids: &[&str]) -> Self {
        let server_icons = load_server_icons(store_path, active_server_ids);
        cache::prune_orphans(store_path, CHANNEL_ICON_SPEC, active_server_ids);
        Self { server_icons }
    }

    pub(crate) fn list_server_icons(&self) -> Vec<crate::ServerIconView> {
        self.server_icons
            .iter()
            .map(|(server_id, entry)| crate::ServerIconView {
                server_id: server_id.clone(),
                bytes: entry.bytes.clone(),
            })
            .collect()
    }

    pub(crate) fn has_server_icon(&self, server_id: &str, icon_id: u32) -> bool {
        self.server_icons
            .get(server_id)
            .is_some_and(|entry| entry.icon_id == icon_id)
    }

    pub(crate) fn save_server_icon(
        &mut self,
        store_path: &Path,
        server_id: &str,
        icon_id: u32,
        bytes: Vec<u8>,
    ) -> Result<(), String> {
        if store_path.as_os_str().is_empty() {
            return Err("server icon cache store path is empty".to_string());
        }
        if icon_id == 0 || bytes.is_empty() || bytes.len() > MAX_ICON_BYTES {
            return Err("invalid server icon cache data".to_string());
        }
        let dir = server_icons_dir(store_path);
        cache::write_atomic(
            &server_icon_file_path(&dir, server_id),
            &bytes,
            true,
            "server icon",
        )?;
        self.server_icons
            .insert(server_id.to_string(), CachedServerIcon { icon_id, bytes });
        write_server_icon_index(&dir, &self.server_icons)
    }

    /// 仅清理指定服务器的服务器图标（用于服务端通告 `icon_id == 0`），不删除频道图标缓存。
    pub(crate) fn clear_server_icon(
        &mut self,
        store_path: &Path,
        server_id: &str,
    ) -> Result<bool, String> {
        let removed = self.server_icons.remove(server_id).is_some();
        if !store_path.as_os_str().is_empty() {
            let dir = server_icons_dir(store_path);
            let bin_path = server_icon_file_path(&dir, server_id);
            if bin_path.exists() {
                let _ = std::fs::remove_file(&bin_path);
            }
            if removed {
                write_server_icon_index(&dir, &self.server_icons)?;
            }
        }
        Ok(removed)
    }

    pub(crate) fn remove_server(
        &mut self,
        store_path: &Path,
        server_id: &str,
    ) -> Result<bool, String> {
        cache::remove_server(store_path, CHANNEL_ICON_SPEC, server_id);
        self.clear_server_icon(store_path, server_id)
    }

    pub(crate) fn move_server(
        &mut self,
        store_path: &Path,
        old_id: &str,
        new_id: &str,
    ) -> Result<Option<Vec<u8>>, String> {
        if old_id == new_id {
            return Ok(None);
        }
        cache::move_server(store_path, CHANNEL_ICON_SPEC, old_id, new_id);
        let Some(entry) = self.server_icons.remove(old_id) else {
            return Ok(None);
        };
        let bytes = entry.bytes.clone();
        if !store_path.as_os_str().is_empty() {
            let dir = server_icons_dir(store_path);
            cache::write_atomic(
                &server_icon_file_path(&dir, new_id),
                &entry.bytes,
                true,
                "server icon",
            )?;
            let _ = std::fs::remove_file(server_icon_file_path(&dir, old_id));
            self.server_icons.insert(new_id.to_string(), entry);
            write_server_icon_index(&dir, &self.server_icons)?;
        } else {
            self.server_icons.insert(new_id.to_string(), entry);
        }
        Ok(Some(bytes))
    }

    pub(crate) fn load_channel_icon(
        &self,
        store_path: &Path,
        server_id: &str,
        icon_id: u32,
    ) -> Option<Vec<u8>> {
        if icon_id == 0 {
            return None;
        }
        cache::load_hit(
            store_path,
            CHANNEL_ICON_SPEC,
            server_id,
            &channel_icon_file_name(icon_id),
        )
    }

    pub(crate) fn save_channel_icon(
        &self,
        store_path: &Path,
        server_id: &str,
        icon_id: u32,
        bytes: &[u8],
    ) -> Result<(), String> {
        if icon_id == 0 {
            return Err("invalid channel icon cache data".to_string());
        }
        cache::save(
            store_path,
            CHANNEL_ICON_SPEC,
            server_id,
            &channel_icon_file_name(icon_id),
            bytes,
        )
    }

    #[cfg(test)]
    pub(crate) fn server_icon_id(&self, server_id: &str) -> Option<u32> {
        self.server_icons.get(server_id).map(|entry| entry.icon_id)
    }

    #[cfg(test)]
    pub(crate) fn is_empty(&self) -> bool {
        self.server_icons.is_empty()
    }

    #[cfg(test)]
    fn save_channel_icon_with_limits(
        &self,
        store_path: &Path,
        server_id: &str,
        icon_id: u32,
        bytes: &[u8],
        max_files: usize,
        max_bytes: u64,
    ) -> Result<(), String> {
        if icon_id == 0 {
            return Err("invalid channel icon cache data".to_string());
        }
        cache::save_with_limits(
            store_path,
            CHANNEL_ICON_SPEC,
            server_id,
            &channel_icon_file_name(icon_id),
            bytes,
            max_files,
            max_bytes,
        )
    }
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, SystemTime};

    use super::*;

    fn channel_server_dir(store_path: &Path, server_id: &str) -> PathBuf {
        cache::server_dir(store_path, CHANNEL_ICON_SPEC, server_id)
    }

    fn channel_icon_path(dir: &Path, icon_id: u32) -> PathBuf {
        dir.join(channel_icon_file_name(icon_id))
    }

    fn temp_store_path(label: &str) -> (PathBuf, PathBuf) {
        let dir =
            std::env::temp_dir().join(format!("flspeak-icons-{label}-{:x}", rand::random::<u64>()));
        let _ = std::fs::create_dir_all(&dir);
        (dir.clone(), dir.join("preferences.json"))
    }

    #[test]
    fn saves_loads_moves_and_removes_cached_server_icons() {
        let (dir, store_path) = temp_store_path("server-roundtrip");
        let mut icons = IconCache::default();
        icons
            .save_server_icon(&store_path, "ts.example.com:9987", 42, vec![1, 2, 3, 4])
            .unwrap();

        let loaded = IconCache::load(&store_path, &["ts.example.com:9987"]);
        assert!(loaded.has_server_icon("ts.example.com:9987", 42));
        assert_eq!(
            loaded.list_server_icons(),
            vec![crate::ServerIconView {
                server_id: "ts.example.com:9987".to_string(),
                bytes: vec![1, 2, 3, 4],
            }]
        );

        let moved = icons
            .move_server(&store_path, "ts.example.com:9987", "new.example.com:9988")
            .unwrap();
        assert_eq!(moved, Some(vec![1, 2, 3, 4]));
        let mut reloaded = IconCache::load(&store_path, &["new.example.com:9988"]);
        assert_eq!(reloaded.server_icon_id("ts.example.com:9987"), None);
        assert_eq!(reloaded.server_icon_id("new.example.com:9988"), Some(42));

        assert!(
            reloaded
                .remove_server(&store_path, "new.example.com:9988")
                .unwrap()
        );
        assert!(IconCache::load(&store_path, &["new.example.com:9988"]).is_empty());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn load_prunes_orphans_from_removed_servers() {
        let (dir, store_path) = temp_store_path("prune");
        let mut icons = IconCache::default();
        icons
            .save_server_icon(&store_path, "keep.example:9987", 10, vec![9, 8])
            .unwrap();
        icons
            .save_server_icon(&store_path, "gone.example:9987", 11, vec![7, 6])
            .unwrap();
        icons
            .save_channel_icon(&store_path, "keep.example:9987", 1, &[1, 2])
            .unwrap();
        icons
            .save_channel_icon(&store_path, "gone.example:9987", 2, &[3, 4])
            .unwrap();

        let loaded = IconCache::load(&store_path, &["keep.example:9987"]);
        assert_eq!(loaded.server_icon_id("keep.example:9987"), Some(10));
        assert_eq!(loaded.server_icon_id("gone.example:9987"), None);
        assert!(
            !server_icon_file_path(&server_icons_dir(&store_path), "gone.example:9987").exists()
        );
        assert!(channel_server_dir(&store_path, "keep.example:9987").exists());
        assert!(!channel_server_dir(&store_path, "gone.example:9987").exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn saves_loads_moves_and_removes_server_channel_icons() {
        let (dir, store_path) = temp_store_path("channel-roundtrip");
        let mut icons = IconCache::default();
        icons
            .save_channel_icon(&store_path, "a.example:9987", 101, &[1, 2, 3])
            .unwrap();
        icons
            .save_channel_icon(&store_path, "b.example:9987", 101, &[9, 8, 7])
            .unwrap();

        assert_eq!(
            icons.load_channel_icon(&store_path, "a.example:9987", 101),
            Some(vec![1, 2, 3])
        );
        assert_eq!(
            icons.load_channel_icon(&store_path, "b.example:9987", 101),
            Some(vec![9, 8, 7])
        );
        assert_eq!(
            icons.load_channel_icon(&store_path, "a.example:9987", 999),
            None
        );

        // 同 ID 移动是空操作
        assert_eq!(
            icons
                .move_server(&store_path, "a.example:9987", "a.example:9987")
                .unwrap(),
            None
        );
        assert_eq!(
            icons.load_channel_icon(&store_path, "a.example:9987", 101),
            Some(vec![1, 2, 3])
        );

        // 即使没有服务器图标记录，move_server 仍会迁移频道图标目录；
        // 目标目录已存在时先删再重命名，不保留目标原有残留文件
        icons
            .save_channel_icon(&store_path, "target.example:9987", 202, &[4, 4])
            .unwrap();
        assert_eq!(
            icons
                .move_server(&store_path, "a.example:9987", "target.example:9987")
                .unwrap(),
            None
        );
        assert_eq!(
            icons.load_channel_icon(&store_path, "a.example:9987", 101),
            None
        );
        assert_eq!(
            icons.load_channel_icon(&store_path, "target.example:9987", 101),
            Some(vec![1, 2, 3])
        );
        assert_eq!(
            icons.load_channel_icon(&store_path, "target.example:9987", 202),
            None
        );

        // clear_server_icon 只清理服务器图标，保留频道图标；remove_server 两者都清理
        icons
            .save_server_icon(&store_path, "target.example:9987", 77, vec![5, 5])
            .unwrap();
        assert!(
            icons
                .clear_server_icon(&store_path, "target.example:9987")
                .unwrap()
        );
        assert_eq!(
            icons.load_channel_icon(&store_path, "target.example:9987", 101),
            Some(vec![1, 2, 3])
        );
        assert!(
            !icons
                .remove_server(&store_path, "target.example:9987")
                .unwrap()
        );
        assert!(!channel_server_dir(&store_path, "target.example:9987").exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn evicts_oldest_icons_when_count_or_bytes_exceed_limit() {
        let (dir, store_path) = temp_store_path("channel-lru");
        let icons = IconCache::default();
        let s_dir = channel_server_dir(&store_path, "srv:9987");
        let base = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000);

        icons
            .save_channel_icon_with_limits(&store_path, "srv:9987", 1, &[1; 4], 10, 100)
            .unwrap();
        icons
            .save_channel_icon_with_limits(&store_path, "srv:9987", 2, &[2; 4], 10, 100)
            .unwrap();
        icons
            .save_channel_icon_with_limits(&store_path, "srv:9987", 3, &[3; 4], 10, 100)
            .unwrap();

        for (id, offset) in [(1, 10u64), (2, 20), (3, 30)] {
            let file = std::fs::OpenOptions::new()
                .write(true)
                .open(channel_icon_path(&s_dir, id))
                .unwrap();
            file.set_modified(base + Duration::from_secs(offset))
                .unwrap();
        }

        // 超出数量上限 (max_files = 3)：写入 4 后共 4 个，应淘汰最旧的 1 号
        icons
            .save_channel_icon_with_limits(&store_path, "srv:9987", 4, &[4; 4], 3, 100)
            .unwrap();
        assert_eq!(icons.load_channel_icon(&store_path, "srv:9987", 1), None);
        assert!(channel_icon_path(&s_dir, 2).exists());
        assert!(channel_icon_path(&s_dir, 3).exists());
        assert!(channel_icon_path(&s_dir, 4).exists());

        // 把 2 号与 4 号重新设为更旧于 3 号，并让 2 号触发一次 load_hit 刷新 mtime
        for (id, offset) in [(2, 10u64), (3, 20), (4, 30)] {
            let file = std::fs::OpenOptions::new()
                .write(true)
                .open(channel_icon_path(&s_dir, id))
                .unwrap();
            file.set_modified(base + Duration::from_secs(offset))
                .unwrap();
        }
        assert_eq!(
            icons.load_channel_icon(&store_path, "srv:9987", 2),
            Some(vec![2; 4])
        );

        // 超出字节上限 (max_bytes = 8，每个 4 字节)：写入 5（mtime 最新）后共 4 个 16 字节；
        // 按 mtime 最旧的 3、4 应被淘汰，命中刷新过的 2 与新写入的 5 保留
        icons
            .save_channel_icon_with_limits(&store_path, "srv:9987", 5, &[5; 4], 10, 8)
            .unwrap();
        assert!(!channel_icon_path(&s_dir, 3).exists());
        assert!(!channel_icon_path(&s_dir, 4).exists());
        assert_eq!(
            icons.load_channel_icon(&store_path, "srv:9987", 2),
            Some(vec![2; 4])
        );
        assert_eq!(
            icons.load_channel_icon(&store_path, "srv:9987", 5),
            Some(vec![5; 4])
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn empty_store_path_is_safe_and_rejects_server_icon_save() {
        let empty = PathBuf::new();
        let mut icons = IconCache::load(&empty, &["srv:9987"]);
        assert!(icons.is_empty());
        assert!(
            icons
                .save_server_icon(&empty, "srv:9987", 1, vec![1])
                .is_err()
        );
        assert!(!icons.clear_server_icon(&empty, "srv:9987").unwrap());
        assert!(!icons.remove_server(&empty, "srv:9987").unwrap());
    }
}
