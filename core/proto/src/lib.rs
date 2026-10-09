//! tsclient-rs 的窄封装。
//!
//! 这一层的职责只有一个：让协议库无法自行决定连到哪里。连接目标由 `policy`
//! 校验后作为字面量交给协议库，并把协议库自带的地址解析器换成 deny-all 版本，
//! 使 SRV、TSDNS、昵称解析三条重定向路径都不可达。

use std::sync::Arc;

use async_trait::async_trait;
use tsclient_rs::{
    AbortSignal, AddrResolver, Client, ClientOptions, Error as ProtocolError, Identity, Logger,
    ResolvedAddr,
};

pub use policy::{
    ApprovedTarget, PolicyError, ServerProfile, ServerRegistry, assert_transfer_host,
    validate_address,
};

#[derive(Debug, thiserror::Error)]
pub enum ConnectError {
    #[error(transparent)]
    Policy(#[from] PolicyError),

    #[error("{0}")]
    Protocol(String),
}

/// 拒绝一切地址解析请求。
///
/// tsclient-rs 的 SRV / TSDNS / 昵称解析都从这个入口进入。它自身在解析失败时会回退到
/// 原地址继续连接，所以这个解析器只算纵深防御：真正的闸门是建连前的 `validate_address`。
/// 之所以仍然要替换掉默认解析器，是因为默认解析器一旦被构造出来，昵称查询就会真的向
/// 官方接口发出请求。
pub struct DenyResolver;

#[async_trait]
impl AddrResolver for DenyResolver {
    async fn resolve(
        &self,
        addr: &str,
        _signal: Option<&AbortSignal>,
    ) -> Result<Vec<ResolvedAddr>, ProtocolError> {
        Err(ProtocolError::Teamspeak(format!(
            "address resolution is disabled by policy: {addr}"
        )))
    }
}

/// 校验连接目标，不通过即拒绝。
pub fn approve(address: &str) -> Result<ApprovedTarget, ConnectError> {
    Ok(validate_address(address)?)
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

/// 建连。目标地址来自档案，档案在连接前重新过一遍策略。
pub fn client(
    identity: Identity,
    profile: &ServerProfile,
    nickname: &str,
    logger: Arc<dyn Logger>,
) -> Result<Client, ConnectError> {
    let target = profile.target()?;
    Ok(Client::new(
        identity,
        target.authority(),
        nickname.to_string(),
        client_options(profile, logger),
    ))
}

/// 文件传输主机必须与会话主机一致，端口由服务器下发。
pub fn check_transfer_host(target: &ApprovedTarget, host: &str) -> Result<(), ConnectError> {
    Ok(assert_transfer_host(&target.host, host)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use policy::FORBIDDEN_HOST_SUFFIXES;

    /// 从策略层的单一事实来源拼一个官方域名：本 crate 不留官方域名字面量，
    /// `tool/audit_policy.sh` 才能保持“官方域名只出现在策略层”这条硬规则。
    fn forbidden_host() -> String {
        format!("voice.{}", FORBIDDEN_HOST_SUFFIXES[0])
    }

    #[test]
    fn approve_rejects_official_infrastructure() {
        assert!(matches!(
            approve(&forbidden_host()),
            Err(ConnectError::Policy(PolicyError::OfficialInfra { .. }))
        ));
        assert_eq!(
            approve("ts.example.com:9987").unwrap().host,
            "ts.example.com"
        );
    }

    #[tokio::test]
    async fn deny_resolver_never_resolves() {
        let err = DenyResolver
            .resolve("ts.example.com", None)
            .await
            .unwrap_err();
        assert!(matches!(err, ProtocolError::Teamspeak(_)));
    }

    #[test]
    fn transfer_host_is_pinned_to_session_host() {
        let target = approve("ts.example.com").unwrap();
        assert!(check_transfer_host(&target, "TS.Example.COM.").is_ok());
        assert!(check_transfer_host(&target, &forbidden_host()).is_err());
    }
}
