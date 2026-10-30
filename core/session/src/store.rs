//! 档案、身份与消息历史持久化。文件路径由上层给出，本层不猜默认位置。

use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use tokio::io::AsyncWriteExt;
use tsclient_rs::{Identity, generateIdentity, identityFromString};

use crate::TextMessageView;

/// 生成身份时的安全等级，与 TeamSpeak 客户端默认量级一致。
const IDENTITY_SECURITY_LEVEL: i32 = 8;

pub fn identity_path(store_path: &Path) -> PathBuf {
    store_path.with_file_name("identity.json")
}

pub fn history_path(store_path: &Path) -> PathBuf {
    store_path.with_file_name("messages.jsonl")
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct HistoryEntry {
    server_id: String,
    at: u64,
    from: String,
    from_uid: String,
    #[serde(default)]
    from_id: i32,
    message: String,
    target_mode: i32,
    target_id: u64,
}

impl HistoryEntry {
    fn new(server_id: &str, message: &TextMessageView) -> Self {
        Self {
            server_id: server_id.to_string(),
            at: message.at,
            from: message.from.clone(),
            from_uid: message.from_uid.clone(),
            from_id: message.from_id,
            message: message.message.clone(),
            target_mode: message.target_mode,
            target_id: message.target_id,
        }
    }

    fn into_view(self) -> TextMessageView {
        TextMessageView {
            from: self.from,
            from_uid: self.from_uid,
            from_id: self.from_id,
            message: self.message,
            target_mode: self.target_mode,
            target_id: self.target_id,
            at: self.at,
        }
    }
}

pub async fn append_history(
    path: &Path,
    server_id: &str,
    message: &TextMessageView,
) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|err| err.to_string())?;
    }
    let line = serde_json::to_string(&HistoryEntry::new(server_id, message))
        .map_err(|err| err.to_string())?;
    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .await
        .map_err(|err| err.to_string())?;
    file.write_all(format!("{line}\n").as_bytes())
        .await
        .map_err(|err| err.to_string())?;
    file.flush().await.map_err(|err| err.to_string())
}

pub async fn load_history(
    path: &Path,
    server_id: &str,
    limit: usize,
) -> Result<Vec<TextMessageView>, String> {
    let raw = match tokio::fs::read_to_string(path).await {
        Ok(raw) => raw,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(err) => return Err(err.to_string()),
    };

    let mut messages: Vec<TextMessageView> = raw
        .lines()
        .filter_map(|line| serde_json::from_str::<HistoryEntry>(line).ok())
        .filter(|entry| entry.server_id == server_id)
        .map(HistoryEntry::into_view)
        .collect();
    if messages.len() > limit {
        messages.drain(..messages.len() - limit);
    }
    Ok(messages)
}

/// 启动时按服务器保留最近 `limit_per_server` 条。
///
/// 只在确实有内容被丢弃或存在坏行时重写，避免每次启动都改文件。
pub async fn compact_history(path: &Path, limit_per_server: usize) -> Result<(), String> {
    let raw = match tokio::fs::read_to_string(path).await {
        Ok(raw) => raw,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(err) => return Err(err.to_string()),
    };

    let mut total = 0usize;
    let mut malformed = 0usize;
    let mut by_server: HashMap<String, VecDeque<HistoryEntry>> = HashMap::new();
    for line in raw.lines() {
        if line.trim().is_empty() {
            continue;
        }
        total += 1;
        match serde_json::from_str::<HistoryEntry>(line) {
            Ok(entry) => {
                let queue = by_server.entry(entry.server_id.clone()).or_default();
                queue.push_back(entry);
                if queue.len() > limit_per_server {
                    queue.pop_front();
                }
            }
            Err(_) => malformed += 1,
        }
    }

    let mut kept: Vec<HistoryEntry> = by_server.into_values().flatten().collect();
    kept.sort_by_key(|entry| (entry.server_id.clone(), entry.at));

    if kept.len() == total && malformed == 0 {
        return Ok(());
    }

    let mut output = String::new();
    for entry in kept {
        let line = serde_json::to_string(&entry).map_err(|err| err.to_string())?;
        output.push_str(&line);
        output.push('\n');
    }
    write_atomic(path, output.as_bytes()).await
}

