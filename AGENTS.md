# AGENTS.md

自托管 TeamSpeak 客户端：Flutter 负责界面，Rust 负责协议、合规策略与音频。

## 先读什么

| 想知道 | 读 |
| --- | --- |
| 仓库结构与不变量 | `.agents/project.md` |
| 怎么编译、怎么验证 | `.agents/commands.md` |
| 写代码的规矩 | `.agents/rules.md` |
| 分层与数据流 | `.agents/architecture.md` |
| 合规策略为什么长这样 | `docs/compliance.md` |
| 已经定下的技术决策 | `.agents/notes/implemented/` |

## 硬规则

1. **官方服务器不可达**：客户端只能连用户手动录入、且通过策略校验的地址。禁止连接
   `teamspeak.com` / `teamspeak-systems.com` / `myteamspeak.com` 及其子域，也禁止访问
   任何官方解析服务。这条规则在 Rust 层用代码强制，不依赖文档声明。
2. **官方域名字面量只允许出现在 `core/policy/src/official_infra.rs`**。
   `tool/audit_policy.sh` 在 CI 里守这条线；测试需要官方域名时从
   `policy::FORBIDDEN_HOST_SUFFIXES` 拼，不要写死。
3. **音频帧不过 FFI**。Rust 侧自己采集、编解码、播放，Dart 只收 UI 事件。
4. `Client` 的一切协议调用都经过 `core/session` 的 actor 串行执行，不要在
   别处并发调用 tsclient-rs。
5. 生成代码（`frb_generated.*`、`lib/src/rust/**`、`lib/l10n/**`）不手改，改输入后重跑生成。

## 验证

提交前至少跑：

```sh
cd plugins/flspeak_ffi/rust && cargo fmt --all && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace --all-features
cd ../../.. && flutter analyze && flutter test
bash tool/audit_policy.sh
```

聚合命令见 `.agents/commands.md`。