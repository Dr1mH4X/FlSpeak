//! 通用按服隔离的本地媒体磁盘缓存原语。
//!
//! 缓存文件存放在 `store_path` 同级的 `<dir_name>/<sha1(server_id)>/<file_name>`：
//! - 使用 `Sha1` 目录隔离不同服务器（规避同 ID 串图与 Windows 路径中的 `:` 限制）；
//! - 写盘采用临时文件 + 原子 `rename`，按规格决定是否调用 `sync_all`；
//! - 命中时刷新文件修改时间，写入后按单服数量与字节上限执行 LRU 淘汰。

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use sha1::{Digest, Sha1};

#[derive(Debug, Clone, Copy)]
pub(super) struct MediaCacheSpec {
    pub(super) dir_name: &'static str,
    pub(super) max_entry_bytes: usize,
    pub(super) max_files_per_server: usize,
    pub(super) max_bytes_per_server: u64,
    pub(super) sync_all: bool,
}

fn has_store_path(store_path: &Path) -> bool {
    !store_path.as_os_str().is_empty()
}

fn is_valid_file_name(file_name: &str) -> bool {
    !file_name.is_empty()
        && file_name != "."
        && file_name != ".."
        && !file_name.contains(['/', '\\', '\0'])
}

pub(super) fn sha1_hex(input: &str) -> String {
    let digest = Sha1::digest(input.as_bytes());
    let mut hex = String::with_capacity(digest.len() * 2);
    for byte in digest {
        use std::fmt::Write;
        let _ = write!(&mut hex, "{byte:02x}");
    }
    hex
}

fn cache_root(store_path: &Path, spec: MediaCacheSpec) -> PathBuf {
    store_path.with_file_name(spec.dir_name)
}

pub(super) fn server_dir(store_path: &Path, spec: MediaCacheSpec, server_id: &str) -> PathBuf {
    cache_root(store_path, spec).join(sha1_hex(server_id))
}

