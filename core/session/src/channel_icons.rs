//! 频道自定义图标的按需本地磁盘缓存。
//!
//! 缓存文件存放在 `store_path` 同级的 `channel-icons/<sha1(server_id)>/<icon_id>.bin`：
//! - 使用 `Sha1` 目录隔离不同服务器（避免同 `icon_id` 串图与 Windows 路径中的 `:` 限制）；
//! - 每次命中刷新文件修改时间，并在写入新图标时按单服数量/容量上限执行 LRU 淘汰。

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use sha1::{Digest, Sha1};

const MAX_ICON_BYTES: usize = 1024 * 1024;
pub(crate) const MAX_ICONS_PER_SERVER: usize = 256;
pub(crate) const MAX_BYTES_PER_SERVER: u64 = 16 * 1024 * 1024;

fn cache_root(store_path: &Path) -> PathBuf {
    store_path.with_file_name("channel-icons")
}

fn server_key(server_id: &str) -> String {
    let digest = Sha1::digest(server_id.as_bytes());
    let mut hex = String::with_capacity(digest.len() * 2);
    for byte in digest {
        use std::fmt::Write;
        let _ = write!(&mut hex, "{byte:02x}");
    }
    hex
}

fn server_dir(store_path: &Path, server_id: &str) -> PathBuf {
    cache_root(store_path).join(server_key(server_id))
}

fn icon_path(dir: &Path, icon_id: u32) -> PathBuf {
    dir.join(format!("{icon_id}.bin"))
}

pub(crate) fn load_hit(store_path: &Path, server_id: &str, icon_id: u32) -> Option<Vec<u8>> {
    if icon_id == 0 {
        return None;
    }
    let path = icon_path(&server_dir(store_path, server_id), icon_id);
    match std::fs::read(&path) {
        Ok(bytes) if !bytes.is_empty() && bytes.len() <= MAX_ICON_BYTES => {
            if let Ok(file) = std::fs::OpenOptions::new().write(true).open(&path) {
                let _ = file.set_modified(SystemTime::now());
            }
            Some(bytes)
        }
        Ok(_) => {
            let _ = std::fs::remove_file(&path);
            None
        }
        Err(_) => None,
    }
}

pub(crate) fn save(
    store_path: &Path,
    server_id: &str,
    icon_id: u32,
    bytes: &[u8],
) -> Result<(), String> {
    save_with_limits(
        store_path,
        server_id,
        icon_id,
        bytes,
        MAX_ICONS_PER_SERVER,
        MAX_BYTES_PER_SERVER,
    )
}

pub(crate) fn save_with_limits(
    store_path: &Path,
    server_id: &str,
    icon_id: u32,
    bytes: &[u8],
    max_files: usize,
    max_bytes: u64,
) -> Result<(), String> {
    if icon_id == 0 || bytes.is_empty() || bytes.len() > MAX_ICON_BYTES {
        return Err("无效的频道图标缓存数据".to_string());
    }
    let dir = server_dir(store_path, server_id);
    std::fs::create_dir_all(&dir).map_err(|err| format!("创建频道图标缓存目录失败: {err}"))?;

    let nanos = SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let temp = dir.join(format!(
        "{icon_id}.{nanos}.{:016x}.tmp",
        rand::random::<u64>()
    ));

    let write_outcome = (|| -> Result<(), String> {
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .map_err(|err| format!("创建频道图标临时文件失败: {err}"))?;
        file.write_all(bytes)
            .map_err(|err| format!("写入频道图标缓存失败: {err}"))?;
        file.sync_all()
            .map_err(|err| format!("同步频道图标缓存失败: {err}"))?;
        drop(file);
        std::fs::rename(&temp, icon_path(&dir, icon_id))
            .map_err(|err| format!("替换频道图标缓存失败: {err}"))?;
        Ok(())
    })();

    if let Err(err) = write_outcome {
        let _ = std::fs::remove_file(&temp);
        return Err(err);
    }

    evict_over_budget(&dir, max_files, max_bytes);
    Ok(())
}

struct CachedEntry {
    path: PathBuf,
    len: u64,
    modified: SystemTime,
}

fn evict_over_budget(dir: &Path, max_files: usize, max_bytes: u64) {
    let Ok(read_dir) = std::fs::read_dir(dir) else {
        return;
    };
    let mut entries = Vec::new();
    let mut total_bytes = 0u64;

    for item in read_dir.flatten() {
        let path = item.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("bin") {
            continue;
        }
        let Ok(meta) = item.metadata() else {
            continue;
        };
        if !meta.is_file() {
            continue;
        }
        let len = meta.len();
        let modified = meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
        total_bytes = total_bytes.saturating_add(len);
        entries.push(CachedEntry {
            path,
            len,
            modified,
        });
    }

    let mut count = entries.len();
    if count <= max_files && total_bytes <= max_bytes {
        return;
    }

    entries.sort_by(|a, b| {
        a.modified
            .cmp(&b.modified)
            .then_with(|| a.path.cmp(&b.path))
    });
    for entry in entries {
        if count <= max_files && total_bytes <= max_bytes {
            break;
        }
        if std::fs::remove_file(&entry.path).is_ok() {
            count -= 1;
            total_bytes = total_bytes.saturating_sub(entry.len);
        }
    }
}

pub(crate) fn prune_orphans(store_path: &Path, active_server_ids: &[&str]) {
    let root = cache_root(store_path);
    let Ok(read_dir) = std::fs::read_dir(&root) else {
        return;
    };
    let valid: HashSet<String> = active_server_ids.iter().map(|id| server_key(id)).collect();
    for item in read_dir.flatten() {
        let Some(name) = item.file_name().to_str().map(str::to_owned) else {
            let path = item.path();
            let _ = if path.is_dir() {
                std::fs::remove_dir_all(path)
            } else {
                std::fs::remove_file(path)
            };
            continue;
        };
        if !valid.contains(&name) {
            let path = item.path();
            let _ = if path.is_dir() {
                std::fs::remove_dir_all(path)
            } else {
                std::fs::remove_file(path)
            };
        }
    }
}

pub(crate) fn remove_server(store_path: &Path, server_id: &str) {
    let dir = server_dir(store_path, server_id);
    if dir.exists() {
        let _ = std::fs::remove_dir_all(dir);
    }
}

pub(crate) fn move_server(store_path: &Path, old_id: &str, new_id: &str) {
    if old_id == new_id {
        return;
    }
    let from = server_dir(store_path, old_id);
    if !from.exists() {
        return;
    }
    let to = server_dir(store_path, new_id);
    if to.exists() {
        let _ = std::fs::remove_dir_all(&to);
    }
    let _ = std::fs::rename(&from, &to);
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

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
