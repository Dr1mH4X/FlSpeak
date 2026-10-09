# 合规

## 为什么

TeamSpeak 官方客户端与官方服务端的许可协议对第三方客户端连接官方基础设施有明确限制。
本项目的定位是**自托管客户端**：只连你自己（或你信任的运营方）部署的 TeamSpeak 服务器，
完全不接触官方基础设施。这不是免责声明式的声明，而是代码层面的硬约束。

## 禁止出现的行为

| 行为 | 拦截点 |
| --- | --- |
| 连接 `teamspeak.com` / `teamspeak-systems.com` / `myteamspeak.com` 及其子域 | `policy::validate_address`（T1） |
| 访问官方昵称解析端点 `named.myteamspeak.com` | 拒绝裸昵称 + deny-all 解析器 |
| 通过 SRV / TSDNS 重定向到别处 | 只传字面 `host:port`，解析路径不可达 |
| 从目录或订阅源自动导入服务器 | 不存在这类接口 |
| 文件传输指向第三方主机 | `proto::check_transfer_host`（主机必须等于会话主机） |
| 连接未经登记的地址 | 连接命令只接受档案 id（T2） |

## 三层防线

1. **录入时（T1）**：地址必须是 host 或 host[:port]；拒绝裸昵称、非法端口、
   带 scheme 的输入；拒绝禁连域名及其子域（用“等于或 `.` 结尾”匹配，
   `notteamspeak.com`、`teamspeak.com.evil.net` 这类相似域名不会被误判，也不会被放过）。
2. **连接时（T2 + proto）**：连接目标只能从档案里取；`proto::client` 会再校验
   一次，并强制注入 `DenyResolver`——一个只会返回错误的 `AddrResolver`。
3. **审计**：`tool/audit_policy.sh` 在 CI 里扫描源码与配置，官方域名字面量只要出现在
   `core/policy` 之外就失败。需要官方域名做测试夹具时，从
   `policy::FORBIDDEN_HOST_SUFFIXES` 拼。

## 为什么不用“校验重定向目标”的方案

tsclient-rs 的 `resolve_addr_impl` 在解析器返回 `Err` 时会**吞掉错误并回退到原始地址**
（`src/client.rs:978-987`），而且 `Resolver` trait 没有导出，策略层无法替换。与其在上游
行为上做脆弱的假设，不如让重定向路径结构上无法触发：传字面地址 + deny-all 解析器。

## 跑审计

```sh
bash tool/audit_policy.sh
cd plugins/flspeak_ffi/rust && cargo test -p policy -p proto
```

## 改动策略

走 `.agents/skills/policy-change/SKILL.md` 的流程：先写决策记录，再改
`core/policy/src/official_infra.rs` 或校验逻辑，补相似域名测试，最后跑闸门。

## 上游候选改动（中性、纯增量）

tsclient-rs 不接受策略逻辑（它要求与 teamspeak-js 参考结构对齐），但这两条是中性的：

- `VoiceData` 暴露 `packet_id`：接收路径现在丢掉了包号（只保留 client_id 与 codec），
  客户端无法做语音重排序与抖动缓冲。
- 导出 `discovery::Resolver`：让第三方客户端可以替换解析策略，而不是复制 transport 代码。