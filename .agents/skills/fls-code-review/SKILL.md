---
name: fls-code-review
description: 审查 PR、分支或本地代码改动时使用：对照 docs/defensive-patterns/ 映射表、架构约束与质量门禁逐项核查，杜绝违规漏入主干。
---

# FlSpeak 代码审查工作流

本技能是 FlSpeak 代码审查（Code Review）与交付前自审的专用入口。审查代码时严格对照规则条目与正反例核对，杜绝凭记忆审查导致违规漏入主干。

## Sources of truth

- [docs/defensive-patterns/README.md](../../../docs/defensive-patterns/README.md)
- [docs/defensive-patterns/review.md](../../../docs/defensive-patterns/review.md)
- [docs/defensive-patterns/general.md](../../../docs/defensive-patterns/general.md)
- [docs/defensive-patterns/ui.md](../../../docs/defensive-patterns/ui.md)
- [docs/defensive-patterns/connection.md](../../../docs/defensive-patterns/connection.md)
- [docs/defensive-patterns/audio.md](../../../docs/defensive-patterns/audio.md)

## 工作流步骤

1. **提取改动面（Diff Scope）**：
   ```sh
   git status --short
   git diff --stat origin/main...HEAD
   ```
2. **映射必读规则**：
   对照 [docs/defensive-patterns/README.md](../../../docs/defensive-patterns/README.md) 的映射表，找出本次改动涉及的所有领域文档。在阅读 diff 前打开每一篇规则文档。
3. **逐项进行阻断性审查**：
   按 [docs/defensive-patterns/review.md](../../../docs/defensive-patterns/review.md) 的阻断性审查项逐项核对；各领域判据以映射表指向的文档为准，本技能不重述。
4. **运行验证与证据复核**：
   作者是否提供了能覆盖改动行为的最小验证命令与测试证据？

## 验证命令

```sh
# 检查是否引入了 Tooltip
grep -rn "Tooltip" lib/
grep -rn "tooltip:" lib/

# 检查是否引入了时序规避手段
grep -rn "Future.delayed" lib/
grep -rn "thread::sleep" core/

# 运行代码分析与相关测试
flutter analyze --no-fatal-infos
```

## 报告要求

列出：
- 审查的改动范围与涉及文件。
- 阻断性审查核对结果（逐项引用规则文档中的条目，标明通过或发现问题）。
- 明确的修复方案（若有问题）或明确的放行结论。
