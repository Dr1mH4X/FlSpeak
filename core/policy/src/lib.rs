//! 连接合规策略：强制连接自托管服务器，禁连官方基础设施。
//!
//! 策略只在本 crate 归口，Dart 侧没有任何可绕过的入口。改动本 crate 必须同时更新
//! 测试与 `.agents/notes` 下的决策记录。

mod official_infra;

pub use official_infra::{FORBIDDEN_HOST_SUFFIXES, OFFICIAL_SERVICE_URLS};

use serde::{Deserialize, Serialize};

/// TeamSpeak 语音服务默认端口。
pub const DEFAULT_VOICE_PORT: u16 = 9987;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PolicyError {
    #[error("服务器地址为空")]
    Empty,

    #[error("服务器地址格式非法: {0}")]
    Malformed(String),

    #[error("拒绝裸昵称 {input}: 昵称解析会请求官方服务, 请填写服务器域名或 IP")]
    NicknameNotAllowed { input: String },

    #[error("拒绝官方基础设施 {host} (命中 {matched})")]
    OfficialInfra { host: String, matched: String },

    #[error("服务器 {0} 未在本地档案中登记")]
    NotRegistered(String),

    #[error("文件传输主机 {actual} 与会话主机 {expected} 不一致")]
    TransferHostMismatch { expected: String, actual: String },
}

/// 通过 T1 校验的连接目标。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApprovedTarget {
    pub host: String,
    pub port: u16,
}

impl ApprovedTarget {
    pub fn authority(&self) -> String {
        join_host_port(&self.host, self.port)
    }
}

/// 用户显式录入的服务器档案（T2）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServerProfile {
    /// 归一化后的 `host:port`，同时作为档案主键，天然去重。
    pub id: String,
    pub label: String,
    pub host: String,
    pub port: u16,
    #[serde(default)]
    pub server_password: Option<String>,
    #[serde(default)]
    pub default_channel: Option<String>,
    #[serde(default)]
    pub default_channel_password: Option<String>,
}

impl ServerProfile {
    /// 连接前重新校验一次，防止档案文件被外部改写。
    pub fn target(&self) -> Result<ApprovedTarget, PolicyError> {
        let target = validate_address(&join_host_port(&self.host, self.port))?;
        if target.authority() != self.id {
            return Err(PolicyError::Malformed(format!(
                "档案主键 {} 与地址 {} 不一致",
                self.id,
                target.authority()
            )));
        }
        Ok(target)
    }
}

/// 显式登记录入的服务器集合。
///
/// 这里刻意不提供目录导入、昵称解析、批量订阅之类的入口：T2 的含义就是连接目标
/// 只能来自用户逐条录入。
#[derive(Debug, Default, Clone)]
pub struct ServerRegistry {
    profiles: Vec<ServerProfile>,
}

impl ServerRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn from_profiles(profiles: Vec<ServerProfile>) -> Self {
        Self { profiles }
    }

    pub fn profiles(&self) -> &[ServerProfile] {
        &self.profiles
    }

    pub fn register(&mut self, label: &str, address: &str) -> Result<ServerProfile, PolicyError> {
        let target = validate_address(address)?;
        let id = target.authority();
        if let Some(existing) = self.profiles.iter().find(|p| p.id == id) {
            return Ok(existing.clone());
        }
        let profile = ServerProfile {
            id,
            label: label.trim().to_string(),
            host: target.host,
            port: target.port,
            server_password: None,
            default_channel: None,
            default_channel_password: None,
        };
        self.profiles.push(profile.clone());
        Ok(profile)
    }

    /// 连接目标的唯一来源。未登记的档案一律拒绝。
    pub fn require(&self, id: &str) -> Result<&ServerProfile, PolicyError> {
        self.profiles
            .iter()
            .find(|p| p.id == id)
            .ok_or_else(|| PolicyError::NotRegistered(id.to_string()))
    }

    pub fn remove(&mut self, id: &str) -> bool {
        let before = self.profiles.len();
        self.profiles.retain(|p| p.id != id);
        self.profiles.len() != before
    }
}

