//! tsclient-rs 的窄封装。
//!
//! `resolve_target` 负责用户域名的 SRV 查询；最终建连目标由 `client` 做一次
//! 官方基础设施检查。tsclient-rs 自己的 discovery 仍然被 `DenyResolver` 挡住，
//! 因此裸昵称不会请求 `named.myteamspeak.com/lookup`。

use std::sync::Arc;

use async_trait::async_trait;
use hickory_resolver::TokioAsyncResolver;
use server::{
    AddressError, ServerProfile, ServerTarget, is_ip_literal, normalize_host, parse_address,
};
use tsclient_rs::{
    AbortSignal, AddrResolver, Client, ClientOptions, Error as ProtocolError, Identity, Logger,
    ResolvedAddr,
};

/// 官方基础设施主机后缀。连接和图片抓取共用这一份清单。
pub const FORBIDDEN_HOST_SUFFIXES: &[&str] =
    &["teamspeak.com", "teamspeak-systems.com", "myteamspeak.com"];

#[derive(Debug, thiserror::Error)]
pub enum ConnectError {
    #[error(transparent)]
    Address(#[from] AddressError),

    #[error("拒绝连接官方基础设施 {host} (命中 {matched})")]
    Blocked { host: String, matched: String },

    #[error("文件传输主机 {actual} 与会话主机 {expected} 不一致")]
    TransferHostMismatch { expected: String, actual: String },

    #[error("{0}")]
    Protocol(String),
}

/// 命中官方基础设施时返回命中的后缀。
pub fn forbidden_host(host: &str) -> Option<&'static str> {
    let host = normalize_host(host);
    FORBIDDEN_HOST_SUFFIXES
        .iter()
        .copied()
        .find(|suffix| host == *suffix || host.ends_with(&format!(".{suffix}")))
}

fn ensure_allowed_target(host: &str) -> Result<(), ConnectError> {
    if let Some(matched) = forbidden_host(host) {
        return Err(ConnectError::Blocked {
            host: host.to_string(),
            matched: matched.to_string(),
        });
    }
    Ok(())
}

/// 拒绝一切地址解析请求。
///
/// 无点主机名会被 tsclient-rs 当作昵称并请求官方 `named.myteamspeak.com`。
/// `server::parse_address` 已拒绝裸昵称；这里再兜住协议库自带的重定向路径。
pub struct DenyResolver;

#[async_trait]
impl AddrResolver for DenyResolver {
    async fn resolve(
        &self,
        addr: &str,
        _signal: Option<&AbortSignal>,
    ) -> Result<Vec<ResolvedAddr>, ProtocolError> {
        Err(ProtocolError::Teamspeak(format!(
            "address resolution is disabled; enter an IP or domain: {addr}"
        )))
    }
}

/// 一条 SRV 记录。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SrvRecord {
    pub host: String,
    pub port: u16,
    pub priority: u16,
    pub weight: u16,
}

#[async_trait]
pub trait SrvResolver: Send + Sync {
    async fn lookup_srv(&self, name: &str) -> Result<Vec<SrvRecord>, String>;
}

/// 使用系统 DNS 配置查询 SRV。
#[derive(Debug, Default, Clone, Copy)]
pub struct DnsSrvResolver;

#[async_trait]
impl SrvResolver for DnsSrvResolver {
    async fn lookup_srv(&self, name: &str) -> Result<Vec<SrvRecord>, String> {
        let resolver =
            TokioAsyncResolver::tokio_from_system_conf().map_err(|err| err.to_string())?;
        let lookup = resolver
            .srv_lookup(name)
            .await
            .map_err(|err| err.to_string())?;
        Ok(lookup
            .iter()
            .filter(|record| record.port() != 0)
            .map(|record| SrvRecord {
                host: record.target().to_utf8(),
                port: record.port(),
                priority: record.priority(),
                weight: record.weight(),
            })
            .collect())
    }
}

/// 解析后的连接目标；`via_srv` 用于日志与诊断。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedTarget {
    pub target: ServerTarget,
    pub via_srv: bool,
}

/// 解析用户录入的地址，并在域名场景下尝试 SRV。
///
/// IP 字面量/`localhost` 直接使用原目标。SRV 查询失败时回退到原目标，避免 DNS
/// 临时故障把本来可直连的地址也拖死。官方基础设施的最终拒绝发生在 `client`。
pub async fn resolve_target(
    profile: &ServerProfile,
    resolver: &dyn SrvResolver,
) -> Result<ResolvedTarget, ConnectError> {
    let original = profile.target()?;
    if is_ip_literal(&original.host) || original.host == "localhost" {
        return Ok(ResolvedTarget {
            target: original,
            via_srv: false,
        });
    }

    let query = format!("_ts3._udp.{}", original.host);
    let records = match resolver.lookup_srv(&query).await {
        Ok(records) => records,
        Err(_) => {
            return Ok(ResolvedTarget {
                target: original,
                via_srv: false,
            });
        }
    };

    let mut records: Vec<SrvRecord> = records
        .into_iter()
        .filter(|record| record.port != 0 && record.host != "." && !record.host.is_empty())
        .collect();
    records.sort_by_key(|record| (record.priority, u16::MAX - record.weight));
    let Some(record) = records.into_iter().next() else {
        return Ok(ResolvedTarget {
            target: original,
            via_srv: false,
        });
    };

    let target = parse_address(&format!("{}:{}", record.host, record.port))?;
    Ok(ResolvedTarget {
        target,
        via_srv: true,
    })
}

