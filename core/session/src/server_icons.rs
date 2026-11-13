//! 服务器自定义图标的本地磁盘缓存。
//!
//! 缓存文件存放在 `store_path` 同级的 `server-icons/` 目录：
//! - `index.json` 记录 `server_id -> icon_id`
//! - `<sha1(server_id)>.bin` 保存原始图标字节，避免 `host:port` 中的冒号触发 Windows 路径限制。

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use sha1::{Digest, Sha1};

const MAX_ICON_BYTES: usize = 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CachedServerIcon {
    pub(crate) icon_id: u32,
    pub(crate) bytes: Vec<u8>,
}

fn cache_dir(store_path: &Path) -> PathBuf {
    store_path.with_file_name("server-icons")
}

fn index_path(dir: &Path) -> PathBuf {
    dir.join("index.json")
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

fn icon_file_path(dir: &Path, server_id: &str) -> PathBuf {
    dir.join(format!("{}.bin", server_key(server_id)))
}

fn write_atomic(path: &Path, data: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|err| format!("创建服务器图标缓存目录失败: {err}"))?;
    }
    let file_name = path
        .file_name()
        .ok_or_else(|| "服务器图标缓存路径缺少文件名".to_string())?;
    let mut temp_name = file_name.to_os_string();
    temp_name.push(format!(".{:032x}.tmp", rand::random::<u128>()));
    let temp = path.with_file_name(temp_name);

    {
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .map_err(|err| format!("创建临时缓存文件失败: {err}"))?;
        file.write_all(data)
            .map_err(|err| format!("写入缓存文件失败: {err}"))?;
        file.sync_all()
            .map_err(|err| format!("同步缓存文件失败: {err}"))?;
    }

    std::fs::rename(&temp, path).map_err(|err| format!("替换缓存文件失败: {err}"))?;
    Ok(())
}

fn write_index(dir: &Path, cache: &HashMap<String, CachedServerIcon>) -> Result<(), String> {
    let index: HashMap<&str, u32> = cache
        .iter()
        .map(|(server_id, entry)| (server_id.as_str(), entry.icon_id))
        .collect();
    let encoded = serde_json::to_vec_pretty(&index)
        .map_err(|err| format!("序列化服务器图标索引失败: {err}"))?;
    write_atomic(&index_path(dir), &encoded)
}

/// 启动时加载本地缓存的服务器图标，并顺便清理已删除服务器或损坏条目对应的残留文件。
pub(crate) fn load(
    store_path: &Path,
    active_server_ids: &[&str],
) -> HashMap<String, CachedServerIcon> {
    let dir = cache_dir(store_path);
    let idx_path = index_path(&dir);
    let raw = match std::fs::read_to_string(&idx_path) {
        Ok(raw) => raw,
        Err(_) => return HashMap::new(),
    };
    let parsed: HashMap<String, u32> = match serde_json::from_str(&raw) {
        Ok(map) => map,
        Err(_) => return HashMap::new(),
    };

    let active: HashSet<&str> = active_server_ids.iter().copied().collect();
    let mut cache = HashMap::new();
    let mut dirty = false;

    for (server_id, icon_id) in parsed {
        if icon_id == 0 || !active.contains(server_id.as_str()) {
            let _ = std::fs::remove_file(icon_file_path(&dir, &server_id));
            dirty = true;
            continue;
        }
        let bin_path = icon_file_path(&dir, &server_id);
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
        let _ = write_index(&dir, &cache);
    }

    cache
}

pub(crate) fn save(
    store_path: &Path,
    cache: &mut HashMap<String, CachedServerIcon>,
    server_id: &str,
    icon_id: u32,
    bytes: Vec<u8>,
) -> Result<(), String> {
    if icon_id == 0 || bytes.is_empty() || bytes.len() > MAX_ICON_BYTES {
        return Err("无效的服务器图标缓存数据".to_string());
    }
    let dir = cache_dir(store_path);
    write_atomic(&icon_file_path(&dir, server_id), &bytes)?;
    cache.insert(server_id.to_string(), CachedServerIcon { icon_id, bytes });
    write_index(&dir, cache)
}

pub(crate) fn remove(
    store_path: &Path,
    cache: &mut HashMap<String, CachedServerIcon>,
    server_id: &str,
) -> Result<bool, String> {
    let removed = cache.remove(server_id).is_some();
    let dir = cache_dir(store_path);
    let bin_path = icon_file_path(&dir, server_id);
    if bin_path.exists() {
        let _ = std::fs::remove_file(&bin_path);
    }
    if removed {
        write_index(&dir, cache)?;
    }
    Ok(removed)
}

pub(crate) fn move_entry(
    store_path: &Path,
    cache: &mut HashMap<String, CachedServerIcon>,
    old_id: &str,
    new_id: &str,
) -> Result<Option<CachedServerIcon>, String> {
    if old_id == new_id {
        return Ok(None);
    }
    let Some(entry) = cache.remove(old_id) else {
        return Ok(None);
    };
    let dir = cache_dir(store_path);
    write_atomic(&icon_file_path(&dir, new_id), &entry.bytes)?;
    let _ = std::fs::remove_file(icon_file_path(&dir, old_id));
    cache.insert(new_id.to_string(), entry.clone());
    write_index(&dir, cache)?;
    Ok(Some(entry))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_store_path(label: &str) -> (PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(format!(
            "flspeak-server-icons-{label}-{:x}",
            rand::random::<u64>()
        ));
        let _ = std::fs::create_dir_all(&dir);
        (dir.clone(), dir.join("preferences.json"))
    }

    #[test]
    fn saves_loads_moves_and_removes_cached_icons() {
        let (dir, store_path) = temp_store_path("roundtrip");
        let mut cache = HashMap::new();
        save(
            &store_path,
            &mut cache,
            "ts.example.com:9987",
            42,
            vec![1, 2, 3, 4],
        )
        .unwrap();

        let loaded = load(&store_path, &["ts.example.com:9987"]);
        assert_eq!(
            loaded.get("ts.example.com:9987"),
            Some(&CachedServerIcon {
                icon_id: 42,
                bytes: vec![1, 2, 3, 4],
            })
        );

        let moved = move_entry(
            &store_path,
            &mut cache,
            "ts.example.com:9987",
            "new.example.com:9988",
        )
        .unwrap();
        assert!(moved.is_some());
        let reloaded = load(&store_path, &["new.example.com:9988"]);
        assert!(!reloaded.contains_key("ts.example.com:9987"));
        assert_eq!(
            reloaded.get("new.example.com:9988").map(|e| e.icon_id),
            Some(42)
        );

        let mut loaded_mut = reloaded;
        assert!(remove(&store_path, &mut loaded_mut, "new.example.com:9988").unwrap());
        assert!(load(&store_path, &["new.example.com:9988"]).is_empty());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn load_prunes_orphans_from_removed_servers() {
        let (dir, store_path) = temp_store_path("prune");
        let mut cache = HashMap::new();
        save(&store_path, &mut cache, "keep.example:9987", 10, vec![9, 8]).unwrap();
        save(&store_path, &mut cache, "gone.example:9987", 11, vec![7, 6]).unwrap();

        let loaded = load(&store_path, &["keep.example:9987"]);
        assert_eq!(loaded.len(), 1);
        assert!(loaded.contains_key("keep.example:9987"));
        assert!(!icon_file_path(&cache_dir(&store_path), "gone.example:9987").exists());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
