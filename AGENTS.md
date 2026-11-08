# AGENTS.md

FlSpeak 是 TeamSpeak 第三方客户端：Flutter 负责界面，Rust 负责协议、连接边界与音频。改动 `lib/` 前必读 [docs/defensive-patterns/ui.md](docs/defensive-patterns/ui.md) 与 [lib/AGENTS.md](lib/AGENTS.md)；改动 `core/` 前必读 [docs/architecture.md](docs/architecture.md) 与对应子树 `AGENTS.md`；文档遵循 [docs/AGENTS.md](docs/AGENTS.md)；权限与访问边界见 [docs/permissions.md](docs/permissions.md)。

- **技术选型**：
  - **Frontend**: Flutter
  - **Backend**: Rust
  - **State Management**: Riverpod
  - **Internationalization**: Flutter Intl (`arb/`)

## 防御模式与变更前必读

动手修改任何界面组件或状态、音频线程、协议或连接边界、会话生命周期或 teardown 代码前，先阅读 [docs/defensive-patterns/README.md](docs/defensive-patterns/README.md) 中的「你在改什么 | 动手前必读」映射表。其审阅原则与反面模式按制品严格执行。

子树规则只写该目录特有的约束，不重复本文件：

| 目录 | 读 |
| --- | --- |
| `core/` | `core/AGENTS.md` (及其下 `audio/`, `proto/`, `server/`, `session/`) |
| `plugins/` | `plugins/AGENTS.md` |
| `plugins/flspeak_ffi/` | `plugins/flspeak_ffi/AGENTS.md` |
| `lib/` | `lib/AGENTS.md` (及其下 `core/`, `features/`, `theme/`, `widgets/` 等) |
| `docs/` | `docs/AGENTS.md` (及其下 `subsystems/`, `defensive-patterns/`, `cookbook/`, `release/`) |
| `website/` | `website/AGENTS.md` |
| `tool/` | `tool/AGENTS.md` |
| `.github/` | `.github/AGENTS.md` |
| `.agents/` | `.agents/AGENTS.md` (及其下 `notes/`, `skills/`) |
| `android/`, `macos/`, `linux/`, `windows/` | 各平台根 `AGENTS.md` 与原生宿主层 |
| `arb/`, `shaders/` | 对应资产与资源目录 `AGENTS.md` |

## 约定与行为工作流

- **UI 变更**：使用 [fls-client-ui-ux](.agents/skills/fls-client-ui-ux/SKILL.md) 作为设计与审查入口；严格遵守 [Flutter 界面文案与操作按钮约束](docs/defensive-patterns/ui.md)，全仓不引入 Tooltip，无多余说明文本。
- **代码审查**：审查 PR 或交付前自查时，遵循 [fls-code-review](.agents/skills/fls-code-review/SKILL.md)；严格对照 [docs/defensive-patterns/README.md](docs/defensive-patterns/README.md) 映射表逐项核查，禁止凭记忆审查。
- **运行本地检查与提推前验证**：在提交或推送前，遵循 [fls-pre-push-checks](.agents/skills/fls-pre-push-checks/SKILL.md)；按即将推出的 diff 选出覆盖它的最小检查集，不反射式地跑全量套件。
- **Agent Notes 决策记录**：只有不可变长效决策才建笔记，遵循 [fls-archive-agent-notes](.agents/skills/fls-archive-agent-notes/SKILL.md)；归档记录冻结不改。
- **清理思维链泄漏**：代码注释、文档或提交说明中禁止残留推理过程、评审者辩解或对冲式规划，遵循 [fls-trim-cot-leakage](.agents/skills/fls-trim-cot-leakage/SKILL.md)。
- **适度重构**：在修改功能时，若发现冗余代码，应在确保行为一致的前提下进行抽象，保持代码库整洁。
- **发版日志**：发版前编写版本变更记录，遵循 [fls-release-log](.agents/skills/fls-release-log/SKILL.md)。
- **AI PR 提交规范**：由 AI 编写或辅助编写的 PR，创建 PR 前必须请用户明确提供本次实际使用的 **Agent（AI 编程工具）、模型名称/版本和思考强度（reasoning effort）**。若用户已在当前对话中明确提供这三项信息，可直接使用；信息不全时，应等待用户补充后再创建 PR。必须将用户提供的信息填写在 PR 描述末尾（模板见 [.github/pull_request_template.md](.github/pull_request_template.md)）；AI 不得自行判断、推测或补全模型名称等字段。多个 Agent 或模型参与时，逐一提供对应信息；「未知」或「不适用」也只能按用户明确提供的内容填写。

## 硬规则

1. **项目边界**：客户端只连接用户手动录入的 IP、域名或 localhost，不实现 myTeamSpeak 账号/云同步，也不调用官方媒体上传或附件下载。裸昵称不接受，`named.myteamspeak.com/lookup` 不使用。SRV（`_ts3._udp.<domain>`）是标准 DNS，可以解析；最终目标由 `core/proto` 的 `client` 做一次官方基础设施检查，不在 UI、FFI 或存储层重复审查。版本更新检查的固定 GitHub 元数据请求是唯一例外，约束见 [连接边界](docs/connection-boundary.md)。
2. **官方主机清单只放在 `core/proto` 的 `FORBIDDEN_HOST_SUFFIXES`**。连接和图片抓取
   共用这一份；测试需要官方域名时从该常量拼，不要写死。
3. **音频帧不过 FFI**。Rust 侧自己采集、编解码、播放，Dart 只收 UI 事件。
4. `Client` 的一切协议调用都经过 `core/session` 的 actor 串行执行，不要在
   别处并发调用 tsclient-rs。
5. 生成代码（`frb_generated.*`、`plugins/flspeak_ffi/lib/src/rust/**`、`lib/l10n/**`）
   不手改，改输入后重跑生成。
6. **全仓不使用悬停提示**：遵守 [Flutter 界面文案与操作按钮约束](docs/defensive-patterns/ui.md)。

## 验证

提交前至少跑：

```sh
just check
```

等价于在 `plugins/flspeak_ffi/rust` 跑 `cargo fmt --all && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace --all-features`，在根目录跑 `dart format lib test setup.dart`、`flutter analyze` 与 `flutter test`，以及在 `website/` 跑 `pnpm --dir website install --frozen-lockfile`、`pnpm --dir website run typecheck` 与 `pnpm --dir website run build`。没装 just 就按原始命令跑；全部任务用 `just --list` 查看，细节见 `docs/development.md`。

