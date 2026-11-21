//! tsclient-rs 的窄封装。
//!
//! `resolve_target` 负责域名 SRV（`_ts3._udp.<domain>`）与 IPv4 A 记录解析，
//! 产出最终 `SocketAddr` 交给 `client`；tsclient-rs 自己的 discovery 仍然被
//! `DenyResolver` 挡住，因此裸昵称不会请求 `named.myteamspeak.com/lookup`。

use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::{Arc, Mutex, OnceLock, RwLock};
#[cfg(target_os = "android")]
use std::time::Duration;

use async_trait::async_trait;
use hickory_resolver::TokioAsyncResolver;
#[cfg(target_os = "android")]
use hickory_resolver::config::{
    LookupIpStrategy, NameServerConfigGroup, ResolverConfig, ResolverOpts,
};
use hickory_resolver::error::{ResolveError, ResolveErrorKind};
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

/// Android 在系统 DNS 列表为空或查询异常时使用的备用公共上游。
pub const ANDROID_FALLBACK_DNS: &[IpAddr] = &[
    IpAddr::V4(Ipv4Addr::new(223, 5, 5, 5)),
    IpAddr::V4(Ipv4Addr::new(1, 1, 1, 1)),
];

#[cfg(target_os = "android")]
const ANDROID_DNS_TIMEOUT: Duration = Duration::from_secs(2);

static ANDROID_DNS_SERVERS: OnceLock<RwLock<Vec<IpAddr>>> = OnceLock::new();

fn android_dns_store() -> &'static RwLock<Vec<IpAddr>> {
    ANDROID_DNS_SERVERS.get_or_init(|| RwLock::new(Vec::new()))
}

fn is_usable_dns_ip(ip: IpAddr) -> bool {
    if ip.is_unspecified() || ip.is_multicast() {
        return false;
    }
    match ip {
        IpAddr::V4(_) => true,
        // 链路本地 IPv6（fe80::/10）没有有效作用域 ID 时无法路由，过滤掉以免拖慢解析。
        IpAddr::V6(v6) => (v6.segments()[0] & 0xffc0) != 0xfe80,
    }
}

/// 解析并保存由宿主网络栈同步过来的 DNS 服务器 IP 列表（仅 Android 生效）。
pub fn parse_dns_server_ips(servers: &[String]) -> Vec<IpAddr> {
    let mut parsed = Vec::new();
    for raw in servers {
        let trimmed = raw.trim();
        if let Ok(ip) = trimmed.parse::<IpAddr>()
            && is_usable_dns_ip(ip)
            && !parsed.contains(&ip)
        {
            parsed.push(ip);
        }
    }
    parsed
}

/// 更新 Android 当前活跃网络的 DNS 上游列表。
pub fn set_android_dns_servers(servers: &[String]) {
    let parsed = parse_dns_server_ips(servers);
    let mut guard = android_dns_store()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if *guard != parsed {
        tracing::info!(target: "proto", servers = ?parsed, "updated Android DNS servers");
        *guard = parsed;
    }
}

/// 读取当前记录的 Android DNS 上游列表。
pub fn android_dns_servers() -> Vec<IpAddr> {
    android_dns_store()
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone()
}