/// 用档案构造协议库的建连参数。resolver 固定为 deny-all，调用方无法替换。
pub fn client_options(profile: &ServerProfile, logger: Arc<dyn Logger>) -> ClientOptions {
    ClientOptions {
        logger,
        resolver: Some(Box::new(DenyResolver)),
        command_middleware: Vec::new(),
        event_middleware: Vec::new(),
        server_password: profile.server_password.clone(),
        default_channel: profile.default_channel.clone(),
        default_channel_password: profile.default_channel_password.clone(),
    }
}

/// 建连。这里是唯一的最终出口检查：目标必须是 IP/域名，且不能命中官方基础设施。
pub fn client(
    identity: Identity,
    profile: &ServerProfile,
    target: &ServerTarget,
    nickname: &str,
    logger: Arc<dyn Logger>,
) -> Result<Client, ConnectError> {
    ensure_allowed_target(&target.host)?;
    Ok(Client::new(
        identity,
        target.authority(),
        nickname.to_string(),
        client_options(profile, logger),
    ))
}

/// 文件传输主机必须与会话主机一致，端口由服务器下发。
pub fn check_transfer_host(target: &ServerTarget, host: &str) -> Result<(), ConnectError> {
    let expected = normalize_host(&target.host);
    let actual = normalize_host(host);
    if expected == actual {
        return Ok(());
    }
    Err(ConnectError::TransferHostMismatch { expected, actual })
}

#[cfg(test)]
mod tests {
    use super::*;
    use server::ServerRegistry;

    struct FakeResolver {
        result: Result<Vec<SrvRecord>, String>,
    }

    #[async_trait]
    impl SrvResolver for FakeResolver {
        async fn lookup_srv(&self, _name: &str) -> Result<Vec<SrvRecord>, String> {
            self.result.clone()
        }
    }

    fn profile(address: &str) -> ServerProfile {
        ServerRegistry::new()
            .register("home", address)
            .expect("档案应当可登记")
    }

    #[test]
    fn blocks_official_hosts_but_not_lookalikes() {
        for host in [
            FORBIDDEN_HOST_SUFFIXES[0].to_string(),
            format!("voice.{}", FORBIDDEN_HOST_SUFFIXES[0]),
            format!("named.{}", FORBIDDEN_HOST_SUFFIXES[2]),
            format!("a.{}", FORBIDDEN_HOST_SUFFIXES[1]),
        ] {
            assert!(forbidden_host(&host).is_some(), "{host}");
            assert!(matches!(
                ensure_allowed_target(&host),
                Err(ConnectError::Blocked { .. })
            ));
        }
        for host in [
            format!("{}.evil.net", FORBIDDEN_HOST_SUFFIXES[0]),
            format!("not{}", FORBIDDEN_HOST_SUFFIXES[0]),
            format!("{}.evil.net", FORBIDDEN_HOST_SUFFIXES[2]),
        ] {
            assert!(forbidden_host(&host).is_none(), "{host}");
        }
    }

    #[tokio::test]
    async fn deny_resolver_never_resolves() {
        let err = DenyResolver
            .resolve("ts.example.com", None)
            .await
            .unwrap_err();
        assert!(matches!(err, ProtocolError::Teamspeak(_)));
    }

    #[tokio::test]
    async fn srv_target_replaces_the_domain() {
        let resolver = FakeResolver {
            result: Ok(vec![SrvRecord {
                host: "voice.example.com".into(),
                port: 10000,
                priority: 10,
                weight: 5,
            }]),
        };
        let resolved = resolve_target(&profile("ts.example.com"), &resolver)
            .await
            .unwrap();
        assert!(resolved.via_srv);
        assert_eq!(resolved.target.host, "voice.example.com");
        assert_eq!(resolved.target.port, 10000);
    }

    #[test]
    fn transfer_host_must_match_session_host() {
        let target = ServerTarget {
            host: "ts.example.com".into(),
            port: 9987,
        };
        assert!(check_transfer_host(&target, "TS.Example.COM.").is_ok());
        assert!(matches!(
            check_transfer_host(&target, "evil.net"),
            Err(ConnectError::TransferHostMismatch { .. })
        ));
    }
}