/// T1 入口校验。只接受 `host` 或 `host:port`，IPv6 必须写成 `[addr]`。
pub fn validate_address(address: &str) -> Result<ApprovedTarget, PolicyError> {
    let trimmed = address.trim();
    if trimmed.is_empty() {
        return Err(PolicyError::Empty);
    }
    if trimmed.contains("://") {
        return Err(PolicyError::Malformed(format!(
            "{trimmed} 带协议前缀, 只接受 host 或 host:port"
        )));
    }

    let (host, port) = split_host_port(trimmed)?;
    if host.is_empty() {
        return Err(PolicyError::Malformed(trimmed.to_string()));
    }

    if let Some(matched) = forbidden_match(&host) {
        return Err(PolicyError::OfficialInfra {
            host: host.clone(),
            matched: matched.to_string(),
        });
    }

    // 无点的非 IP 主机名会被 tsclient-rs 当作昵称，去请求官方解析接口。
    if !is_ip_literal(&host) && !host.contains('.') && host != "localhost" {
        return Err(PolicyError::NicknameNotAllowed { input: host });
    }

    Ok(ApprovedTarget { host, port })
}

/// 文件传输必须落在会话已校验的主机上，端口由服务器下发。
pub fn assert_transfer_host(expected: &str, actual: &str) -> Result<(), PolicyError> {
    let expected = normalize_host(expected);
    let actual = normalize_host(actual);
    if expected == actual {
        return Ok(());
    }
    Err(PolicyError::TransferHostMismatch { expected, actual })
}

/// 命中官方基础设施时返回命中的后缀。
pub fn forbidden_match(host: &str) -> Option<&'static str> {
    let host = normalize_host(host);
    FORBIDDEN_HOST_SUFFIXES
        .iter()
        .copied()
        .find(|suffix| host == *suffix || host.ends_with(&format!(".{suffix}")))
}

pub fn is_ip_literal(host: &str) -> bool {
    if host.contains(':') {
        return true;
    }
    let parts: Vec<&str> = host.split('.').collect();
    parts.len() == 4
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.len() <= 3 && p.bytes().all(|b| b.is_ascii_digit()))
}

/// 小写、去首尾空白与末尾点、去 IPv6 方括号。
pub fn normalize_host(host: &str) -> String {
    let host = host.trim().to_ascii_lowercase();
    let host = host.strip_suffix('.').unwrap_or(&host);
    let host = host.strip_prefix('[').unwrap_or(host);
    let host = host.strip_suffix(']').unwrap_or(host);
    host.to_string()
}

fn split_host_port(address: &str) -> Result<(String, u16), PolicyError> {
    if let Some(rest) = address.strip_prefix('[') {
        let (host, tail) = rest
            .split_once(']')
            .ok_or_else(|| PolicyError::Malformed(address.to_string()))?;
        let port = match tail.strip_prefix(':') {
            Some(raw) => parse_port(raw, address)?,
            None if tail.is_empty() => DEFAULT_VOICE_PORT,
            None => return Err(PolicyError::Malformed(address.to_string())),
        };
        return Ok((normalize_host(host), port));
    }

    match address.rsplit_once(':') {
        Some((host, raw)) => Ok((normalize_host(host), parse_port(raw, address)?)),
        None => Ok((normalize_host(address), DEFAULT_VOICE_PORT)),
    }
}

fn parse_port(raw: &str, address: &str) -> Result<u16, PolicyError> {
    raw.parse::<u16>()
        .map_err(|_| PolicyError::Malformed(address.to_string()))
}