#[derive(Debug, thiserror::Error)]
pub enum ConnectError {
    #[error(transparent)]
    Address(#[from] AddressError),

    #[error("refusing to connect to official infrastructure {host} (matched {matched})")]
    Blocked { host: String, matched: String },

    #[error("DNS resolution for {host} failed: {reason}")]
    Dns { host: String, reason: String },

    #[error("file transfer host {actual} does not match session host {expected}")]
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

/// SRV 查询失败原因，区分权威空记录与传输/配置异常。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SrvLookupError {
    NoRecords,
    Failed(String),
}

#[async_trait]
pub trait DnsResolver: Send + Sync {
    async fn lookup_srv(&self, name: &str) -> Result<Vec<SrvRecord>, SrvLookupError>;
    async fn lookup_ipv4(&self, host: &str) -> Result<Vec<Ipv4Addr>, String>;
}

#[cfg(target_os = "android")]
fn build_android_resolver(ips: &[IpAddr]) -> TokioAsyncResolver {
    let name_servers = NameServerConfigGroup::from_ips_clear(ips, 53, true);
    let config = ResolverConfig::from_parts(None, Vec::new(), name_servers);
    let mut opts = ResolverOpts::default();
    opts.timeout = ANDROID_DNS_TIMEOUT;
    opts.attempts = 1;
    opts.try_tcp_on_error = true;
    opts.ip_strategy = LookupIpStrategy::Ipv4Only;
    opts.use_hosts_file = false;
    TokioAsyncResolver::tokio(config, opts)
}

fn is_no_records(err: &ResolveError) -> bool {
    matches!(err.kind(), ResolveErrorKind::NoRecordsFound { .. })
}

fn map_srv_records(lookup: hickory_resolver::lookup::SrvLookup) -> Vec<SrvRecord> {
    lookup
        .iter()
        .filter(|record| record.port() != 0)
        .map(|record| SrvRecord {
            host: record.target().to_utf8(),
            port: record.port(),
            priority: record.priority(),
            weight: record.weight(),
        })
        .collect()
}

fn map_ipv4_records(lookup: hickory_resolver::lookup::Ipv4Lookup) -> Vec<Ipv4Addr> {
    lookup.iter().map(|record| record.0).collect()
}

async fn query_ipv4(resolver: &TokioAsyncResolver, host: &str) -> Result<Vec<Ipv4Addr>, String> {
    let lookup = resolver
        .ipv4_lookup(host)
        .await
        .map_err(|err| err.to_string())?;
    let ips = map_ipv4_records(lookup);
    if ips.is_empty() {
        return Err("no IPv4 A records returned".into());
    }
    Ok(ips)
}

#[cfg(target_os = "android")]
struct CachedResolver {
    ips: Vec<IpAddr>,
    resolver: TokioAsyncResolver,
}

/// 基于 `hickory-resolver` 的 DNS 解析器。
///
/// Android 使用由宿主网络栈注入的 DNS 服务器，空列表或传输/超时异常时回退到
/// [`ANDROID_FALLBACK_DNS`]；桌面端沿用 `tokio_from_system_conf()`。
#[derive(Default)]
pub struct HickoryDnsResolver {
    #[cfg(target_os = "android")]
    cached_system: Mutex<Option<CachedResolver>>,
    #[cfg(target_os = "android")]
    cached_fallback: OnceLock<TokioAsyncResolver>,
    #[cfg(not(target_os = "android"))]
    cached_desktop: Mutex<Option<TokioAsyncResolver>>,
}

impl HickoryDnsResolver {
    pub fn new() -> Self {
        Self::default()
    }

    #[cfg(target_os = "android")]
    fn system_resolver(&self) -> Option<TokioAsyncResolver> {
        let ips = android_dns_servers();
        if ips.is_empty() {
            return None;
        }
        let mut guard = self
            .cached_system
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some(cached) = guard.as_ref()
            && cached.ips == ips
        {
            return Some(cached.resolver.clone());
        }
        let resolver = build_android_resolver(&ips);
        *guard = Some(CachedResolver {
            ips,
            resolver: resolver.clone(),
        });
        Some(resolver)
    }

    #[cfg(target_os = "android")]
    fn fallback_resolver(&self) -> &TokioAsyncResolver {
        self.cached_fallback
            .get_or_init(|| build_android_resolver(ANDROID_FALLBACK_DNS))
    }

    #[cfg(not(target_os = "android"))]
    fn desktop_resolver(&self) -> Result<TokioAsyncResolver, String> {
        let mut guard = self
            .cached_desktop
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some(resolver) = guard.as_ref() {
            return Ok(resolver.clone());
        }
        let resolver =
            TokioAsyncResolver::tokio_from_system_conf().map_err(|err| err.to_string())?;
        *guard = Some(resolver.clone());
        Ok(resolver)
    }
}

#[async_trait]
impl DnsResolver for HickoryDnsResolver {
    async fn lookup_srv(&self, name: &str) -> Result<Vec<SrvRecord>, SrvLookupError> {
        #[cfg(target_os = "android")]
        {
            if let Some(resolver) = self.system_resolver() {
                match resolver.srv_lookup(name).await {
                    Ok(lookup) => return Ok(map_srv_records(lookup)),
                    Err(err) if is_no_records(&err) => return Err(SrvLookupError::NoRecords),
                    Err(err) => {
                        tracing::warn!(
                            target: "proto",
                            query = %name,
                            error = %err,
                            "system DNS SRV lookup failed; retrying fallback upstreams"
                        );
                    }
                }
            }
            match self.fallback_resolver().srv_lookup(name).await {
                Ok(lookup) => Ok(map_srv_records(lookup)),
                Err(err) if is_no_records(&err) => Err(SrvLookupError::NoRecords),
                Err(err) => Err(SrvLookupError::Failed(err.to_string())),
            }
        }
        #[cfg(not(target_os = "android"))]
        {
            let resolver = self.desktop_resolver().map_err(SrvLookupError::Failed)?;
            match resolver.srv_lookup(name).await {
                Ok(lookup) => Ok(map_srv_records(lookup)),
                Err(err) if is_no_records(&err) => Err(SrvLookupError::NoRecords),
                Err(err) => Err(SrvLookupError::Failed(err.to_string())),
            }
        }
    }

