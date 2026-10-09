# 决策记录：合规策略在 Rust 层强制实施

日期：2026-10-08
状态：已实施

## 背景

要求是“强制连接自托管服务器、禁止连接官方服务器（避免 EULA 争议），且在 Rust 层用代码
强制，而不是只写文档”。审查 tsclient-rs 0.1.5 后发现四条能绕开策略的路径：

1. `discovery.rs` 对不含点的主机会去查 `named.myteamspeak.com/lookup`（官方昵称解析）。
2. SRV 记录可以将已批准的域名重定向到别处。
3. TSDNS 同理。
4. `resolve_addr_impl`（`client.rs:978-987`）在解析器返回 `Err` 时**吞掉错误并回退到原始
   地址**，所以“靠自定义解析器拦截”不可靠。
5. `Resolver` trait 没有导出，策略层无法替换它。
6. 文件传输的主机由调用方传入。

## 决策

**T1（硬拦）**：录入地址时校验
- 必须是 host 或 host[:port]，端口 1..=65535；
- 拒绝裸昵称（含点才算 host），从而永不走官方昵称解析；
- 命中禁连清单（`teamspeak.com`、`teamspeak-systems.com`、`myteamspeak.com` 及其子域，
  用“等于或 `.` 结尾”匹配，避免 `notteamspeak.com` 这类误判）直接拒绝；
- `https://` 之类带 scheme 的输入拒绝。

**T2（显式登记）**：连接命令只接受**档案 id**，不接受地址；地址只能来自 T1 校验过的档案。
没有“从目录导入”“服务器列表订阅”这类接口。

**结构上掐死重定向**：策略层只把字面 `host:port` 交给 `Client::new`，同时强制注入
deny-all 的 `AddrResolver`（`proto` 的 `DenyResolver`）。因为传的是字面地址，
tsclient-rs 内部不会构造自己的 `Resolver`，官方昵称端点、SRV、TSDNS 三条路径全部不可达；
即使某条路径被触发，解析器也只会返回错误。

**文件传输**：`assert_transfer_host` 要求传输主机与会话主机一致，端口由服务器下发。

**审计**：`tool/audit_policy.sh` 在 CI 里保证官方域名字面量只出现在
`core/policy/src/official_infra.rs`。

## 被否决的方案

- **只写文档声明**：不满足“代码强制”的要求。
- **用自定义解析器逐个校验重定向目标**：`resolve_addr_impl` 会吞错误回退，且 `Resolver`
  未导出，需要给上游加补丁或复制一份 transport 代码。收益不足，复杂度高。
- **把策略推给 tsclient-rs 上游**：上游要求与 JS 参考保持结构对齐，不接受这类策略逻辑。

## 后果

- 代价：不支持官方 SRV/TSDNS 便捷域名与裸昵称，用户必须填完整 host 或 IP。
- 收益：合规约束是结构性的，不依赖运行时检查的覆盖面；测试可以直接断言
  `DenyResolver` 永不解析。

## 待办的上游候选（中性、纯增量）

- `VoiceData` 暴露 `packet_id`：现在接收侧丢掉包号（`client.rs` 只保留 `[2..4]` 的
  client_id 与 `[4]` 的 codec），语音无法做重排序与抖动缓冲。
- `discovery` 导出 `Resolver`：便于第三方客户端替换解析策略。