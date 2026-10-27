# AGENTS.md

自托管 TeamSpeak 客户端：Flutter 负责界面，Rust 负责协议、连接边界与音频。

## 先读什么

| 想知道 | 读 |
| --- | --- |
| 仓库结构与不变量 | `.agents/project.md` |
| 怎么编译、怎么验证 | `docs/development.md` |
| 测试怎么写、跑哪些 | `docs/testing.md` |
| 写代码的规矩 | `docs/defensive-patterns.md` |
| 分层与数据流 | `docs/architecture.md` |
| 连接边界为什么长这样 | `docs/connection-boundary.md` |
| 文档放哪、怎么写 | `docs/AGENTS.md` |
| 已经定下的技术决策 | `.agents/notes/implemented/` |

子树规则只写该目录特有的约束，不重复本文件：

| 目录 | 读 |
| --- | --- |
| `core/` | `core/AGENTS.md` |
| `plugins/flspeak_ffi/` | `plugins/flspeak_ffi/AGENTS.md` |
| `lib/` | `lib/AGENTS.md` |
| `docs/` | `docs/AGENTS.md` |
| `.github/` | `.github/AGENTS.md` |
| `.agents/notes/` | `.agents/notes/AGENTS.md` |
| `.agents/skills/` | `.agents/skills/AGENTS.md` |

## 硬规则

1. **自托管 only**：客户端只连接用户手动录入的 IP、域名或 localhost，不实现 myTeamSpeak
   账号/云同步，也不调用官方媒体上传或附件下载。裸昵称不接受，`named.myteamspeak.com/lookup`
   不使用。SRV（`_ts3._udp.<domain>`）是标准 DNS，可以解析；最终目标由
   `core/proto` 的 `client` 做一次官方基础设施检查，不在 UI、FFI 或存储层重复审查。
2. **官方主机清单只放在 `core/proto` 的 `FORBIDDEN_HOST_SUFFIXES`**。连接和图片抓取
   共用这一份；测试需要官方域名时从该常量拼，不要写死。
3. **音频帧不过 FFI**。Rust 侧自己采集、编解码、播放，Dart 只收 UI 事件。
4. `Client` 的一切协议调用都经过 `core/session` 的 actor 串行执行，不要在
   别处并发调用 tsclient-rs。
5. 生成代码（`frb_generated.*`、`plugins/flspeak_ffi/lib/src/rust/**`、`lib/l10n/**`）
   不手改，改输入后重跑生成。
6. **全仓不使用悬停提示**：不引入 `Tooltip`，也不给 `IconButton` 等控件传 `tooltip:`。
   图标按钮的无障碍名称用 `semanticLabel` 或 `Semantics` 提供；`MaterialLocalizations`
   里的 `*Tooltip` 只作为标准语义文案使用。

## 验证

提交前至少跑：

```sh
just check
```

等价于在 `plugins/flspeak_ffi/rust` 跑 `cargo fmt --all && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace --all-features`，再在根目录跑 `dart format lib setup.dart`、`flutter analyze` 与 `flutter test lib`。没装 just 就按原始命令跑；全部任务用 `just --list` 查看，细节见 `docs/development.md`。
