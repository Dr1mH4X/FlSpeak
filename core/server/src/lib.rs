//! 服务器档案与地址解析。
//!
//! 这里只负责“地址是否可解析、档案是否已登记”。官方基础设施的边界由
//! `proto::client` 在最终建连目标上检查一次，不在录入、FFI 或 UI 重复维护。

use serde::{Deserialize, Serialize};

/// TeamSpeak 语音服务默认端口。
pub const DEFAULT_VOICE_PORT: u16 = 9987;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AddressError {
    #[error("服务器地址为空")]
    Empty,

    #[error("服务器地址格式非法: {0}")]
    Malformed(String),

    #[error("请填写服务器域名或 IP: {input}")]
    HostRequired { input: String },
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ServerError {
    #[error(transparent)]
    Address(#[from] AddressError),

    #[error("服务器 {0} 未在本地档案中登记")]
    NotRegistered(String),
}

/// 解析后的连接目标。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerTarget {
    pub host: String,
    pub port: u16,
}

impl ServerTarget {
    pub fn authority(&self) -> String {
        join_host_port(&self.host, self.port)
    }
}

/// 用户显式录入的服务器档案。
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
    /// 连接前重新解析一次，防止档案文件被外部改写。
    pub fn target(&self) -> Result<ServerTarget, AddressError> {
        let target = parse_address(&join_host_port(&self.host, self.port))?;
        if target.authority() != self.id {
            return Err(AddressError::Malformed(format!(
                "档案主键 {} 与地址 {} 不一致",
                self.id,
                target.authority()
            )));
        }
        Ok(target)
    }
}

