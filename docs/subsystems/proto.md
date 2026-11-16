# 子系统契约 — core/proto

本文定义 `core/proto` 的职责、关键调用序列与不变量。

## 职责

- 对用户输入的域名执行异步 DNS SRV（`_ts3._udp.<domain>`）与 IPv4 A 记录解析，产出最终 IPv4 `SocketAddr`（`ResolvedTarget.addr`）。
- 维护全仓唯一的官方基础设施屏蔽清单 `FORBIDDEN_HOST_SUFFIXES`，在建连与 SRV 重定向阶段执行统一拦截。
- 提供 `DenyResolver` 彻底阻断 `tsclient-rs` 内部对 `named.myteamspeak.com` 的默认回退查找，并绕开底层 `tokio::net::lookup_host`。
- 封装客户端工厂 `client()` 与文件传输主机检查 `check_transfer_host()`。
- 维护 Android 活跃网络 DNS 上游列表（由宿主 `ConnectivityManager` 经 FFI `set_android_dns_servers` 注入），在系统 DNS 为空或查询异常时回退 `223.5.5.5` 与 `1.1.1.1`；桌面端使用 `tokio_from_system_conf()`。

## 关键路径与序列

1. **入口与边界校验**：收到 `ServerProfile` → 通过 `profile.target()` 校验格式并拒绝裸昵称 → 调用 `ensure_allowed_target` 拦截官方域名；IPv4 字面量与 `localhost`（映射为 `127.0.0.1`）直接产出 `SocketAddr`，IPv6 字面量直接返回 `ConnectError::Address`。
2. **SRV 查询与二次拦截**：域名输入调用 `HickoryDnsResolver` 查询 `_ts3._udp.<host>` → 若因非 `NoRecordsFound` 异常失败，先通过 `tracing::warn!` 记录错误再回退到原主机名；命中 SRV 时用 `parse_address` 校验并再次执行 `ensure_allowed_target`。
3. **IPv4 一步到位解析**：无论是否命中 SRV，统一通过 `HickoryDnsResolver::lookup_ipv4` 查询 A 记录生成 IPv4 `SocketAddr`；未返回 IPv4 或查询失败立即返回 `ConnectError::Dns`。Android 先查宿主同步的 DNS 上游（2 秒超时），空列表或非 `NoRecordsFound` 异常（以及 A 记录失败）时自动回退至 `ANDROID_FALLBACK_DNS`。
4. **安全 Client 实例构建**：通过 `proto::client()` 再次核验原始主机与解析后目标均不在 `FORBIDDEN_HOST_SUFFIXES` 内，将解析出的 IPv4 `SocketAddr` 传给 `tsclient_rs::Client::new`，并注入 `DenyResolver` 拦截协议库内部任何隐式域名查找；会话层的 `transfer_target` 同样复用该 IPv4 地址执行 TCP 文件传输。

## 不变量

- `FORBIDDEN_HOST_SUFFIXES` 是全仓唯一的官方主机屏蔽名单；UI、FFI、图片抓取与会话层均不得复制维护私有后缀列表。
- `DenyResolver` 恒定拒绝任何解析请求，彻底根除通过官方昵称查询接口泄露用户网络行为的可能。
- 任何发往 TeamSpeak UDP 端口的建连操作前，原始主机与 SRV 重定向目标都必须通过本子系统的官方主机检查并解析为 IPv4 `SocketAddr`。

## 相关决策

- [连接边界架构设计](../../.agents/notes/implemented/architecture/2026-10-18-connection-boundary.md)
