//! 频道自定义图标的按需本地磁盘缓存。
//!
//! 缓存文件存放在 `store_path` 同级的 `channel-icons/<sha1(server_id)>/<icon_id>.bin`：
//! - 复用 `media_cache` 的按服隔离、原子写、命中刷新与单服数量/字节 LRU 淘汰；
//! - 保持单服 256 个 / 16 MiB 预算与 `sync_all` 持久化语义不变。

use std::path::Path;

use crate::media_cache::{self, MediaCacheSpec};

const MAX_ICON_BYTES: usize = 1024 * 1024;
pub(crate) const MAX_ICONS_PER_SERVER: usize = 256;
pub(crate) const MAX_BYTES_PER_SERVER: u64 = 16 * 1024 * 1024;

const SPEC: MediaCacheSpec = MediaCacheSpec {
    dir_name: "channel-icons",
    max_entry_bytes: MAX_ICON_BYTES,
    max_files_per_server: MAX_ICONS_PER_SERVER,
    max_bytes_per_server: MAX_BYTES_PER_SERVER,
    sync_all: true,
};

fn icon_file_name(icon_id: u32) -> String {
    format!("{icon_id}.bin")
}

pub(crate) fn load_hit(store_path: &Path, server_id: &str, icon_id: u32) -> Option<Vec<u8>> {
    if icon_id == 0 {
        return None;
    }
    media_cache::load_hit(store_path, SPEC, server_id, &icon_file_name(icon_id))
}

pub(crate) fn save(
    store_path: &Path,
    server_id: &str,
    icon_id: u32,
    bytes: &[u8],
) -> Result<(), String> {
    if icon_id == 0 {
        return Err("invalid channel icon cache data".to_string());
    }
    media_cache::save(store_path, SPEC, server_id, &icon_file_name(icon_id), bytes)
}

#[cfg(test)]
pub(crate) fn save_with_limits(
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
    media_cache::save_with_limits(
        store_path,
        SPEC,
        server_id,
        &icon_file_name(icon_id),
        bytes,
        max_files,
        max_bytes,
    )
}

pub(crate) fn prune_orphans(store_path: &Path, active_server_ids: &[&str]) {
    media_cache::prune_orphans(store_path, SPEC, active_server_ids);
}

pub(crate) fn remove_server(store_path: &Path, server_id: &str) {
    media_cache::remove_server(store_path, SPEC, server_id);
}