fn join_host_port(host: &str, port: u16) -> String {
    if host.contains(':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn approved(address: &str) -> ApprovedTarget {
        validate_address(address).expect("应当通过校验")
    }

    #[test]
    fn accepts_self_hosted_addresses() {
        assert_eq!(approved("127.0.0.1:9987").host, "127.0.0.1");
        assert_eq!(approved("127.0.0.1").port, DEFAULT_VOICE_PORT);
        assert_eq!(approved("[::1]:9987").host, "::1");
        assert_eq!(approved("localhost").host, "localhost");
        assert_eq!(approved("ts.example.com").host, "ts.example.com");
        assert_eq!(approved("TS.Example.COM.").host, "ts.example.com");
        assert_eq!(approved("ts.example.com:10000").port, 10000);
    }

    #[test]
    fn suffix_match_does_not_hit_lookalike_domains() {
        assert!(forbidden_match("teamspeak.com.evil.net").is_none());
        assert!(forbidden_match("notteamspeak.com").is_none());
        assert!(forbidden_match("myteamspeak.com.evil.net").is_none());
        assert!(forbidden_match("teamspeak.company").is_none());
        assert_eq!(forbidden_match("teamspeak.com"), Some("teamspeak.com"));
    }

    #[test]
    fn rejects_official_infrastructure() {
        for address in [
            "voice.teamspeak.com",
            "VOICE.TEAMSPEAK.COM.",
            "named.myteamspeak.com",
            "a.teamspeak-systems.com",
            "teamspeak.com:9987",
        ] {
            match validate_address(address) {
                Err(PolicyError::OfficialInfra { matched, .. }) => {
                    assert!(!matched.is_empty(), "{address}");
                }
                other => panic!("{address} 应当被拒绝, 实际 {other:?}"),
            }
        }
    }

    #[test]
    fn rejects_bare_nickname() {
        assert_eq!(
            validate_address("my-server"),
            Err(PolicyError::NicknameNotAllowed {
                input: "my-server".into()
            })
        );
    }

    #[test]
    fn rejects_malformed_addresses() {
        assert_eq!(validate_address("   "), Err(PolicyError::Empty));
        for address in [
            "https://ts.example.com",
            "ts.example.com:99999",
            "ts.example.com:abc",
        ] {
            assert!(
                matches!(validate_address(address), Err(PolicyError::Malformed(_))),
                "{address}"
            );
        }
    }

    #[test]
    fn registry_only_accepts_self_hosted_profiles() {
        let mut registry = ServerRegistry::new();
        assert!(matches!(
            registry.register("official", "voice.teamspeak.com"),
            Err(PolicyError::OfficialInfra { .. })
        ));

        let profile = registry.register("home", "ts.example.com").unwrap();
        assert_eq!(profile.id, "ts.example.com:9987");
        assert_eq!(registry.profiles().len(), 1);
        assert_eq!(registry.require(&profile.id).unwrap().label, "home");
        assert_eq!(registry.register("dup", "ts.example.com").unwrap(), profile);
        assert_eq!(registry.profiles().len(), 1);

        assert!(matches!(
            registry.require("ts.example.com:9999"),
            Err(PolicyError::NotRegistered(_))
        ));
        assert!(registry.remove(&profile.id));
        assert!(!registry.remove(&profile.id));
    }

    #[test]
    fn profile_target_revalidates_stored_fields() {
        let mut profile = ServerRegistry::new()
            .register("home", "ts.example.com")
            .unwrap();
        assert_eq!(profile.target().unwrap().port, DEFAULT_VOICE_PORT);

        profile.host = "voice.teamspeak.com".to_string();
        assert!(matches!(
            profile.target(),
            Err(PolicyError::OfficialInfra { .. })
        ));
    }

    #[test]
    fn transfer_host_must_match_session_host() {
        assert!(assert_transfer_host("ts.example.com", "TS.Example.COM.").is_ok());
        assert!(matches!(
            assert_transfer_host("ts.example.com", "evil.net"),
            Err(PolicyError::TransferHostMismatch { .. })
        ));
    }
}
