# AGENTS.md — Agent Notes — 决策记录

Agent Note 记录代码与文档载不下的「为什么」：决定了什么、放弃了什么、代价与验证方式。写或改本目录任何文件前先读本文件的布局、格式与核查清单，以及 [docs/AGENTS.md](../../docs/AGENTS.md) 的写作规则。新增前先检索覆盖同一决策的旧笔记，完全取代的旧笔记在同一个 PR 里归档或删除。

## 布局与命名

路径编码两个维度：`{lifecycle}/{class}/yyyy-mm-dd-主题-标题.md`，日期是该主题首次提出的时间（以 git 历史为准）。

- **生命周期**：`proposed/`（尚未落地）、`implemented/`（已交付）、`rejected/`（已否决，`Status` 行写明原因）。
- **类目**：`feature`、`bug-fix`、`simplification`、`architecture`（交付源码的结构性决策）、`process`（源码周边的工具与流程）、`testing`。
- 笔记之间一律用从笔记根写起的相对链接（`](../../implemented/<class>/<file>.md)`），移动后仍然有效；不建集中索引，活跃目录树本身就是工作清单。

## Status 与骨架

前三行严格为 `# Agent Note: <标题>`、空行、`Status: <状态>`；状态只有 `proposed`、`implemented`、`rejected — <一句话原因>` 三种，必须与所在目录一致，不带日期。

- implemented：`## Problem` → `## Decision` → 自定义小节 → `## Alternatives considered` → `## Consequences`；`## Testing`、`## Related` 也可用。`## Proposal`、`## Plan`、`## Acceptance criteria` 属于 spec 语气，不得出现。
- proposed：`## Problem` → `## Proposal` → 自定义小节 → `## Alternatives considered` → `## Acceptance criteria` → `## Risks`。
- 每篇都必须有 `## Alternatives considered`：真实考虑过并放弃的方案，每个一段，用加粗论点引导。

## 维护、归档与删除

代码后续改了路径、符号、默认值或机制时，在同一个改动里就地改写笔记的事实，不追加变更历史；就地更新的是事实，推翻决策必须新写一篇并互相链接。

只有代码、测试与现有文档解释不了的决策理由具有长期价值时才新增笔记：架构、生命周期、并发、音频链路、连接边界、FFI 接口取舍等有明确 tradeoff 的改动应当附带笔记，纯文案与格式改动不必。

只描述局部文案或纯机械改动的 implemented 笔记直接删除并修复入站链接。其余已落地笔记在交付决策完整、依据不太可能再指导未来工作但仍具历史价值时归档到 `archived/{class}/`：保留 `Status: implemented`，在其下插入一行 `Archived: YYYY-MM-DD`，其余正文一字不改，之后永久冻结、不再向外核查链接。proposed 笔记永不归档，过时的提案转为 `rejected`。

## 核查清单

- 路径符合 `{lifecycle}/{class}/yyyy-mm-dd-主题-标题.md`，`Status:` 与目录一致。
- 正文以 `## Problem` 开头，implemented 用 `## Decision`、proposed 用 `## Proposal`。
- `## Alternatives considered` 存在且写的是真实放弃过的方案。
- 笔记间链接能解析到仓库里的文件；代码只写模块路径与符号名，不写 `file:line`。
- 没有 emoji、没有指代性时间戳（「本轮」「这一版」）、没有过程流水账。