pub async fn load_identity(path: &Path) -> Result<Identity, String> {
    match tokio::fs::read_to_string(path).await {
        Ok(raw) => identityFromString(raw.trim()).map_err(|error| error.to_string()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            let identity = generateIdentity(IDENTITY_SECURITY_LEVEL);
            save_identity_atomic(path, &identity).await?;
            Ok(identity)
        }
        Err(error) => Err(error.to_string()),
    }
}

/// 原子写身份文件：临时文件 + fsync + rename。
///
/// 身份文件承载用户在服务器上的全部权限，挖矿中途被杀也不能留下半个文件。
pub async fn save_identity_atomic(path: &Path, identity: &Identity) -> Result<(), String> {
    write_atomic(path, identity.to_string().as_bytes()).await
}

async fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|error| error.to_string())?;
    }
    let file_name = path
        .file_name()
        .ok_or_else(|| "文件路径没有文件名".to_string())?;
    let mut temp_name = file_name.to_os_string();
    temp_name.push(format!(".{:032x}.tmp", rand::random::<u128>()));
    let temp = path.with_file_name(temp_name);
    let mut options = tokio::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    options.mode(0o600);
    let mut file = options
        .open(&temp)
        .await
        .map_err(|error| error.to_string())?;
    let written = async {
        file.write_all(bytes).await?;
        file.sync_all().await
    }
    .await;
    drop(file);
    // rename 的覆盖语义由文件系统提供；失败时不能先删除用户的旧文件。
    let outcome = match written {
        Ok(()) => tokio::fs::rename(&temp, path).await,
        Err(error) => Err(error),
    };
    if let Err(error) = outcome {
        if let Err(cleanup) = tokio::fs::remove_file(&temp).await {
            return Err(format!("{error}; 清理临时文件失败: {cleanup}"));
        }
        return Err(error.to_string());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn invalid_identity_is_not_replaced_with_a_new_key() {
        let dir = std::env::temp_dir().join(format!(
            "flspeak-invalid-identity-{:x}",
            rand::random::<u64>()
        ));
        tokio::fs::create_dir_all(&dir).await.unwrap();
        let path = dir.join("identity.json");
        tokio::fs::write(&path, b"invalid identity - preserve for recovery")
            .await
            .unwrap();
        assert!(load_identity(&path).await.is_err());
        assert_eq!(
            tokio::fs::read(&path).await.unwrap(),
            b"invalid identity - preserve for recovery"
        );
        tokio::fs::remove_dir_all(&dir).await.unwrap();
    }

    #[tokio::test]
    async fn atomic_replacement_failure_preserves_destination_and_cleans_staging() {
        let dir = std::env::temp_dir().join(format!(
            "flspeak-atomic-failure-{:x}",
            rand::random::<u64>()
        ));
        let path = dir.join("identity.json");
        tokio::fs::create_dir_all(&path).await.unwrap();
        tokio::fs::write(path.join("keep"), b"original")
            .await
            .unwrap();
        assert!(write_atomic(&path, b"replacement").await.is_err());
        assert_eq!(
            tokio::fs::read(path.join("keep")).await.unwrap(),
            b"original"
        );
        let mut entries = tokio::fs::read_dir(&dir).await.unwrap();
        assert_eq!(
            entries.next_entry().await.unwrap().unwrap().file_name(),
            "identity.json"
        );
        assert!(entries.next_entry().await.unwrap().is_none());
        tokio::fs::remove_dir_all(&dir).await.unwrap();
    }

    #[tokio::test]
    async fn concurrent_atomic_writes_publish_only_complete_files() {
        let dir = std::env::temp_dir().join(format!(
            "flspeak-atomic-concurrent-{:x}",
            rand::random::<u64>()
        ));
        let path = dir.join("data.json");
        let mut writes = Vec::new();
        for index in 0..12u8 {
            let path = path.clone();
            writes.push(tokio::spawn(async move {
                write_atomic(&path, &vec![index; 32 * 1024]).await
            }));
        }
        for write in writes {
            write.await.unwrap().unwrap();
        }
        let bytes = tokio::fs::read(&path).await.unwrap();
        assert_eq!(bytes.len(), 32 * 1024);
        assert!(bytes.iter().all(|byte| *byte == bytes[0]));
        let mut entries = tokio::fs::read_dir(&dir).await.unwrap();
        assert!(entries.next_entry().await.unwrap().is_some());
        assert!(entries.next_entry().await.unwrap().is_none());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                tokio::fs::metadata(&path)
                    .await
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
        tokio::fs::remove_dir_all(&dir).await.unwrap();
    }

    #[tokio::test]
    async fn identity_is_generated_once_and_reloaded() {
        let dir = std::env::temp_dir().join("flspeak-session-identity-test");
        let path = identity_path(&dir.join("preferences.json"));
        let _ = tokio::fs::remove_dir_all(&dir).await;

        let first = load_identity(&path).await.unwrap();
        let second = load_identity(&path).await.unwrap();
        assert_eq!(first.to_string(), second.to_string());
        assert_eq!(first.public_key_base64(), second.public_key_base64());

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    fn message(at: u64, text: &str) -> TextMessageView {
        TextMessageView {
            from: "alice".into(),
            from_uid: "uid-alice".into(),
            from_id: 8,
            message: text.into(),
            target_mode: 2,
            target_id: 7,
            at,
        }
    }

    #[tokio::test]
    async fn identity_write_is_atomic_and_leaves_no_temp_file() {
        let dir = std::env::temp_dir().join("flspeak-session-atomic-identity-test");
        let path = identity_path(&dir.join("preferences.json"));
        let _ = tokio::fs::remove_dir_all(&dir).await;

        let identity = load_identity(&path).await.unwrap();
        save_identity_atomic(&path, &identity).await.unwrap();

        let raw = tokio::fs::read_to_string(&path).await.unwrap();
        assert_eq!(raw, identity.to_string());
        assert!(
            !tokio::fs::try_exists(path.with_file_name("identity.json.tmp"))
                .await
                .unwrap()
        );

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn history_appends_and_loads_the_latest_messages() {
        let dir = std::env::temp_dir().join("flspeak-session-history-test");
        let path = history_path(&dir.join("preferences.json"));
        let _ = tokio::fs::remove_dir_all(&dir).await;

        for index in 0..5 {
            append_history(&path, "ts.example.com:9987", &message(index, "hi"))
                .await
                .unwrap();
        }
        append_history(&path, "other.example.com:9987", &message(6, "other"))
            .await
            .unwrap();

        let loaded = load_history(&path, "ts.example.com:9987", 3).await.unwrap();
        assert_eq!(loaded.len(), 3);
        assert_eq!(loaded[0].at, 2);
        assert_eq!(loaded[0].from_id, 8);
        assert_eq!(loaded[2].at, 4);

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn history_compaction_keeps_a_limit_per_server() {
        let dir = std::env::temp_dir().join("flspeak-session-compact-test");
        let path = history_path(&dir.join("preferences.json"));
        let _ = tokio::fs::remove_dir_all(&dir).await;

        for index in 0..10 {
            append_history(&path, "a.example.com:9987", &message(index, "a"))
                .await
                .unwrap();
            append_history(&path, "b.example.com:9987", &message(index, "b"))
                .await
                .unwrap();
        }
        compact_history(&path, 3).await.unwrap();

        assert_eq!(
            load_history(&path, "a.example.com:9987", 10)
                .await
                .unwrap()
                .len(),
            3
        );
        assert_eq!(
            load_history(&path, "b.example.com:9987", 10)
                .await
                .unwrap()
                .len(),
            3
        );

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn malformed_history_lines_are_skipped() {
        let dir = std::env::temp_dir().join("flspeak-session-bad-history-test");
        let path = history_path(&dir.join("preferences.json"));
        let _ = tokio::fs::remove_dir_all(&dir).await;
        tokio::fs::create_dir_all(&dir).await.unwrap();
        tokio::fs::write(&path, "not json\n{\"server_id\":\"x\"}\n")
            .await
            .unwrap();

        assert!(
            load_history(&path, "x", 10).await.unwrap().is_empty(),
            "坏行不能把整个历史读崩"
        );
        compact_history(&path, 10).await.unwrap();
        assert_eq!(tokio::fs::read_to_string(&path).await.unwrap().trim(), "");

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }
}