pub(super) fn load_hit(
    store_path: &Path,
    spec: MediaCacheSpec,
    server_id: &str,
    file_name: &str,
) -> Option<Vec<u8>> {
    if !has_store_path(store_path) || !is_valid_file_name(file_name) {
        return None;
    }
    let path = server_dir(store_path, spec, server_id).join(file_name);
    match std::fs::read(&path) {
        Ok(bytes) if !bytes.is_empty() && bytes.len() <= spec.max_entry_bytes => {
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

/// 写入临时文件后原子替换目标；`label` 只用于错误与日志文案。
pub(super) fn write_atomic(
    path: &Path,
    bytes: &[u8],
    sync_all: bool,
    label: &str,
) -> Result<(), String> {
    if let Some(parent) = path.parent()
        && !parent.as_os_str().is_empty()
    {
        std::fs::create_dir_all(parent)
            .map_err(|err| format!("failed to create the {label} directory: {err}"))?;
    }
    let file_name = path
        .file_name()
        .ok_or_else(|| format!("the {label} path is missing a file name"))?;
    let nanos = SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let mut temp_name = file_name.to_os_string();
    temp_name.push(format!(".{nanos}.{:016x}.tmp", rand::random::<u64>()));
    let temp = path.with_file_name(temp_name);

    let write_outcome = (|| -> Result<(), String> {
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .map_err(|err| format!("failed to create a temporary {label} file: {err}"))?;
        file.write_all(bytes)
            .map_err(|err| format!("failed to write the {label} cache: {err}"))?;
        if sync_all {
            file.sync_all()
                .map_err(|err| format!("failed to sync the {label} cache: {err}"))?;
        }
        drop(file);
        std::fs::rename(&temp, path)
            .map_err(|err| format!("failed to replace the {label} cache: {err}"))?;
        Ok(())
    })();

    if let Err(err) = write_outcome {
        let _ = std::fs::remove_file(&temp);
        return Err(err);
    }

    Ok(())
}

pub(super) fn save_atomic(
    store_path: &Path,
    spec: MediaCacheSpec,
    server_id: &str,
    file_name: &str,
    bytes: &[u8],
) -> Result<PathBuf, String> {
    if !has_store_path(store_path) {
        return Err("cache store path is empty".to_string());
    }
    if !is_valid_file_name(file_name) || bytes.is_empty() || bytes.len() > spec.max_entry_bytes {
        return Err(format!("invalid {} cache data", spec.dir_name));
    }
    let dir = server_dir(store_path, spec, server_id);
    write_atomic(&dir.join(file_name), bytes, spec.sync_all, spec.dir_name)?;
    Ok(dir)
}

pub(super) fn save(
    store_path: &Path,
    spec: MediaCacheSpec,
    server_id: &str,
    file_name: &str,
    bytes: &[u8],
) -> Result<(), String> {
    save_with_limits(
        store_path,
        spec,
        server_id,
        file_name,
        bytes,
        spec.max_files_per_server,
        spec.max_bytes_per_server,
    )
}

pub(super) fn save_with_limits(
    store_path: &Path,
    spec: MediaCacheSpec,
    server_id: &str,
    file_name: &str,
    bytes: &[u8],
    max_files: usize,
    max_bytes: u64,
) -> Result<(), String> {
    let dir = save_atomic(store_path, spec, server_id, file_name, bytes)?;
    evict_over_budget(&dir, max_files, max_bytes);
    Ok(())
}

struct CachedEntry {
    path: PathBuf,
    len: u64,
    modified: SystemTime,
}

pub(super) fn evict_over_budget(dir: &Path, max_files: usize, max_bytes: u64) {
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

pub(super) fn remove_files_matching(
    store_path: &Path,
    spec: MediaCacheSpec,
    server_id: &str,
    predicate: impl Fn(&str) -> bool,
) {
    if !has_store_path(store_path) {
        return;
    }
    let dir = server_dir(store_path, spec, server_id);
    let Ok(read_dir) = std::fs::read_dir(&dir) else {
        return;
    };
    for item in read_dir.flatten() {
        let Ok(meta) = item.metadata() else {
            continue;
        };
        if !meta.is_file() {
            continue;
        }
        let Some(name) = item.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        if predicate(&name) {
            let _ = std::fs::remove_file(item.path());
        }
    }
}

pub(super) fn prune_orphans(store_path: &Path, spec: MediaCacheSpec, active_server_ids: &[&str]) {
    if !has_store_path(store_path) {
        return;
    }
    let root = cache_root(store_path, spec);
    let Ok(read_dir) = std::fs::read_dir(&root) else {
        return;
    };
    let valid: HashSet<String> = active_server_ids.iter().map(|id| sha1_hex(id)).collect();
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

pub(super) fn remove_server(store_path: &Path, spec: MediaCacheSpec, server_id: &str) {
    if !has_store_path(store_path) {
        return;
    }
    let dir = server_dir(store_path, spec, server_id);
    if dir.exists() {
        let _ = std::fs::remove_dir_all(dir);
    }
}

pub(super) fn move_server(store_path: &Path, spec: MediaCacheSpec, old_id: &str, new_id: &str) {
    if !has_store_path(store_path) || old_id == new_id {
        return;
    }
    let from = server_dir(store_path, spec, old_id);
    if !from.exists() {
        return;
    }
    let to = server_dir(store_path, spec, new_id);
    if to.exists() {
        let _ = std::fs::remove_dir_all(&to);
    }
    let _ = std::fs::rename(&from, &to);
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

    const TEST_SPEC: MediaCacheSpec = MediaCacheSpec {
        dir_name: "test-media",
        max_entry_bytes: 16,
        max_files_per_server: 4,
        max_bytes_per_server: 32,
        sync_all: false,
    };

    const SYNC_SPEC: MediaCacheSpec = MediaCacheSpec {
        sync_all: true,
        ..TEST_SPEC
    };

    fn temp_store_path(label: &str) -> (PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(format!(
            "flspeak-media-cache-{label}-{:x}",
            rand::random::<u64>()
        ));
        let _ = std::fs::create_dir_all(&dir);
        (dir.clone(), dir.join("preferences.json"))
    }

    #[test]
    fn empty_store_path_is_a_safe_noop_and_rejects_save() {
        let empty = PathBuf::new();
        assert_eq!(load_hit(&empty, TEST_SPEC, "srv:9987", "a.bin"), None);
        assert!(save(&empty, TEST_SPEC, "srv:9987", "a.bin", &[1]).is_err());
        prune_orphans(&empty, TEST_SPEC, &["srv:9987"]);
        remove_server(&empty, TEST_SPEC, "srv:9987");
        move_server(&empty, TEST_SPEC, "a", "b");
        remove_files_matching(&empty, TEST_SPEC, "srv:9987", |_| true);
    }

    #[test]
    fn isolates_servers_supports_sync_and_unsynced_atomic_writes_and_cleans_corrupt_entries() {
        let (dir, store_path) = temp_store_path("roundtrip");
        save(&store_path, TEST_SPEC, "a.example:9987", "1.bin", &[1, 2]).unwrap();
        save(&store_path, SYNC_SPEC, "b.example:9987", "1.bin", &[9, 8]).unwrap();

        assert_eq!(
            load_hit(&store_path, TEST_SPEC, "a.example:9987", "1.bin"),
            Some(vec![1, 2])
        );
        assert_eq!(
            load_hit(&store_path, SYNC_SPEC, "b.example:9987", "1.bin"),
            Some(vec![9, 8])
        );
        assert_eq!(
            load_hit(&store_path, TEST_SPEC, "a.example:9987", "../evil.bin"),
            None
        );

        // 写入空文件或超上限文件后命中读取会自动清理损坏条目
        let s_dir = server_dir(&store_path, TEST_SPEC, "a.example:9987");
        std::fs::write(s_dir.join("empty.bin"), []).unwrap();
        std::fs::write(s_dir.join("huge.bin"), [7u8; 32]).unwrap();
        assert_eq!(
            load_hit(&store_path, TEST_SPEC, "a.example:9987", "empty.bin"),
            None
        );
        assert_eq!(
            load_hit(&store_path, TEST_SPEC, "a.example:9987", "huge.bin"),
            None
        );
        assert!(!s_dir.join("empty.bin").exists());
        assert!(!s_dir.join("huge.bin").exists());

        // 同目录下不应残留 .tmp 文件
        let has_tmp = std::fs::read_dir(&s_dir)
            .unwrap()
            .flatten()
            .any(|item| item.path().extension().and_then(|e| e.to_str()) == Some("tmp"));
        assert!(!has_tmp);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn evicts_oldest_by_count_and_bytes_and_refreshes_mtime_on_hit() {
        let (dir, store_path) = temp_store_path("lru");
        let s_dir = server_dir(&store_path, TEST_SPEC, "srv:9987");
        let base = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000);

        for name in ["a.bin", "b.bin", "c.bin"] {
            save_with_limits(&store_path, TEST_SPEC, "srv:9987", name, &[1; 4], 10, 100).unwrap();
        }
        for (name, offset) in [("a.bin", 10u64), ("b.bin", 20), ("c.bin", 30)] {
            let file = std::fs::OpenOptions::new()
                .write(true)
                .open(s_dir.join(name))
                .unwrap();
            file.set_modified(base + Duration::from_secs(offset))
                .unwrap();
        }

        // 超过数量上限 (3)：最旧的 a.bin 被淘汰
        save_with_limits(&store_path, TEST_SPEC, "srv:9987", "d.bin", &[2; 4], 3, 100).unwrap();
        assert!(!s_dir.join("a.bin").exists());
        assert!(s_dir.join("b.bin").exists());
        assert!(s_dir.join("c.bin").exists());
        assert!(s_dir.join("d.bin").exists());

        // 把 b.bin 设为最旧再命中刷新 mtime，写入超字节上限 (8 字节) 后应保留 b.bin 和新写入的 e.bin
        for (name, offset) in [("b.bin", 10u64), ("c.bin", 20), ("d.bin", 30)] {
            let file = std::fs::OpenOptions::new()
                .write(true)
                .open(s_dir.join(name))
                .unwrap();
            file.set_modified(base + Duration::from_secs(offset))
                .unwrap();
        }
        assert_eq!(
            load_hit(&store_path, TEST_SPEC, "srv:9987", "b.bin"),
            Some(vec![1; 4])
        );
        save_with_limits(&store_path, TEST_SPEC, "srv:9987", "e.bin", &[5; 4], 10, 8).unwrap();
        assert!(!s_dir.join("c.bin").exists());
        assert!(!s_dir.join("d.bin").exists());
        assert!(s_dir.join("b.bin").exists());
        assert!(s_dir.join("e.bin").exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn remove_files_matching_prunes_and_moves_servers() {
        let (dir, store_path) = temp_store_path("ops");
        save(&store_path, TEST_SPEC, "a.example:9987", "u1.h1.bin", &[1]).unwrap();
        save(&store_path, TEST_SPEC, "a.example:9987", "u2.h1.bin", &[2]).unwrap();
        save(&store_path, TEST_SPEC, "gone.example:9987", "u1.bin", &[3]).unwrap();

        remove_files_matching(&store_path, TEST_SPEC, "a.example:9987", |name| {
            name.starts_with("u1.")
        });
        assert_eq!(
            load_hit(&store_path, TEST_SPEC, "a.example:9987", "u1.h1.bin"),
            None
        );
        assert_eq!(
            load_hit(&store_path, TEST_SPEC, "a.example:9987", "u2.h1.bin"),
            Some(vec![2])
        );

        prune_orphans(&store_path, TEST_SPEC, &["a.example:9987"]);
        assert!(!server_dir(&store_path, TEST_SPEC, "gone.example:9987").exists());

        move_server(&store_path, TEST_SPEC, "a.example:9987", "b.example:9987");
        assert_eq!(
            load_hit(&store_path, TEST_SPEC, "b.example:9987", "u2.h1.bin"),
            Some(vec![2])
        );
        remove_server(&store_path, TEST_SPEC, "b.example:9987");
        assert!(!server_dir(&store_path, TEST_SPEC, "b.example:9987").exists());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
