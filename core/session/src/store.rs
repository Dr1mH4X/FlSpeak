//! 档案、身份与消息历史持久化。文件路径由上层给出，本层不猜默认位置。

use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use server::{ServerProfile, ServerRegistry};
use tokio::io::AsyncWriteExt;
use tsclient_rs::{Identity, generateIdentity, identityFromString};

use crate::TextMessageView;

/// 生成身份时的安全等级，与 TeamSpeak 客户端默认量级一致。
const IDENTITY_SECURITY_LEVEL: i32 = 8;

pub fn identity_path(store_path: &Path) -> PathBuf {
    store_path.with_file_name("identity.txt")
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
    tokio::fs::write(path, output)
        .await
        .map_err(|err| err.to_string())
}

pub async fn load_registry(path: &Path) -> Result<ServerRegistry, String> {
    match tokio::fs::read_to_string(path).await {
        Ok(raw) => {
            let profiles: Vec<ServerProfile> =
                serde_json::from_str(&raw).map_err(|err| err.to_string())?;
            Ok(ServerRegistry::from_profiles(profiles))
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(ServerRegistry::new()),
        Err(err) => Err(err.to_string()),
    }
}

pub async fn save_registry(path: &Path, registry: &ServerRegistry) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|err| err.to_string())?;
    }
    let raw = serde_json::to_string_pretty(registry.profiles()).map_err(|err| err.to_string())?;
    tokio::fs::write(path, raw)
        .await
        .map_err(|err| err.to_string())
}

pub async fn load_identity(path: &Path) -> Result<Identity, String> {
    if let Ok(raw) = tokio::fs::read_to_string(path).await
        && let Ok(identity) = identityFromString(raw.trim())
    {
        return Ok(identity);
    }
    let identity = generateIdentity(IDENTITY_SECURITY_LEVEL);
    save_identity_atomic(path, &identity).await?;
    Ok(identity)
}

/// 原子写身份文件：临时文件 + fsync + rename。
///
/// 身份文件承载用户在服务器上的全部权限，挖矿中途被杀也不能留下半个文件。
pub async fn save_identity_atomic(path: &Path, identity: &Identity) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|err| err.to_string())?;
    }
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| "身份文件路径没有文件名".to_string())?;
    let temp = path.with_file_name(format!("{file_name}.tmp"));

    let mut file = tokio::fs::File::create(&temp)
        .await
        .map_err(|err| err.to_string())?;
    file.write_all(identity.to_string().as_bytes())
        .await
        .map_err(|err| err.to_string())?;
    file.sync_all().await.map_err(|err| err.to_string())?;
    drop(file);

    match tokio::fs::rename(&temp, path).await {
        Ok(()) => Ok(()),
        Err(_) => {
            // Windows 上 rename 不覆盖已有文件；退化成先删后改名。
            tokio::fs::remove_file(path)
                .await
                .map_err(|err| err.to_string())?;
            tokio::fs::rename(&temp, path)
                .await
                .map_err(|err| err.to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn registry_round_trips_through_disk() {
        let dir = std::env::temp_dir().join("flspeak-session-store-test");
        let path = dir.join("servers.json");
        let _ = tokio::fs::remove_dir_all(&dir).await;

        let mut registry = ServerRegistry::new();
        registry.register("home", "ts.example.com").unwrap();
        save_registry(&path, &registry).await.unwrap();

        let loaded = load_registry(&path).await.unwrap();
        assert_eq!(loaded.profiles(), registry.profiles());

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn missing_registry_is_empty() {
        let path = std::env::temp_dir().join("flspeak-session-missing/servers.json");
        let loaded = load_registry(&path).await.unwrap();
        assert!(loaded.profiles().is_empty());
    }

    #[tokio::test]
    async fn identity_is_generated_once_and_reloaded() {
        let dir = std::env::temp_dir().join("flspeak-session-identity-test");
        let path = identity_path(&dir.join("servers.json"));
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
        let path = identity_path(&dir.join("servers.json"));
        let _ = tokio::fs::remove_dir_all(&dir).await;

        let identity = load_identity(&path).await.unwrap();
        save_identity_atomic(&path, &identity).await.unwrap();

        let raw = tokio::fs::read_to_string(&path).await.unwrap();
        assert_eq!(raw, identity.to_string());
        assert!(
            !tokio::fs::try_exists(path.with_file_name("identity.txt.tmp"))
                .await
                .unwrap()
        );

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn history_appends_and_loads_the_latest_messages() {
        let dir = std::env::temp_dir().join("flspeak-session-history-test");
        let path = history_path(&dir.join("servers.json"));
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
        let path = history_path(&dir.join("servers.json"));
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
        let path = history_path(&dir.join("servers.json"));
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
