# AGENTS.md — 文档标准

本文定义仓库文档体系的分层归属与写作规则。写或改 `docs/` 下任何文档前先读本文件；`.agents/` 侧文档同样受这里的分层归属约束。`docs/` 面向使用者与维护者，`.agents/` 面向编码代理。

## 分层归属：一事实一归属

每类事实只有一个归属地，其余地方只放链接，禁止重复。归属判断先问一句：这条事实是给谁看的、属于哪个层次。

| 层级 | 职责 | 不该放这里 |
|---|---|---|
| 根 `AGENTS.md` | 全局 standing orders：每个 session 都必须知道的规则与拓扑，每条一两行并链向归属地 | 展开细节、步骤式流程、任何从归属地重复的内容 |
| `.agents/project.md` | 仓库结构、不变量、与 tsclient-rs 的关系 | 决策理由（→ `.agents/notes/`）、命令（→ `development.md`） |
| `docs/architecture.md` | 索引与拓扑：分层、一次连接的时序、事件流、线程模型、目录职责与「尚未接线」 | 跨文件契约与序列（→ 主题文档或 `docs/subsystems/`）、决策理由 |
| `docs/` 主题文档（`audio.md`、`backend.md`、`connection-boundary.md`、`images.md`） | 按链路组织的深潜文档：一条跨 crate 的链路或边界的契约、关键序列与已知限制 | 决策理由（→ `.agents/notes/`）、逐行实现细节（→ 源码） |
| `docs/subsystems/` | 每个子系统一篇：契约、关键路径与序列、不变量；规则见其 `AGENTS.md` | 决策理由（→ `.agents/notes/`）、逐行实现细节（→ 源码） |
| `docs/development.md` | 开发流程与环境：常用命令、构建依赖与平台细节、FFI 绑定生成、语言约定、git 约定、发版打包 | 架构图、测试约定、决策理由 |
| `docs/testing.md` | 测试约定：单测摆放、测试范围选择、真实服务器手动测试、CI 测试门 | 测试用例誊写 |
| `docs/defensive-patterns.md` | 编码反面与替代：FAILFAST、YAGNI、DRY、警告压制处置、类型安全优先、连接边界 | 常规开发流程 |
| `docs/ci-cd.md` | 各 GitHub Actions workflow 的触发条件与职责、发布矩阵、打包产物与已知简化 | 架构决策 |
| `docs/release/` | 发版日志：每个 tag 一篇 Release 正文；格式与生命周期见其 `AGENTS.md` | 当前机制的说明（→ docs 各归属地）、下一版的计划 |
| `docs/THIRD-PARTY.md` | 第三方代码的来源、来源提交、原始许可证与文件清单 | 决策理由（→ `.agents/notes/`） |
| `.agents/notes/` | 决策记录：为什么这么做、放弃了什么、如何验证；路径编码生命周期与类目，规则见其 `README.md` | 迁移计划、验收清单、spec 语气 |
| `.agents/skills/` | agent 侧复用工作流与判定标准（`SKILL.md`） | 产品与运行期契约（→ docs 或源码） |
| 模块内 `AGENTS.md` | 目录级规则，如 `core/AGENTS.md`、`lib/AGENTS.md`、本文 | 仓库级规则（→ 根 AGENTS.md） |

放置速查：standing orders → 根 `AGENTS.md`；结构与不变量 → `project.md`；命令与流程 → `development.md`；测试 → `testing.md`；编码反面 → `defensive-patterns.md`；拓扑与索引 → `architecture.md`；跨 crate 链路 → 主题文档；单 crate 契约 → `subsystems/`；workflow → `ci-cd.md`；发版日志 → `docs/release/`；第三方代码 → `docs/THIRD-PARTY.md`；决策理由 → `.agents/notes/`；复用流程 → `.agents/skills/`；目录规则 → 该目录的 `AGENTS.md`。

## 写作规则

- **只写当前状态，不写变更史。** 不用「之前/现在/不再/曾改名/已迁移」等说法，不写 PR 或 commit 编号，只写当前机制本身；变更故事归 commit、PR、`.agents/notes/` 与 `docs/release/` 的发版日志。

- **一段一物理行。** Markdown 每段只占一行，用编辑器软换行；代码块、表格、列表结构保持原格式。

- **相对 Markdown 链接。** 引用其他文档用仓库内相对路径，禁用绝对路径与纯文件名参引；引用代码写模块路径与符号名（如 `core/session` 的 `SessionHandle::spawn`、`core/proto` 的 `resolve_target`），不写 `file:line` 行号，行号漂移后没有门禁能发现。

- **命令要能直接复制执行，写明工作目录。** 各文档出现的命令与 `development.md` 保持一致，不一致就是缺陷。

- **未完成的部分显式标注「尚未接线」**，不写成已完成。

- **禁 emoji**，禁叙述历史与变更叙事（不写「我们后来发现…」这类过程性文字）。

- **用语审核。** 避免 contract、boundary、shape 这类模糊隐喻词，必须使用时先给出准确定义；例如用「官方主机清单」「最终出口检查」替代泛泛的「校验边界」。

## 文档索引

仓库级 standing orders 见根 `AGENTS.md`，各目录的模块级规则见该目录的 `AGENTS.md`。

## 精简版 slop checklist

写完逐条自查：

- **重复已有规则**：同一规则在多个文档出现。搜一个特征短语定位，只留一个归属地，其余放链接。

- **叙述历史**：出现「之前/现在/不再/重命名/迁移」，或时间线式编排。改为陈述当前事实。

- **手抄目录树**：源码或生成器已是事实来源时，不手工誊写目录、清单或清单式状态。

- **段落墙**：一个长段落塞进多条规则与括号补充。拆段，或把细节降级到它的归属地。

- **强调通胀**：到处加粗、大写、「务必/关键」等于没有强调。只保留会改变行为的那处强调。

- **spec 语气**：用「应当/需要实现」规划未来，而不是「是/采用」描述现状。

- **CoT 泄漏**：残留设计讨论、推测性规划、评审表演。只留结论与必要的归属链接；执行细则见 [.agents/skills/fls-trim-cot-leakage/SKILL.md](../.agents/skills/fls-trim-cot-leakage/SKILL.md)。
