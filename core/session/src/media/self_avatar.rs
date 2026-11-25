//! 本机自头像快照：单文件存储，读写与清理都由 `AvatarDiskQueue` 串行执行。

use std::io::ErrorKind;
use std::path::{Path, PathBuf};

use super::avatars::{MAX_AVATAR_BYTES, is_supported_image};
use super::cache;

const FILE_NAME: &str = "identity-avatar.bin";

fn path(store_path: &Path) -> PathBuf {
    store_path.with_file_name(FILE_NAME)
}

/// 读取并校验快照；缺失、损坏或超限时只记录警告并返回 `None`。
pub(crate) fn load(store_path: &Path) -> Option<Vec<u8>> {
    if store_path.as_os_str().is_empty() {
        return None;
    }
    let path = path(store_path);
    let metadata = match std::fs::metadata(&path) {
        Ok(metadata) => metadata,
        Err(_) => return None,
    };
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > MAX_AVATAR_BYTES as u64 {
        tracing::warn!(
            target: "session",
            path = %path.display(),
            bytes = metadata.len(),
            "ignoring self avatar snapshot with an invalid size"
        );
        return None;
    }
    let bytes = match std::fs::read(&path) {
        Ok(bytes) => bytes,
        Err(error) => {
            tracing::warn!(
                target: "session",
                path = %path.display(),
                error = %error,
                "failed to read self avatar snapshot"
            );
            return None;
        }
    };
    if bytes.len() > MAX_AVATAR_BYTES || !is_supported_image(&bytes) {
        tracing::warn!(
            target: "session",
            path = %path.display(),
            bytes = bytes.len(),
            "ignoring self avatar snapshot with an unsupported format"
        );
        return None;
    }
    Some(bytes)
}

pub(crate) fn save(store_path: &Path, bytes: &[u8]) -> Result<(), String> {
    if store_path.as_os_str().is_empty() {
        return Err("self avatar snapshot store path is empty".to_string());
    }
    if bytes.is_empty() || bytes.len() > MAX_AVATAR_BYTES || !is_supported_image(bytes) {
        return Err("invalid self avatar snapshot".to_string());
    }
    cache::write_atomic(&path(store_path), bytes, false, "self avatar snapshot")
}

pub(super) fn clear(store_path: &Path) -> Result<(), String> {
    if store_path.as_os_str().is_empty() {
        return Ok(());
    }
    match std::fs::remove_file(path(store_path)) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
        Err(error) => Err(format!(
            "failed to remove the self avatar snapshot: {error}"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PNG_HEADER: [u8; 16] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
        0x52,
    ];

    fn temp_store_path(label: &str) -> (PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(format!(
            "flspeak-self-avatar-{label}-{:x}",
            rand::random::<u64>()
        ));
        let _ = std::fs::create_dir_all(&dir);
        (dir.clone(), dir.join("preferences.json"))
    }

    #[test]
    fn saves_loads_and_clears_the_snapshot() {
        let (dir, store_path) = temp_store_path("roundtrip");
        assert_eq!(load(&store_path), None);

        save(&store_path, &PNG_HEADER).unwrap();
        assert_eq!(load(&store_path), Some(PNG_HEADER.to_vec()));

        clear(&store_path).unwrap();
        assert_eq!(load(&store_path), None);
        clear(&store_path).unwrap();

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn rejected_or_oversized_files_load_as_none_without_deleting_them() {
        let (dir, store_path) = temp_store_path("invalid");
        let path = path(&store_path);

        std::fs::write(&path, b"not an image").unwrap();
        assert_eq!(load(&store_path), None);
        assert!(path.exists());

        std::fs::write(&path, vec![0u8; MAX_AVATAR_BYTES + 1]).unwrap();
        assert_eq!(load(&store_path), None);
        assert!(path.exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn save_is_atomic_and_rejects_invalid_payloads() {
        let (dir, store_path) = temp_store_path("atomic");
        let path = path(&store_path);

        assert!(save(&store_path, b"not an image").is_err());
        assert!(!path.exists());

        save(&store_path, &PNG_HEADER).unwrap();
        let leftovers = std::fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .filter(|entry| entry.path().extension().and_then(|ext| ext.to_str()) == Some("tmp"))
            .count();
        assert_eq!(leftovers, 0);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn empty_store_path_is_a_safe_noop() {
        let empty = PathBuf::new();
        assert_eq!(load(&empty), None);
        assert!(save(&empty, &PNG_HEADER).is_err());
        clear(&empty).unwrap();
    }
}