    async fn lookup_ipv4(&self, host: &str) -> Result<Vec<Ipv4Addr>, String> {
        #[cfg(target_os = "android")]
        {
            if let Some(resolver) = self.system_resolver() {
                match query_ipv4(&resolver, host).await {
                    Ok(ips) => return Ok(ips),
                    Err(err) => {
                        tracing::warn!(
                            target: "proto",
                            host = %host,
                            error = %err,
                            "system DNS A lookup failed; retrying fallback upstreams"
                        );
                    }
                }
            }
            query_ipv4(self.fallback_resolver(), host).await
        }
        #[cfg(not(target_os = "android"))]
        {
            let resolver = self.desktop_resolver()?;
            query_ipv4(&resolver, host).await
        }
    }
}

/// 解析后的连接目标；`addr` 为最终用于建连的 IPv4 `SocketAddr`。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedTarget {
    pub target: ServerTarget,
    pub addr: SocketAddr,
    pub via_srv: bool,
}

async fn resolve_ipv4_socket(
    target: &ServerTarget,
    resolver: &dyn DnsResolver,
) -> Result<SocketAddr, ConnectError> {
    if let Ok(ipv4) = target.host.parse::<Ipv4Addr>() {
        return Ok(SocketAddr::new(IpAddr::V4(ipv4), target.port));
    }
    if is_ip_literal(&target.host) {
        return Err(AddressError::Malformed(format!(
            "IPv6 addresses are not supported: {}",
            target.host
        ))
        .into());
    }
    if target.host == "localhost" {
        return Ok(SocketAddr::new(
            IpAddr::V4(Ipv4Addr::LOCALHOST),
            target.port,
        ));
    }
    if !target.host.contains('.') {
        return Err(AddressError::HostRequired {
            input: target.host.clone(),
        }
        .into());
    }

    let ips = resolver
        .lookup_ipv4(&target.host)
        .await
        .map_err(|reason| ConnectError::Dns {
            host: target.host.clone(),
            reason,
        })?;
    let ip = ips.into_iter().next().ok_or_else(|| ConnectError::Dns {
        host: target.host.clone(),
        reason: "no IPv4 A records returned".into(),
    })?;
    Ok(SocketAddr::new(IpAddr::V4(ip), target.port))
}

