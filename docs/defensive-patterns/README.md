# 防御性模式

本目录中每条模式都是本仓库在编码与评审中执行的强制要求，以「反面模式（错误做法）与规范模式（正确做法）」对比陈述。动手修改代码之前，先阅读对应范围的守则。

<a id="changing-read-map"></a>
## 你在改什么 | 动手前必读

| 你在改什么（Changing） | 动手前必读（Read） | 关键不变量与检查点 |
|---|---|---|
| Flutter 界面、页面组件、操作按钮、弹窗、文案 | [ui.md](ui.md) 与 [lib/AGENTS.md](../../lib/AGENTS.md) | 遵循 [fls-client-ui-ux](../../.agents/skills/fls-client-ui-ux/SKILL.md)；无 Tooltip、按钮极简无多余说明、无障碍走 `semanticLabel`、文案走 `arb/`。 |
| 会话生命周期、Actor 调度、并发、异步事件流 | [../architecture.md](../architecture.md) 与 [core/session/AGENTS.md](../../core/session/AGENTS.md) | `Client` 协议调用只能经 `core/session` 的 Actor 串行执行，禁止并发调用 tsclient-rs。 |
| 连接边界、官方主机清单、地址校验、文件/头像传输 | [connection.md](connection.md) 与 [../connection-boundary.md](../connection-boundary.md) | 官方主机清单只在 `core/proto` 的 `FORBIDDEN_HOST_SUFFIXES`，客户端不连接官方云或 myTeamSpeak；连接与传输共用同一检查。 |
| 音频采集、编解码、播放、环形缓冲区与 FFI 音频链路 | [audio.md](audio.md) 与 [core/audio/AGENTS.md](../../core/audio/AGENTS.md) | 音频帧零跨越 FFI 边界；双线程无锁环形缓冲区，Rust 侧自闭环。 |
| 通用代码质量、时序与并发、第一性原则、类型安全、警告消除 | [general.md](general.md) | 时序不承载正确性（严禁 `Future.delayed` / `sleep` 补丁）、FAILFAST、消除所有警告、边界处做显式强类型校验。 |
| 缺陷诊断、审查原则与事实陈述 | [review.md](review.md) | 事实陈述基于代码与实测，避免主观臆测与未经证实的推论。 |

---

## 核心设计思想

- **把正确性显式化**：写进结构与静态约束，不靠时序、魔法等待或外部补偿。
- **单一真相与单一出口**：官方主机校验、错误提示派发、音频处理各归正家，不在多处散落重复逻辑。
- **约束优先于自由度**：不添加非必要的界面解释文本、不引入悬停提示、不暴露未经收敛的底层状态。
- **改动面压成评审面**：变更只携带其声明的行为所必需的行，提交前运行最小证据集进行验证。
