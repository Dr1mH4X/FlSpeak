# Agent Note: 连接边界收敛为最终出口

Status: implemented

## Problem

原 `core/policy` 同时承载服务器档案、地址解析、禁连清单、T1/T2 登记和 `DenyResolver`。
录入、连接、FFI 和图片抓取各自重复引用 policy，改一处边界需要同步多处审查，且
`ServerProfile` 这类纯数据模型被误当成合规代码。

## Decision

- `ServerProfile`、`ServerRegistry`、地址解析和默认端口归 `core/server`。
- `core/server` 只接受 IP、域名、`localhost` 和可选端口；裸昵称直接拒绝，因此正常录入
  路径不会触发 `named.myteamspeak.com/lookup`。
- 官方主机清单只放在 `core/proto` 的 `FORBIDDEN_HOST_SUFFIXES`。
- `proto::client` 是唯一最终出口检查：连接前检查一次最终目标；SRV 返回的目标也经过这里。
  `core/session` 的图片抓取复用同一份 host 检查。
- SRV 是标准 DNS，`proto::resolve_target` 继续解析；查询失败回退档案字面地址。
- `DenyResolver` 保留，继续挡住 tsclient-rs 自带的 discovery。
- 文件传输主机必须等于会话主机，检查放在 `proto::check_transfer_host`。
- 不实现 myTeamSpeak 账号、云同步、官方媒体上传或附件下载。

## Alternatives considered

- **保留 T1/T2 分层**：同一事实在录入、连接和 FFI 重复出现，改边界容易漏。
- **只靠前端限制**：FFI、`servers.json` 和 SRV 结果都能绕过前端。
- **删除最终检查**：self-hosted-only 会退化成文档约定，而且 `DenyResolver` 一旦漏掉，
  官方昵称解析就会重新可用。
- **整体删除 `core/policy` 而不迁移档案模型**：会破坏 `servers.json` 和连接流程。

## Consequences

- 连接边界只在一个函数和一个清单维护；UI 只负责输入格式提示。
- 官方主机检查覆盖最终连接目标、SRV 结果和图片 URL；拒绝类失败只有 `InvalidAddress` 与
  `BlockedAddress` 两种，FFI 绑定与之一致。
- 边界全貌见 `docs/connection-boundary.md`。

## Testing

- `cargo test -p server -p proto`
- `cargo check --workspace --all-features`
