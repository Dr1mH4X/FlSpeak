---
name: fls-code-review
description: 审查 PR、分支或本地代码改动时使用：对照 docs/defensive-patterns/ 映射表、架构约束与质量门禁逐项核查，杜绝违规漏入主干。
---

# FlSpeak 代码审查工作流

本技能是 FlSpeak 代码审查（Code Review）与交付前自审的专用入口。审查代码时严格对照规则条目与正反例核对，杜绝凭记忆审查导致违规漏入主干。

## Sources of truth

- [docs/defensive-patterns/README.md](../../../docs/defensive-patterns/README.md)：修改范围到必读文档的映射表（Changing | Read）。
- [docs/defensive-patterns/review.md](../../../docs/defensive-patterns/review.md)：审查原则与阻断性审查项。
- [docs/defensive-patterns/general.md](../../../docs/defensive-patterns/general.md)：通用编码准则、FAILFAST、时序不承载正确性、警告消除。
- [docs/defensive-patterns/ui.md](../../../docs/defensive-patterns/ui.md)：Flutter 界面文案与操作按钮极简原则、杜绝技术实现外溢。
- [docs/defensive-patterns/connection.md](../../../docs/defensive-patterns/connection.md)：连接边界、单一出口检查。
- [docs/defensive-patterns/audio.md](../../../docs/defensive-patterns/audio.md)：音频线程、无锁实时安全、音频帧零跨越 FFI 边界。

## 工作流步骤

1. **提取改动面（Diff Scope）**：
   ```sh
   git status --short
   git diff --stat origin/main...HEAD
   ```
2. **映射必读规则**：
   对照 [docs/defensive-patterns/README.md](../../../docs/defensive-patterns/README.md) 的映射表，找出本次改动涉及的所有领域文档。在阅读 diff 前打开每一篇规则文档。
3. **逐项进行阻断性审查**：
   - **UI / 交互**：是否引入了 `Tooltip` / `tooltip:`？按钮是否有多余解释？弹窗与卡片是否包含探测机制、限流、协议等内部实现细节外溢？文字是否全部走 `arb/`？
   - **连接边界**：是否违背了只连接手动录入主机的原则？官方主机校验是否仅由 `core/proto` 承担？
   - **时序与并发**：是否存在 `Future.delayed`、`microtask`、`addPostFrameCallback` 或 `thread::sleep` 掩盖竞态？tsclient-rs 调用是否全由 `core/session` 的 Actor 串行处理？
   - **错误处理与类型**：是否吞掉异常或伪造兜底值？是否有新增编译器警告或使用属性压制？
   - **思维链残留**：是否有变更叙事、调试流水账或推理过程泄露在注释与文档中？
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
- 阻断性审查核对结果（逐项标明：通过 / 发现问题）。
- 明确的修复方案（若有问题）或明确的放行结论。