/// 显式登记录入的服务器集合。
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

    pub fn register(&mut self, label: &str, address: &str) -> Result<ServerProfile, ServerError> {
        let target = parse_address(address)?;
        let id = target.authority();
        if let Some(existing) = self.profiles.iter().find(|profile| profile.id == id) {
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

    pub fn require(&self, id: &str) -> Result<&ServerProfile, ServerError> {
        self.profiles
            .iter()
            .find(|profile| profile.id == id)
            .ok_or_else(|| ServerError::NotRegistered(id.to_string()))
    }

    pub fn remove(&mut self, id: &str) -> bool {
        let before = self.profiles.len();
        self.profiles.retain(|profile| profile.id != id);
        self.profiles.len() != before
    }
}

/// 解析 `host` 或 `host:port`。只接受 IP、域名和 `localhost`，不接受裸昵称。
pub fn parse_address(address: &str) -> Result<ServerTarget, AddressError> {
    let trimmed = address.trim();
    if trimmed.is_empty() {
        return Err(AddressError::Empty);
    }
    if trimmed.contains("://") {
        return Err(AddressError::Malformed(format!(
            "{trimmed} 带协议前缀, 只接受 host 或 host:port"
        )));
    }

    let (host, port) = split_host_port(trimmed)?;
    if host.is_empty() {
        return Err(AddressError::Malformed(trimmed.to_string()));
    }

    // 无点的非 IP 主机名会被 tsclient-rs 当作昵称，去请求官方解析接口。
    if !is_ip_literal(&host) && !host.contains('.') && host != "localhost" {
        return Err(AddressError::HostRequired { input: host });
    }

    Ok(ServerTarget { host, port })
}

pub fn is_ip_literal(host: &str) -> bool {
    if host.contains(':') {
        return host.parse::<std::net::Ipv6Addr>().is_ok();
    }
    host.parse::<std::net::Ipv4Addr>().is_ok()
}

/// 小写、去首尾空白与末尾点、去 IPv6 方括号。
pub fn normalize_host(host: &str) -> String {
    let host = host.trim().to_ascii_lowercase();
    let host = host.strip_suffix('.').unwrap_or(&host);
    let host = host.strip_prefix('[').unwrap_or(host);
    let host = host.strip_suffix(']').unwrap_or(host);
    host.to_string()
}

pub fn join_host_port(host: &str, port: u16) -> String {
    if host.contains(':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

fn split_host_port(address: &str) -> Result<(String, u16), AddressError> {
    if let Some(rest) = address.strip_prefix('[') {
        let (host, tail) = rest
            .split_once(']')
            .ok_or_else(|| AddressError::Malformed(address.to_string()))?;
        let port = match tail.strip_prefix(':') {
            Some(raw) => parse_port(raw, address)?,
            None if tail.is_empty() => DEFAULT_VOICE_PORT,
            None => return Err(AddressError::Malformed(address.to_string())),
        };
        if host.parse::<std::net::Ipv6Addr>().is_err() {
            return Err(AddressError::Malformed(address.to_string()));
        }
        return Ok((normalize_host(host), port));
    }

    match address.rsplit_once(':') {
        Some((host, raw)) => {
            if host.contains(':') {
                return Err(AddressError::Malformed(address.to_string()));
            }
            Ok((normalize_host(host), parse_port(raw, address)?))
        }
        None => Ok((normalize_host(address), DEFAULT_VOICE_PORT)),
    }
}

fn parse_port(raw: &str, address: &str) -> Result<u16, AddressError> {
    let port = raw
        .parse::<u16>()
        .map_err(|_| AddressError::Malformed(address.to_string()))?;
    if port == 0 {
        return Err(AddressError::Malformed(address.to_string()));
    }
    Ok(port)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn target(address: &str) -> ServerTarget {
        parse_address(address).expect("地址应当可解析")
    }

    #[test]
    fn accepts_ip_domain_and_localhost() {
        assert_eq!(target("127.0.0.1:9987").host, "127.0.0.1");
        assert_eq!(target("127.0.0.1").port, DEFAULT_VOICE_PORT);
        assert_eq!(target("[::1]:9987").host, "::1");
        assert_eq!(target("localhost").host, "localhost");
        assert_eq!(target("ts.example.com").host, "ts.example.com");
        assert_eq!(target("TS.Example.COM.").host, "ts.example.com");
        assert_eq!(target("ts.example.com:10000").port, 10000);
    }

    #[test]
    fn rejects_bare_nickname_and_malformed_addresses() {
        assert_eq!(
            parse_address("my-server"),
            Err(AddressError::HostRequired {
                input: "my-server".into()
            })
        );
        assert_eq!(parse_address("   "), Err(AddressError::Empty));
        for address in [
            "https://ts.example.com",
            "ts.example.com:0",
            "ts.example.com:99999",
            "ts.example.com:abc",
            "[::1",
        ] {
            assert!(
                matches!(parse_address(address), Err(AddressError::Malformed(_))),
                "{address}"
            );
        }
    }

    #[test]
    fn registry_deduplicates_and_requires_profiles() {
        let mut registry = ServerRegistry::new();
        let profile = registry.register("home", "ts.example.com").unwrap();
        assert_eq!(profile.id, "ts.example.com:9987");
        assert_eq!(registry.profiles().len(), 1);
        assert_eq!(registry.require(&profile.id).unwrap().label, "home");
        assert_eq!(registry.register("dup", "ts.example.com").unwrap(), profile);
        assert_eq!(registry.profiles().len(), 1);

        assert!(matches!(
            registry.require("ts.example.com:9999"),
            Err(ServerError::NotRegistered(_))
        ));
        assert!(registry.remove(&profile.id));
        assert!(!registry.remove(&profile.id));
    }

    #[test]
    fn profile_target_reparses_stored_fields() {
        let mut profile = ServerRegistry::new()
            .register("home", "ts.example.com")
            .unwrap();
        assert_eq!(profile.target().unwrap().port, DEFAULT_VOICE_PORT);

        profile.host = "my-server".to_string();
        assert!(matches!(
            profile.target(),
            Err(AddressError::HostRequired { .. })
        ));
    }
}
