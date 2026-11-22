//! 成员头像的按需本地磁盘缓存与阻塞线程 FIFO 调度队列。
//!
//! 缓存文件存放在 `store_path` 同级的 `avatars/<sha1(server_id)>/`：
//! - 已知合法 `avatar_hash` 时使用 `<sha1(uid)>.<avatar_hash>.bin`，写入新 hash 后删除同一 UID 的旧文件；
//! - 因权限等原因缺失或校验未通过时退回 `<sha1(uid)>.bin`；
//! - 单服预算 512 个 / 32 MiB（LRU），写盘跳过 `sync_all`，全部磁盘读写与删除均经阻塞工作线程串行执行。

use std::path::{Path, PathBuf};

use tokio::sync::mpsc;

use crate::media_cache::{self, MediaCacheSpec};

/// 头像字节大小安全上限。
pub const MAX_AVATAR_BYTES: usize = 1024 * 1024;
pub(crate) const MAX_AVATARS_PER_SERVER: usize = 512;
pub(crate) const MAX_BYTES_PER_SERVER: u64 = 32 * 1024 * 1024;
const MAX_AVATAR_HASH_LEN: usize = 64;

const SPEC: MediaCacheSpec = MediaCacheSpec {
    dir_name: "avatars",
    max_entry_bytes: MAX_AVATAR_BYTES,
    max_files_per_server: MAX_AVATARS_PER_SERVER,
    max_bytes_per_server: MAX_BYTES_PER_SERVER,
    sync_all: false,
};

/// 头像只接受 PNG / JPEG / GIF / WebP；服务器不校验内容，客户端负责这一步。
pub(crate) fn is_supported_image(bytes: &[u8]) -> bool {
    matches!(
        crate::images::image_format(bytes),
        Some(("image/png" | "image/jpeg" | "image/gif" | "image/webp", _))
    )
}

/// 先按客户端 1 MiB 安全上限，再按服务器 `i_client_max_avatar_filesize` 校验。
///
/// 服务器值 `0` 表示没有权限，正数表示字节上限，`-1` 表示不限；未知值放行，
/// 由服务器的 2565 兜底。
pub(crate) fn validate_size(len: usize, limit: Option<i32>) -> Result<(), crate::SessionError> {
    let hard_limit = MAX_AVATAR_BYTES as u64;
    match limit {
        Some(0) => Err(crate::SessionError::AvatarPermissionDenied),
        Some(value) if value > 0 => {
            let effective = (value as u64).min(hard_limit);
            if len as u64 > effective {
                Err(crate::SessionError::AvatarTooLarge {
                    max_bytes: Some(effective),
                })
            } else {
                Ok(())
            }
        }
        Some(_) | None => {
            if len as u64 > hard_limit {
                Err(crate::SessionError::AvatarTooLarge {
                    max_bytes: Some(hard_limit),
                })
            } else {
                Ok(())
            }
        }
    }
}

pub(crate) fn is_valid_avatar_hash(hash: &str) -> bool {
    !hash.is_empty()
        && hash.len() <= MAX_AVATAR_HASH_LEN
        && hash
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-')
}

pub(crate) fn file_name(uid: &str, avatar_hash: Option<&str>) -> String {
    let uid_key = media_cache::sha1_hex(uid);
    match avatar_hash.filter(|hash| is_valid_avatar_hash(hash)) {
        Some(hash) => format!("{uid_key}.{hash}.bin"),
        None => format!("{uid_key}.bin"),
    }
}

fn is_uid_avatar_file(name: &str, uid_key: &str) -> bool {
    let Some(rest) = name.strip_prefix(uid_key) else {
        return false;
    };
    if rest == ".bin" {
        return true;
    }
    let Some(middle) = rest
        .strip_prefix('.')
        .and_then(|value| value.strip_suffix(".bin"))
    else {
        return false;
    };
    !middle.is_empty()
}

fn is_same_cache_file(name: &str, keep_name: &str) -> bool {
    if cfg!(any(target_os = "macos", target_os = "windows")) {
        name.eq_ignore_ascii_case(keep_name)
    } else {
        name == keep_name
    }
}