/// 解析用户录入的地址：先拦截裸昵称/非 IPv4 与官方域名，再查 SRV 并一步解析为 IPv4 `SocketAddr`。
pub async fn resolve_target(
    profile: &ServerProfile,
    resolver: &dyn DnsResolver,
) -> Result<ResolvedTarget, ConnectError> {
    let original = profile.target()?;
    ensure_allowed_target(&original.host)?;

    if is_ip_literal(&original.host) || original.host == "localhost" {
        let addr = resolve_ipv4_socket(&original, resolver).await?;
        return Ok(ResolvedTarget {
            target: original,
            addr,
            via_srv: false,
        });
    }

    let query = format!("_ts3._udp.{}", original.host);
    let srv_target = match resolver.lookup_srv(&query).await {
        Ok(records) => {
            let mut records: Vec<SrvRecord> = records
                .into_iter()
                .filter(|record| record.port != 0 && record.host != "." && !record.host.is_empty())
                .collect();
            records.sort_by_key(|record| (record.priority, u16::MAX - record.weight));
            if let Some(record) = records.into_iter().next() {
                let candidate = parse_address(&format!("{}:{}", record.host, record.port))?;
                ensure_allowed_target(&candidate.host)?;
                Some(candidate)
            } else {
                None
            }
        }
        Err(SrvLookupError::NoRecords) => None,
        Err(SrvLookupError::Failed(err)) => {
            tracing::warn!(
                target: "proto",
                query = %query,
                error = %err,
                "SRV lookup failed, falling back to host"
            );
            None
        }
    };

    let (target, via_srv) = match srv_target {
        Some(target) => (target, true),
        None => (original, false),
    };
    let addr = resolve_ipv4_socket(&target, resolver).await?;
    Ok(ResolvedTarget {
        target,
        addr,
        via_srv,
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

/// 建连。这里是唯一的最终出口检查：目标必须通过官方基础设施拦截，并以解析后的 IPv4 `SocketAddr` 建连。
pub fn client(
    identity: Identity,
    profile: &ServerProfile,
    resolved: &ResolvedTarget,
    nickname: &str,
    logger: Arc<dyn Logger>,
) -> Result<Client, ConnectError> {
    ensure_allowed_target(&profile.host)?;
    ensure_allowed_target(&resolved.target.host)?;
    Ok(Client::new(
        identity,
        resolved.addr.to_string(),
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
    use std::collections::HashMap;

    struct FakeResolver {
        srv: Result<Vec<SrvRecord>, SrvLookupError>,
        a: HashMap<String, Result<Vec<Ipv4Addr>, String>>,
    }

    #[async_trait]
    impl DnsResolver for FakeResolver {
        async fn lookup_srv(&self, _name: &str) -> Result<Vec<SrvRecord>, SrvLookupError> {
            self.srv.clone()
        }

        async fn lookup_ipv4(&self, host: &str) -> Result<Vec<Ipv4Addr>, String> {
            self.a
                .get(host)
                .cloned()
                .unwrap_or_else(|| Err(format!("missing A record for {host}")))
        }
    }

    fn profile(address: &str) -> ServerProfile {
        ServerRegistry::new()
            .register("home", address)
            .expect("the profile should be registrable")
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
    async fn srv_target_replaces_domain_and_resolves_ipv4_socket() {
        let resolver = FakeResolver {
            srv: Ok(vec![SrvRecord {
                host: "voice.example.com".into(),
                port: 10000,
                priority: 10,
                weight: 5,
            }]),
            a: HashMap::from([(
                "voice.example.com".into(),
                Ok(vec![Ipv4Addr::new(203, 0, 113, 10)]),
            )]),
        };
        let resolved = resolve_target(&profile("ts.example.com"), &resolver)
            .await
            .unwrap();
        assert!(resolved.via_srv);
        assert_eq!(resolved.target.host, "voice.example.com");
        assert_eq!(resolved.target.port, 10000);
        assert_eq!(
            resolved.addr,
            SocketAddr::new(IpAddr::V4(Ipv4Addr::new(203, 0, 113, 10)), 10000)
        );
    }

    #[tokio::test]
    async fn srv_error_falls_back_to_host_and_resolves_ipv4() {
        let resolver = FakeResolver {
            srv: Err(SrvLookupError::Failed("timed out".into())),
            a: HashMap::from([(
                "ts.example.com".into(),
                Ok(vec![Ipv4Addr::new(203, 0, 113, 20)]),
            )]),
        };
        let resolved = resolve_target(&profile("ts.example.com"), &resolver)
            .await
            .unwrap();
        assert!(!resolved.via_srv);
        assert_eq!(resolved.target.host, "ts.example.com");
        assert_eq!(
            resolved.addr,
            SocketAddr::new(IpAddr::V4(Ipv4Addr::new(203, 0, 113, 20)), 9987)
        );
    }

    #[tokio::test]
    async fn blocks_srv_redirect_to_official_host_before_ip_resolution() {
        let resolver = FakeResolver {
            srv: Ok(vec![SrvRecord {
                host: format!("voice.{}", FORBIDDEN_HOST_SUFFIXES[0]),
                port: 9987,
                priority: 0,
                weight: 0,
            }]),
            a: HashMap::new(),
        };
        let err = resolve_target(&profile("evil.example.net"), &resolver)
            .await
            .unwrap_err();
        assert!(matches!(err, ConnectError::Blocked { .. }));
    }

    #[tokio::test]
    async fn rejects_ipv6_and_missing_a_record() {
        let resolver = FakeResolver {
            srv: Err(SrvLookupError::NoRecords),
            a: HashMap::from([("v6only.example.com".into(), Err("no A records".into()))]),
        };
        let ipv6_err = resolve_target(&profile("[::1]:9987"), &resolver)
            .await
            .unwrap_err();
        assert!(matches!(ipv6_err, ConnectError::Address(_)));

        let dns_err = resolve_target(&profile("v6only.example.com"), &resolver)
            .await
            .unwrap_err();
        assert!(matches!(dns_err, ConnectError::Dns { .. }));
    }

    #[test]
    fn parse_dns_server_ips_filters_link_local_and_dedups() {
        let parsed = parse_dns_server_ips(&[
            "fe80::667:61ff:feb4:1b18%wlan0".into(),
            "fe80::1".into(),
            "0.0.0.0".into(),
            "223.6.6.6".into(),
            " 223.6.6.6 ".into(),
            "119.29.29.29".into(),
            "2400:3200::1".into(),
        ]);
        assert_eq!(
            parsed,
            vec![
                IpAddr::V4(Ipv4Addr::new(223, 6, 6, 6)),
                IpAddr::V4(Ipv4Addr::new(119, 29, 29, 29)),
                IpAddr::V6("2400:3200::1".parse().unwrap()),
            ]
        );
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
