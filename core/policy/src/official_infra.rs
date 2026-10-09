//! 官方基础设施清单。
//!
//! 本文件是全仓库官方域名与服务端点的唯一归属地：`tool/audit_policy.sh` 在 CI 中
//! 保证这些字面量不出现在其他源码文件里。新增条目必须同时补 `lib.rs` 的测试。

/// 禁连的官方主机后缀，按「等于该域或以 `.` 加该域结尾」匹配，避免子串误判。
pub const FORBIDDEN_HOST_SUFFIXES: &[&str] =
    &["teamspeak.com", "teamspeak-systems.com", "myteamspeak.com"];

/// 客户端不得发起任何请求的官方服务端点。
///
/// 昵称解析端点目前被两道机制挡住：策略层拒绝裸昵称，协议层用 deny-all 解析器
/// 替掉 tsclient-rs 自带的 SRV/TSDNS/昵称解析。此处保留清单供审计与回归检查。
pub const OFFICIAL_SERVICE_URLS: &[&str] = &["named.myteamspeak.com"];