pub(crate) fn load_hit(
    store_path: &Path,
    server_id: &str,
    uid: &str,
    avatar_hash: Option<&str>,
) -> Option<Vec<u8>> {
    if uid.is_empty() {
        return None;
    }
    media_cache::load_hit(store_path, SPEC, server_id, &file_name(uid, avatar_hash))
}

pub(crate) fn save(
    store_path: &Path,
    server_id: &str,
    uid: &str,
    avatar_hash: Option<&str>,
    bytes: &[u8],
) -> Result<(), String> {
    save_with_limits(
        store_path,
        server_id,
        uid,
        avatar_hash,
        bytes,
        SPEC.max_files_per_server,
        SPEC.max_bytes_per_server,
    )
}

pub(crate) fn save_with_limits(
    store_path: &Path,
    server_id: &str,
    uid: &str,
    avatar_hash: Option<&str>,
    bytes: &[u8],
    max_files: usize,
    max_bytes: u64,
) -> Result<(), String> {
    if uid.is_empty() {
        return Err("avatar UID must not be empty".to_string());
    }
    let uid_key = media_cache::sha1_hex(uid);
    let keep_name = file_name(uid, avatar_hash);
    let dir = media_cache::save_atomic(store_path, SPEC, server_id, &keep_name, bytes)?;
    // 先清理同 UID 的旧 hash / 回退文件再计入单服 LRU 预算，避免旧文件被算进总体积触发误淘汰。
    media_cache::remove_files_matching(store_path, SPEC, server_id, |name| {
        is_uid_avatar_file(name, &uid_key) && !is_same_cache_file(name, &keep_name)
    });
    media_cache::evict_over_budget(&dir, max_files, max_bytes);
    Ok(())
}

