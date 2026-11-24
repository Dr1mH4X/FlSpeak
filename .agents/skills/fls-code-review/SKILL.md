---
name: fls-code-review
description: 审查 PR、分支或本地代码改动时使用：对照 docs/defensive-patterns/ 映射表、架构约束与质量门禁逐项核查，杜绝违规漏入主干。
---

# FlSpeak 代码审查工作流

审查的判据全部在仓库文档里，本技能只规定从哪篇文档取判据、按什么顺序核、交什么证据。

## Sources of truth

- [docs/defensive-patterns/README.md](../../../docs/defensive-patterns/README.md)：映射表，按改动面决定要读的规则篇与归属文档。
- [docs/defensive-patterns/review.md](../../../docs/defensive-patterns/review.md)、[general.md](../../../docs/defensive-patterns/general.md)、[ui.md](../../../docs/defensive-patterns/ui.md)、[ui-performance.md](../../../docs/defensive-patterns/ui-performance.md)、[logging.md](../../../docs/defensive-patterns/logging.md)：各领域判据。
- [docs/architecture.md](../../../docs/architecture.md)、[docs/backend.md](../../../docs/backend.md)、[docs/connection-boundary.md](../../../docs/connection-boundary.md)：架构与边界契约。
- [docs/AGENTS.md](../../../docs/AGENTS.md)：文档与注释的写作规则。

## 工作流步骤

1. **提取改动面**：

   ```sh
   git status --short
   git diff --stat origin/main...HEAD
   ```

2. **映射必读规则**：按映射表找出本次改动涉及的领域文档，在读 diff 之前打开每一篇。
3. **逐项核对**：对照映射表里该改动命中的关键不变量逐条核查，不凭记忆审查。
4. **复核证据**：作者是否提供了覆盖改动行为的最小验证命令与实际测试结果。

## 验证命令

```sh
grep -rn "Tooltip" lib/
grep -rn "tooltip:" lib/
grep -rn "Future.delayed" lib/
grep -rn "thread::sleep" core/

flutter analyze --no-fatal-infos
```

## 报告要求

列出审查范围与涉及文件、逐项核对结果（引用规则文档中的条目标明通过或发现问题）、明确的修复方案或放行结论。
