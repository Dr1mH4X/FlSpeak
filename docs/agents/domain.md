# Domain Docs

工程技能在探索代码库之前读取本仓库的领域文档。本仓库是单上下文（single-context）布局。

## 探索前先读

- 根目录 `GLOSSARY.md`。
- [.agents/notes/AGENTS.md](../../.agents/notes/AGENTS.md) 与将要改动区域相关的决策记录：按生命周期目录（`proposed/`、`implemented/`、`rejected/`）与类目检索，读覆盖该机制的笔记。

两类文件不存在时静默跳过：不提示缺失，也不在探索阶段建议创建。`/domain-modeling` 在术语或决策真正落定时按需创建；`GLOSSARY.md` 只承载词汇定义，不写实现细节。

## 文件布局

```
/
├── GLOSSARY.md
├── .agents/
│   └── notes/{lifecycle}/{class}/yyyy-mm-dd-主题-标题.md
└── docs/agents/
```

`.agents/notes/` 的内部布局、命名、生命周期与文件格式由 [.agents/notes/AGENTS.md](../../.agents/notes/AGENTS.md) 定义，本文只引用。

## 决策记录只有一处归属

决策记录写在 `.agents/notes/`。单项架构决策按 `architecture` 类目记录，路径与文件格式遵循 [.agents/notes/AGENTS.md](../../.agents/notes/AGENTS.md)。不新建 `docs/adr/`，也不在其他文档里另起一套决策记录。

新增笔记前先检索覆盖同一决策的旧笔记，并做取代性检查；规则见 [.agents/notes/AGENTS.md](../../.agents/notes/AGENTS.md) 与 [fls-archive-agent-notes](../../.agents/skills/fls-archive-agent-notes/SKILL.md)。

## 使用词汇表用词

输出中命名领域概念时（issue 标题、重构提案、假设、测试名），使用 `GLOSSARY.md` 定义的术语；词汇表明确避免的同义词不再使用。

需要的概念尚未收录时先判断：要么是在发明项目不用的语言（重新表述），要么确实是缺口（记录给 `/domain-modeling`）。

## 标出决策冲突

输出与现有 Agent Note 矛盾时显式指出，不静默覆盖：

> 与 [Agent Note：会话 actor 跑在独占线程的 LocalSet 上](../../.agents/notes/implemented/architecture/2026-10-08-session-actor.md) 冲突，但因为……值得重新讨论。