pub(crate) fn remove_uid(store_path: &Path, server_id: &str, uid: &str) {
    if uid.is_empty() {
        return;
    }
    let uid_key = media_cache::sha1_hex(uid);
    media_cache::remove_files_matching(store_path, SPEC, server_id, |name| {
        is_uid_avatar_file(name, &uid_key)
    });
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

enum AvatarDiskJob {
    LoadHit {
        store_path: PathBuf,
        server_id: String,
        uid: String,
        avatar_hash: Option<String>,
        on_done: Box<dyn FnOnce(Option<Vec<u8>>) + Send>,
    },
    Save {
        store_path: PathBuf,
        server_id: String,
        uid: String,
        avatar_hash: Option<String>,
        bytes: Vec<u8>,
    },
    RemoveUid {
        store_path: PathBuf,
        server_id: String,
        uid: String,
    },
    RemoveServer {
        store_path: PathBuf,
        server_id: String,
    },
    MoveServer {
        store_path: PathBuf,
        old_id: String,
        new_id: String,
    },
    PruneOrphans {
        store_path: PathBuf,
        active_server_ids: Vec<String>,
    },
    LoadSelfSnapshot {
        store_path: PathBuf,
        on_done: Box<dyn FnOnce(Option<Vec<u8>>) + Send>,
    },
    SaveSelfSnapshot {
        store_path: PathBuf,
        bytes: Vec<u8>,
    },
    ClearSelfSnapshot {
        store_path: PathBuf,
    },
    #[cfg(test)]
    Flush(tokio::sync::oneshot::Sender<()>),
}

impl AvatarDiskJob {
    fn run(self) {
        match self {
            AvatarDiskJob::LoadHit {
                store_path,
                server_id,
                uid,
                avatar_hash,
                on_done,
            } => {
                let bytes = load_hit(&store_path, &server_id, &uid, avatar_hash.as_deref());
                on_done(bytes);
            }
            AvatarDiskJob::Save {
                store_path,
                server_id,
                uid,
                avatar_hash,
                bytes,
            } => {
                if let Err(error) = save(
                    &store_path,
                    &server_id,
                    &uid,
                    avatar_hash.as_deref(),
                    &bytes,
                ) {
                    tracing::warn!(target: "session", uid = %uid, error = %error, "failed to save avatar disk cache");
                }
            }
            AvatarDiskJob::RemoveUid {
                store_path,
                server_id,
                uid,
            } => {
                remove_uid(&store_path, &server_id, &uid);
            }
            AvatarDiskJob::RemoveServer {
                store_path,
                server_id,
            } => {
                remove_server(&store_path, &server_id);
            }
            AvatarDiskJob::MoveServer {
                store_path,
                old_id,
                new_id,
            } => {
                move_server(&store_path, &old_id, &new_id);
            }
            AvatarDiskJob::PruneOrphans {
                store_path,
                active_server_ids,
            } => {
                let refs: Vec<&str> = active_server_ids.iter().map(String::as_str).collect();
                prune_orphans(&store_path, &refs);
            }
            AvatarDiskJob::LoadSelfSnapshot {
                store_path,
                on_done,
            } => {
                on_done(crate::self_avatar::load(&store_path));
            }
            AvatarDiskJob::SaveSelfSnapshot { store_path, bytes } => {
                if let Err(error) = crate::self_avatar::save(&store_path, &bytes) {
                    tracing::warn!(
                        target: "session",
                        error = %error,
                        "failed to save the self avatar snapshot"
                    );
                }
            }
            AvatarDiskJob::ClearSelfSnapshot { store_path } => {
                if let Err(error) = crate::self_avatar::clear(&store_path) {
                    tracing::warn!(
                        target: "session",
                        error = %error,
                        "failed to clear the self avatar snapshot"
                    );
                }
            }
            #[cfg(test)]
            AvatarDiskJob::Flush(reply) => {
                let _ = reply.send(());
            }
        }
    }
}

/// 单一 FIFO 阻塞工作线程队列：保证 `remove_uid` / `save` / `load_hit` 顺序严格一致，
/// 同时不让任何磁盘读写或目录清理阻塞 Actor 主线程。
pub(crate) struct AvatarDiskQueue {
    tx: Option<mpsc::UnboundedSender<AvatarDiskJob>>,
}

impl AvatarDiskQueue {
    pub(crate) fn new() -> Self {
        let Ok(handle) = tokio::runtime::Handle::try_current() else {
            return Self { tx: None };
        };
        let (tx, mut rx) = mpsc::unbounded_channel::<AvatarDiskJob>();
        handle.spawn_blocking(move || {
            while let Some(job) = rx.blocking_recv() {
                job.run();
            }
        });
        Self { tx: Some(tx) }
    }

    fn dispatch(&self, job: AvatarDiskJob) {
        if let Some(tx) = &self.tx {
            let _ = tx.send(job);
        } else {
            job.run();
        }
    }

    pub(crate) fn load_hit(
        &self,
        store_path: PathBuf,
        server_id: String,
        uid: String,
        avatar_hash: Option<String>,
        on_done: impl FnOnce(Option<Vec<u8>>) + Send + 'static,
    ) {
        self.dispatch(AvatarDiskJob::LoadHit {
            store_path,
            server_id,
            uid,
            avatar_hash,
            on_done: Box::new(on_done),
        });
    }

    pub(crate) fn save(
        &self,
        store_path: PathBuf,
        server_id: String,
        uid: String,
        avatar_hash: Option<String>,
        bytes: Vec<u8>,
    ) {
        self.dispatch(AvatarDiskJob::Save {
            store_path,
            server_id,
            uid,
            avatar_hash,
            bytes,
        });
    }

    pub(crate) fn remove_uid(&self, store_path: PathBuf, server_id: String, uid: String) {
        self.dispatch(AvatarDiskJob::RemoveUid {
            store_path,
            server_id,
            uid,
        });
    }

    pub(crate) fn remove_server(&self, store_path: PathBuf, server_id: String) {
        self.dispatch(AvatarDiskJob::RemoveServer {
            store_path,
            server_id,
        });
    }

    pub(crate) fn move_server(&self, store_path: PathBuf, old_id: String, new_id: String) {
        self.dispatch(AvatarDiskJob::MoveServer {
            store_path,
            old_id,
            new_id,
        });
    }

    pub(crate) fn prune_orphans(&self, store_path: PathBuf, active_server_ids: Vec<String>) {
        self.dispatch(AvatarDiskJob::PruneOrphans {
            store_path,
            active_server_ids,
        });
    }

    pub(crate) fn load_self_snapshot(
        &self,
        store_path: PathBuf,
        on_done: impl FnOnce(Option<Vec<u8>>) + Send + 'static,
    ) {
        self.dispatch(AvatarDiskJob::LoadSelfSnapshot {
            store_path,
            on_done: Box::new(on_done),
        });
    }

    pub(crate) fn save_self_snapshot(&self, store_path: PathBuf, bytes: Vec<u8>) {
        self.dispatch(AvatarDiskJob::SaveSelfSnapshot { store_path, bytes });
    }

    pub(crate) fn clear_self_snapshot(&self, store_path: PathBuf) {
        self.dispatch(AvatarDiskJob::ClearSelfSnapshot { store_path });
    }

    #[cfg(test)]
    pub(crate) async fn flush(&self) {
        let Some(tx) = &self.tx else {
            return;
        };
        let (reply, rx) = tokio::sync::oneshot::channel();
        if tx.send(AvatarDiskJob::Flush(reply)).is_ok() {
            let _ = rx.await;
        }
    }
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, SystemTime};

    use super::*;

    fn server_dir(store_path: &Path, server_id: &str) -> PathBuf {
        media_cache::server_dir(store_path, SPEC, server_id)
    }

    fn temp_store_path(label: &str) -> (PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(format!(
            "flspeak-avatars-{label}-{:x}",
            rand::random::<u64>()
        ));
        let _ = std::fs::create_dir_all(&dir);
        (dir.clone(), dir.join("preferences.json"))
    }

    #[test]
    fn avatar_format_accepts_supported_images_and_rejects_avif() {
        assert!(is_supported_image(b"\x89PNG\r\n\x1a\npayload"));
        assert!(is_supported_image(&[0xFF, 0xD8, 0xFF, 0xE0]));
        assert!(is_supported_image(b"GIF89a-payload"));
        assert!(is_supported_image(b"RIFF\x00\x00\x00\x00WEBPpayload"));
        assert!(!is_supported_image(b"\x00\x00\x00\x18ftypavifpayload"));
        assert!(!is_supported_image(b"not an image"));
        assert!(!is_supported_image(b""));
    }

    #[test]
    fn avatar_size_validation_combines_server_limit_with_client_cap() {
        assert!(validate_size(10, Some(10)).is_ok());
        assert!(validate_size(10, Some(11)).is_ok());
        assert!(validate_size(10, Some(-1)).is_ok());
        assert!(validate_size(10, None).is_ok());

        assert!(matches!(
            validate_size(10, Some(0)),
            Err(crate::SessionError::AvatarPermissionDenied)
        ));
        assert!(matches!(
            validate_size(MAX_AVATAR_BYTES + 1, Some(0)),
            Err(crate::SessionError::AvatarPermissionDenied)
        ));
        assert!(matches!(
            validate_size(10, Some(5)),
            Err(crate::SessionError::AvatarTooLarge { max_bytes: Some(5) })
        ));
        assert!(matches!(
            validate_size(MAX_AVATAR_BYTES + 1, Some(-1)),
            Err(crate::SessionError::AvatarTooLarge {
                max_bytes: Some(value)
            }) if value == MAX_AVATAR_BYTES as u64
        ));
        assert!(validate_size(MAX_AVATAR_BYTES + 1, None).is_err());
        assert!(validate_size(MAX_AVATAR_BYTES, Some(2 * 1024 * 1024)).is_ok());
    }

    #[test]
    fn validates_avatar_hash_and_builds_expected_cache_file_names() {
        let uid = "KqXRNkJgnzjGFbp0GTCPJN1ODJY=";
        let uid_key = media_cache::sha1_hex(uid);

        assert_eq!(
            file_name(uid, Some("deadbeef_01-AB")),
            format!("{uid_key}.deadbeef_01-AB.bin")
        );
        assert_eq!(file_name(uid, None), format!("{uid_key}.bin"));

        for invalid in [
            "",
            "../evil",
            "a/b",
            r"a\b",
            "a.b",
            "has space",
            &"a".repeat(65),
        ] {
            assert!(!is_valid_avatar_hash(invalid), "should reject {invalid:?}");
            assert_eq!(file_name(uid, Some(invalid)), format!("{uid_key}.bin"));
        }
    }

    #[test]
    fn saves_hashed_avatar_cleans_old_hashes_and_preserves_other_uids() {
        let (dir, store_path) = temp_store_path("hash-cleanup");
        let s_dir = server_dir(&store_path, "srv:9987");
        let uid_a = "KqXRNkJgnzjGFbp0GTCPJN1ODJY=";
        let uid_b = "HYqkXu981igdjfxleVv2aYOmdkdumh2pFrkTSLRHG5k=";

        // 无 hash 时写入回退路径，并保留另一个 UID 的文件
        save(&store_path, "srv:9987", uid_a, None, &[1, 2]).unwrap();
        save(&store_path, "srv:9987", uid_b, Some("otherhash"), &[9, 9]).unwrap();
        assert_eq!(
            load_hit(&store_path, "srv:9987", uid_a, None),
            Some(vec![1, 2])
        );

        // 写入带 hash 的新头像：删除回退路径，仅保留新 hash 文件
        save(&store_path, "srv:9987", uid_a, Some("hash_v1"), &[3, 4]).unwrap();
        assert!(!s_dir.join(file_name(uid_a, None)).exists());
        assert_eq!(
            load_hit(&store_path, "srv:9987", uid_a, Some("hash_v1")),
            Some(vec![3, 4])
        );

        // 覆盖为新 hash_v2：删除旧 hash_v1，同时不影响 uid_b
        save(&store_path, "srv:9987", uid_a, Some("hash_v2"), &[5, 6]).unwrap();
        assert!(!s_dir.join(file_name(uid_a, Some("hash_v1"))).exists());
        assert_eq!(
            load_hit(&store_path, "srv:9987", uid_a, Some("hash_v2")),
            Some(vec![5, 6])
        );
        assert_eq!(
            load_hit(&store_path, "srv:9987", uid_b, Some("otherhash")),
            Some(vec![9, 9])
        );

        // remove_uid 只删 uid_a，不碰 uid_b
        remove_uid(&store_path, "srv:9987", uid_a);
        assert_eq!(
            load_hit(&store_path, "srv:9987", uid_a, Some("hash_v2")),
            None
        );
        assert_eq!(
            load_hit(&store_path, "srv:9987", uid_b, Some("otherhash")),
            Some(vec![9, 9])
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn evicts_oldest_avatars_by_count_and_bytes_and_manages_server_dirs() {
        let (dir, store_path) = temp_store_path("lru");
        let s_dir = server_dir(&store_path, "srv:9987");
        let base = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000);
        let uids = ["u1", "u2", "u3", "u4", "u5"];

        for uid in &uids[..3] {
            save_with_limits(&store_path, "srv:9987", uid, Some("h"), &[1; 4], 10, 100).unwrap();
        }
        for (uid, offset) in [("u1", 10u64), ("u2", 20), ("u3", 30)] {
            let file = std::fs::OpenOptions::new()
                .write(true)
                .open(s_dir.join(file_name(uid, Some("h"))))
                .unwrap();
            file.set_modified(base + Duration::from_secs(offset))
                .unwrap();
        }

        save_with_limits(&store_path, "srv:9987", "u4", Some("h"), &[4; 4], 3, 100).unwrap();
        assert_eq!(load_hit(&store_path, "srv:9987", "u1", Some("h")), None);
        assert!(s_dir.join(file_name("u2", Some("h"))).exists());
        assert!(s_dir.join(file_name("u3", Some("h"))).exists());
        assert!(s_dir.join(file_name("u4", Some("h"))).exists());

        for (uid, offset) in [("u2", 10u64), ("u3", 20), ("u4", 30)] {
            let file = std::fs::OpenOptions::new()
                .write(true)
                .open(s_dir.join(file_name(uid, Some("h"))))
                .unwrap();
            file.set_modified(base + Duration::from_secs(offset))
                .unwrap();
        }
        assert_eq!(
            load_hit(&store_path, "srv:9987", "u2", Some("h")),
            Some(vec![1; 4])
        );

        save_with_limits(&store_path, "srv:9987", "u5", Some("h"), &[5; 4], 10, 8).unwrap();
        assert!(!s_dir.join(file_name("u3", Some("h"))).exists());
        assert!(!s_dir.join(file_name("u4", Some("h"))).exists());
        assert_eq!(
            load_hit(&store_path, "srv:9987", "u2", Some("h")),
            Some(vec![1; 4])
        );
        assert_eq!(
            load_hit(&store_path, "srv:9987", "u5", Some("h")),
            Some(vec![5; 4])
        );

        save(&store_path, "gone:9987", "u1", None, &[9]).unwrap();
        prune_orphans(&store_path, &["srv:9987"]);
        assert!(!server_dir(&store_path, "gone:9987").exists());

        move_server(&store_path, "srv:9987", "moved:9987");
        assert!(!server_dir(&store_path, "srv:9987").exists());
        assert_eq!(
            load_hit(&store_path, "moved:9987", "u5", Some("h")),
            Some(vec![5; 4])
        );
        remove_server(&store_path, "moved:9987");
        assert!(!server_dir(&store_path, "moved:9987").exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn disk_queue_runs_on_blocking_thread_in_strict_fifo_order() {
        let (dir, store_path) = temp_store_path("queue");
        let queue = AvatarDiskQueue::new();
        let caller_thread = std::thread::current().id();

        queue.save(
            store_path.clone(),
            "srv:9987".into(),
            "u1".into(),
            Some("h1".into()),
            vec![7, 8, 9],
        );

        let (tx1, rx1) = tokio::sync::oneshot::channel();
        queue.load_hit(
            store_path.clone(),
            "srv:9987".into(),
            "u1".into(),
            Some("h1".into()),
            move |bytes| {
                let _ = tx1.send((std::thread::current().id(), bytes));
            },
        );
        let (worker_thread, hit) = rx1.await.unwrap();
        assert_ne!(worker_thread, caller_thread);
        assert_eq!(hit, Some(vec![7, 8, 9]));

        queue.remove_uid(store_path.clone(), "srv:9987".into(), "u1".into());
        let (tx2, rx2) = tokio::sync::oneshot::channel();
        queue.load_hit(
            store_path.clone(),
            "srv:9987".into(),
            "u1".into(),
            Some("h1".into()),
            move |bytes| {
                let _ = tx2.send(bytes);
            },
        );
        assert_eq!(rx2.await.unwrap(), None);

        queue.flush().await;
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn self_avatar_snapshot_queue_is_fifo_and_survives_avatar_pruning() {
        const PNG_A: [u8; 16] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48,
            0x44, 0x52,
        ];
        const PNG_B: [u8; 16] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48,
            0x44, 0x53,
        ];

        let (dir, store_path) = temp_store_path("self-snapshot");
        let queue = AvatarDiskQueue::new();

        queue.save_self_snapshot(store_path.clone(), PNG_A.to_vec());
        let (tx, rx) = tokio::sync::oneshot::channel();
        queue.load_self_snapshot(store_path.clone(), move |bytes| {
            let _ = tx.send(bytes);
        });
        assert_eq!(rx.await.unwrap(), Some(PNG_A.to_vec()));

        queue.save_self_snapshot(store_path.clone(), PNG_B.to_vec());
        let (tx, rx) = tokio::sync::oneshot::channel();
        queue.load_self_snapshot(store_path.clone(), move |bytes| {
            let _ = tx.send(bytes);
        });
        assert_eq!(rx.await.unwrap(), Some(PNG_B.to_vec()));

        queue.prune_orphans(store_path.clone(), Vec::new());
        let (tx, rx) = tokio::sync::oneshot::channel();
        queue.load_self_snapshot(store_path.clone(), move |bytes| {
            let _ = tx.send(bytes);
        });
        assert_eq!(rx.await.unwrap(), Some(PNG_B.to_vec()));

        queue.clear_self_snapshot(store_path.clone());
        let (tx, rx) = tokio::sync::oneshot::channel();
        queue.load_self_snapshot(store_path.clone(), move |bytes| {
            let _ = tx.send(bytes);
        });
        assert_eq!(rx.await.unwrap(), None);

        queue.flush().await;
        let _ = std::fs::remove_dir_all(&dir);
    }
}