pub(crate) fn move_server(store_path: &Path, old_id: &str, new_id: &str) {
    media_cache::move_server(store_path, SPEC, old_id, new_id);
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::time::{Duration, SystemTime};

    use super::*;

    fn server_dir(store_path: &Path, server_id: &str) -> PathBuf {
        media_cache::server_dir(store_path, SPEC, server_id)
    }

    fn icon_path(dir: &Path, icon_id: u32) -> PathBuf {
        dir.join(icon_file_name(icon_id))
    }

    fn temp_store_path(label: &str) -> (PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(format!(
            "flspeak-channel-icons-{label}-{:x}",
            rand::random::<u64>()
        ));
        let _ = std::fs::create_dir_all(&dir);
        (dir.clone(), dir.join("preferences.json"))
    }

    #[test]
    fn saves_loads_moves_and_removes_server_channel_icons() {
        let (dir, store_path) = temp_store_path("roundtrip");
        save(&store_path, "a.example:9987", 101, &[1, 2, 3]).unwrap();
        save(&store_path, "b.example:9987", 101, &[9, 8, 7]).unwrap();

        assert_eq!(
            load_hit(&store_path, "a.example:9987", 101),
            Some(vec![1, 2, 3])
        );
        assert_eq!(
            load_hit(&store_path, "b.example:9987", 101),
            Some(vec![9, 8, 7])
        );
        assert_eq!(load_hit(&store_path, "a.example:9987", 999), None);

        // 同 ID 移动是空操作
        move_server(&store_path, "a.example:9987", "a.example:9987");
        assert_eq!(
            load_hit(&store_path, "a.example:9987", 101),
            Some(vec![1, 2, 3])
        );

        // 目标目录已存在时先删再重命名，不保留目标原有残留文件
        save(&store_path, "target.example:9987", 202, &[4, 4]).unwrap();
        move_server(&store_path, "a.example:9987", "target.example:9987");
        assert_eq!(load_hit(&store_path, "a.example:9987", 101), None);
        assert_eq!(
            load_hit(&store_path, "target.example:9987", 101),
            Some(vec![1, 2, 3])
        );
        assert_eq!(load_hit(&store_path, "target.example:9987", 202), None);

        remove_server(&store_path, "target.example:9987");
        assert!(!server_dir(&store_path, "target.example:9987").exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn prune_orphans_removes_unregistered_server_dirs() {
        let (dir, store_path) = temp_store_path("prune");
        save(&store_path, "keep.example:9987", 1, &[1, 2]).unwrap();
        save(&store_path, "gone.example:9987", 2, &[3, 4]).unwrap();

        prune_orphans(&store_path, &["keep.example:9987"]);
        assert!(server_dir(&store_path, "keep.example:9987").exists());
        assert!(!server_dir(&store_path, "gone.example:9987").exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn evicts_oldest_icons_when_count_or_bytes_exceed_limit() {
        let (dir, store_path) = temp_store_path("lru");
        let s_dir = server_dir(&store_path, "srv:9987");
        let base = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000);

        save_with_limits(&store_path, "srv:9987", 1, &[1; 4], 10, 100).unwrap();
        save_with_limits(&store_path, "srv:9987", 2, &[2; 4], 10, 100).unwrap();
        save_with_limits(&store_path, "srv:9987", 3, &[3; 4], 10, 100).unwrap();

        for (id, offset) in [(1, 10u64), (2, 20), (3, 30)] {
            let file = std::fs::OpenOptions::new()
                .write(true)
                .open(icon_path(&s_dir, id))
                .unwrap();
            file.set_modified(base + Duration::from_secs(offset))
                .unwrap();
        }

        // 超出数量上限 (max_files = 3)：写入 4 后共 4 个，应淘汰最旧的 1 号
        save_with_limits(&store_path, "srv:9987", 4, &[4; 4], 3, 100).unwrap();
        assert_eq!(load_hit(&store_path, "srv:9987", 1), None);
        assert!(icon_path(&s_dir, 2).exists());
        assert!(icon_path(&s_dir, 3).exists());
        assert!(icon_path(&s_dir, 4).exists());

        // 把 2 号与 4 号重新设为更旧于 3 号，并让 2 号触发一次 load_hit 刷新 mtime
        for (id, offset) in [(2, 10u64), (3, 20), (4, 30)] {
            let file = std::fs::OpenOptions::new()
                .write(true)
                .open(icon_path(&s_dir, id))
                .unwrap();
            file.set_modified(base + Duration::from_secs(offset))
                .unwrap();
        }
        assert_eq!(load_hit(&store_path, "srv:9987", 2), Some(vec![2; 4]));

        // 超出字节上限 (max_bytes = 8，每个 4 字节)：写入 5（mtime 最新）后共 4 个 16 字节；
        // 按 mtime 最旧的 3、4 应被淘汰，命中刷新过的 2 与新写入的 5 保留
        save_with_limits(&store_path, "srv:9987", 5, &[5; 4], 10, 8).unwrap();
        assert!(!icon_path(&s_dir, 3).exists());
        assert!(!icon_path(&s_dir, 4).exists());
        assert_eq!(load_hit(&store_path, "srv:9987", 2), Some(vec![2; 4]));
        assert_eq!(load_hit(&store_path, "srv:9987", 5), Some(vec![5; 4]));

        let _ = std::fs::remove_dir_all(&dir);
    }
}
