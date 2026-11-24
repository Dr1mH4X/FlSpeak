# AGENTS.md

FlSpeak 是 TeamSpeak 第三方客户端：Flutter 负责界面，Rust 负责协议、连接边界与音频。改动 `lib/` 前必读 [docs/defensive-patterns/ui.md](docs/defensive-patterns/ui.md) 与 [lib/AGENTS.md](lib/AGENTS.md)；改动 `core/` 前必读 [docs/architecture.md](docs/architecture.md) 与 [core/AGENTS.md](core/AGENTS.md)；文档遵循 [docs/AGENTS.md](docs/AGENTS.md)；权限与访问边界见 [docs/permissions.md](docs/permissions.md)。

- **技术选型**：
  - **Frontend**: Flutter
  - **Backend**: Rust
  - **State Management**: Riverpod
  - **Internationalization**: Flutter Intl (`arb/`)

## 防御模式与变更前必读

动手修改任何界面组件或状态、音频线程、协议或连接边界、会话生命周期或 teardown 代码前，先阅读 [docs/defensive-patterns/README.md](docs/defensive-patterns/README.md) 中的「你在改什么 | 动手前必读」映射表。其审阅原则与反面模式按制品严格执行。

子树规则只写该目录特有的约束，不重复本文件。目录级入口只有这几处：[core/AGENTS.md](core/AGENTS.md)、[lib/AGENTS.md](lib/AGENTS.md)、[plugins/flspeak_ffi/AGENTS.md](plugins/flspeak_ffi/AGENTS.md)、[docs/AGENTS.md](docs/AGENTS.md) 与 [docs/defensive-patterns/README.md](docs/defensive-patterns/README.md)。

## 约定与行为工作流

- **UI 变更**：使用 [fls-client-ui-ux](.agents/skills/fls-client-ui-ux/SKILL.md) 作为设计与审查入口；界面组件优先经 [lib/widgets/prism.dart](lib/widgets/prism.dart) 复用 `prism_ui` 原语（见 [Flutter 界面设计规范](docs/ui-design.md)），并严格遵守 [Flutter 界面文案与操作按钮约束](docs/defensive-patterns/ui.md)（全仓不引入 Tooltip，无多余说明文本）。
- **输出语言**：日志、错误 `Display`、测试输出、`tool/` 与 CI 输出用英文；中文只用于注释与用户可见的本地化文案，规范见 [docs/development.md](docs/development.md)。
- **代码审查**：审查 PR 或交付前自查时，遵循 [fls-code-review](.agents/skills/fls-code-review/SKILL.md)；严格对照 [docs/defensive-patterns/README.md](docs/defensive-patterns/README.md) 映射表逐项核查，禁止凭记忆审查。
- **运行本地检查与提推前验证**：在提交或推送前，遵循 [fls-pre-push-checks](.agents/skills/fls-pre-push-checks/SKILL.md)；按即将推出的 diff 选出覆盖它的最小检查集，不反射式地跑全量套件。
- **Agent Notes 决策记录**：只有不可变长效决策才建笔记，规则见 [.agents/notes/AGENTS.md](.agents/notes/AGENTS.md)；归档记录冻结不改。
- **清理思维链泄漏**：代码注释、文档或提交说明中禁止残留推理过程、评审者辩解或对冲式规划，遵循 [fls-trim-cot-leakage](.agents/skills/fls-trim-cot-leakage/SKILL.md)。
- **适度重构**：在修改功能时，若发现冗余代码，应在确保行为一致的前提下进行抽象，保持代码库整洁。
- **发版日志**：发版前编写版本变更记录，遵循 [fls-release-log](.agents/skills/fls-release-log/SKILL.md)。
- **AI PR 提交规范**：由 AI 编写或辅助编写的 PR，创建 PR 前必须请用户明确提供本次实际使用的 **Agent（AI 编程工具）、模型名称/版本和思考强度（reasoning effort）**。若用户已在当前对话中明确提供这三项信息，可直接使用；信息不全时，应等待用户补充后再创建 PR。必须将用户提供的信息填写在 PR 描述末尾（模板见 [.github/pull_request_template.md](.github/pull_request_template.md)）；AI 不得自行判断、推测或补全模型名称等字段。多个 Agent 或模型参与时，逐一提供对应信息；「未知」或「不适用」也只能按用户明确提供的内容填写。

## 硬规则

1. **项目边界**：客户端只连接用户手动录入的 IP、域名或 localhost，不实现 myTeamSpeak 账号、云同步、官方媒体上传或附件下载；SRV 是标准 DNS 可以解析，最终目标由 `core/proto` 的 `client` 检查一次。完整规则与版本更新检查的例外见[连接边界](docs/connection-boundary.md)。
2. **官方主机清单只在 `core/proto` 的 `FORBIDDEN_HOST_SUFFIXES`**：连接与图片抓取共用这一份，测试需要官方域名时从该常量拼。
3. **音频帧不过 FFI**：Rust 侧自己采集、编解码、播放，Dart 只收 UI 事件，见[音频](docs/audio.md)。
4. **`Client` 的协议调用只经 `core/session` 的 actor 串行执行**，不要在别处并发调用 tsclient-rs，线程模型见[架构](docs/architecture.md)。
5. **生成代码不手改**：`frb_generated.*`、`plugins/flspeak_ffi/lib/src/rust/**` 与 `lib/l10n/**` 都由输入重新生成。
6. **全仓不使用悬停提示**，遵守 [Flutter 界面文案与操作按钮约束](docs/defensive-patterns/ui.md)。
7. **前后端职责边界**：Dart 只负责 UI、纯 UI 偏好、OS 桥接与 WebRTC，业务协议、媒体缓存、权限与非 UI 持久化归 Rust + FFI，见[架构](docs/architecture.md)。

## 验证

提交前在仓库根目录跑：

```sh
just check
```

各任务覆盖的检查项与平台依赖见 [docs/development.md](docs/development.md)，没装 just 时按那里的原始命令跑。

## Issue 与领域术语

issue 与 spec 存放为 `Dr1mH4X/FlSpeak` 的 GitHub issue（`origin`，不是 `zeroblock0`），用 `gh` CLI 操作；领域术语以根 [GLOSSARY.md](GLOSSARY.md) 为准，界面、测试与决策记录都用那里的叫法。
