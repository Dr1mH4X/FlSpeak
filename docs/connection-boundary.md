# 连接边界

FlSpeak 的 TeamSpeak 连接只面向 TeamSpeak 服务器。边界由录入格式和最终建连出口各承担一件事，不在 UI、FFI 或存储层重复审查。版本更新检查是独立的固定主机旁路，规则见下方。

## 规则

- 用户只能录入 IP、域名或 `localhost`（可带端口），裸昵称不接受。
- 不实现 myTeamSpeak 账号登录、云同步、官方媒体上传或附件下载。
- `named.myteamspeak.com/lookup` 不使用。裸昵称在 `server::parse_address` 就被拒绝，`proto::DenyResolver` 再挡住 tsclient-rs 自带的 discovery。
- SRV（`_ts3._udp.<domain>`）是标准 DNS，可以解析。原始域名与 SRV 目标均在 `core/proto` 检查官方主机清单并由 `hickory-resolver` 解析为 IPv4 `SocketAddr` 后再交给 `proto::client` 建连，命中清单直接拒绝。
- 官方主机清单只在 `core/proto` 的 `FORBIDDEN_HOST_SUFFIXES` 维护；连接和图片抓取共用这一份，不在 UI、FFI 或存储层复制。
- 第三方图片 URL 仍然经过 `core/session/src/media/images.rs` 的 SSRF 检查（只允许 http/https、公网地址、有限重定向和大小）；官方媒体和 `ts.file.myts` 附件不访问。
- 文件传输主机必须等于会话主机（`proto::check_transfer_host`）。
- 版本更新检查只访问 `https://api.github.com/repos/Dr1mH4X/FlSpeak/releases`：固定主机与路径、不跟随重定向、8s 超时、4 MiB 响应上限、失败静默、不内置 token。请求携带 `User-Agent`、`Accept: application/vnd.github+json` 与 `X-GitHub-Api-Version: 2022-11-28`。
- 放宽边界是一次需要留痕的决策：先在 `.agents/notes/` 按[笔记规则](../.agents/notes/AGENTS.md)写清理由与残余风险，并在同一改动里补上相似域名与目标重定向的测试。

## 域名解析

- 只做标准 DNS：域名的 `_ts3._udp.<domain>` SRV 与 IPv4 A 记录；IPv4 字面量与 `localhost`（映射为 `127.0.0.1`）直接产出 `SocketAddr`，IPv6 字面量与裸昵称直接拒绝。SRV 查询异常时先记录警告再回退到档案主机，A 记录解析失败直接报 `ConnectError::Dns`，不交给协议库做系统解析。
- 桌面端 resolver 取系统 DNS 配置（`tokio_from_system_conf()`）。Android 的活跃网络 DNS 上游由宿主 `ConnectivityManager` 经 FFI `set_android_dns_servers` 注入，查询超时 2 秒；系统 DNS 为空或查询异常时回退到 `ANDROID_FALLBACK_DNS` 的 `223.5.5.5` 与 `1.1.1.1`。
- `proto::DenyResolver` 恒定拒绝任何解析请求，既挡住 tsclient-rs 自带的官方昵称 discovery，也绕开底层 `tokio::net::lookup_host`。

## 代码位置

| 位置 | 职责 |
| --- | --- |
| `core/server/src/lib.rs` | IP/域名解析、档案登记；拒绝空地址、协议前缀、裸昵称和非法端口 |
| `core/proto/src/lib.rs` | SRV 解析、`DenyResolver`、最终官方主机检查和建连 |
| `core/session/src/media/images.rs` | 图片 URL 的 host 检查与 SSRF 防护 |
| `core/session/src/actor/` | 连接流程、重连和文件传输主机校验（`connect.rs`、`transfers.rs`） |
| `core/session/src/updates.rs` | 固定 GitHub Releases 主机的版本检查、SemVer 比较、6 小时缓存与失败回退 |

## 验证

```sh
cd plugins/flspeak_ffi/rust
cargo test -p server -p proto
```

涉及最终连接边界时，再跑完整的 workspace 检查和 Flutter analyze。
