# 连接边界

FlSpeak 只面向 TeamSpeak 服务器。边界由录入格式和最终建连出口各承担一件事，
不在 UI、FFI 或存储层重复审查。

## 规则

- 用户只能录入 IP、域名或 `localhost`（可带端口），裸昵称不接受。
- 不实现 myTeamSpeak 账号登录、云同步、官方媒体上传或附件下载。
- `named.myteamspeak.com/lookup` 不使用。裸昵称在 `server::parse_address` 就被拒绝，
  `proto::DenyResolver` 再挡住 tsclient-rs 自带的 discovery。
- SRV（`_ts3._udp.<domain>`）是标准 DNS，可以解析。最终目标在
  `proto::client` 建连前检查一次，命中官方主机清单直接拒绝。
- 官方主机清单只在 `core/proto` 的 `FORBIDDEN_HOST_SUFFIXES` 维护；连接和图片抓取
  共用这一份，不在 UI、FFI 或存储层复制。
- 第三方图片 URL 仍然经过 `images.rs` 的 SSRF 检查（只允许 http/https、公网地址、
  有限重定向和大小）；官方媒体和 `ts.file.myts` 附件不访问。
- 文件传输主机必须等于会话主机（`proto::check_transfer_host`）。

## 代码位置

| 位置 | 职责 |
| --- | --- |
| `core/server/src/lib.rs` | IP/域名解析、档案登记；拒绝空地址、协议前缀、裸昵称和非法端口 |
| `core/proto/src/lib.rs` | SRV 解析、`DenyResolver`、最终官方主机检查和建连 |
| `core/session/src/images.rs` | 图片 URL 的 host 检查与 SSRF 防护 |
| `core/session/src/actor.rs` | 连接流程、重连和文件传输主机校验 |

## 验证

```sh
cd plugins/flspeak_ffi/rust
cargo test -p server -p proto
```

涉及最终连接边界时，再跑完整的 workspace 检查和 Flutter analyze。
