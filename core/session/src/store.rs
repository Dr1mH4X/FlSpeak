//! 档案与身份持久化。文件路径由上层给出，本层不猜默认位置。

use std::path::{Path, PathBuf};

use policy::{ServerProfile, ServerRegistry};
use tsclient_rs::{Identity, generateIdentity, identityFromString};

/// 生成身份时的安全等级，与 TeamSpeak 客户端默认量级一致。
const IDENTITY_SECURITY_LEVEL: i32 = 8;

pub fn identity_path(store_path: &Path) -> PathBuf {
    store_path.with_file_name("identity.txt")
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
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|err| err.to_string())?;
    }
    tokio::fs::write(path, identity.to_string())
        .await
        .map_err(|err| err.to_string())?;
    Ok(identity)
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
}
