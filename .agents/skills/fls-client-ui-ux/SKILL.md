---
name: fls-client-ui-ux
description: 设计、修改或审查 Flutter 界面与交互时使用：核对文案精简、无悬停提示/Tooltip、无障碍语义、多语言词条及暗色模式。
---

# FlSpeak UI/UX 开发与审查

本技能是 Flutter 界面的设计、实现与审查入口：它只说去读哪里、按什么顺序做、怎么验证。操作文案、交互形式、无障碍与视觉规格的判据在 `docs/` 里，本技能不复述。

## Sources of truth

- [docs/defensive-patterns/README.md](../../../docs/defensive-patterns/README.md)：「你在改什么 | 动手前必读」映射表，决定这次要读哪几篇。
- [docs/defensive-patterns/ui.md](../../../docs/defensive-patterns/ui.md)：操作文案、悬停提示与无障碍。
- [docs/ui-design.md](../../../docs/ui-design.md)：组件选型、表面层级、圆角、字阶、按压反馈与设置行规格。
- [docs/defensive-patterns/ui-performance.md](../../../docs/defensive-patterns/ui-performance.md)：帧预算与按需渲染。
- [lib/AGENTS.md](../../../lib/AGENTS.md) 与 [lib/widgets/prism.dart](../../../lib/widgets/prism.dart)：目录约束与 `prism_ui` 桥接入口。
- [arb/intl_zh.arb](../../../arb/intl_zh.arb) 与 [arb/intl_en.arb](../../../arb/intl_en.arb)：唯一文案来源。

## 工作流步骤

1. **确定改动面**：列出本次涉及的页面、组件、主题与文案入口。
2. **核对规则**：按映射表打开命中的文档逐条核对，判据以文档为准。
3. **实现与生成**：改动了 `arb/` 就运行 `flutter gen-l10n`，不手改 `lib/l10n/**`。
4. **验证与回归**：跑格式化、静态分析与受影响组件的定向测试。

## 验证命令

```sh
# 若改动了 arb/
flutter gen-l10n

dart format lib test
flutter analyze --no-fatal-infos

# 全仓不使用悬停提示
grep -rn "Tooltip" lib/
grep -rn "tooltip:" lib/

# 受影响组件的单测
flutter test test/features/...
```

## 报告要求

列出受影响的页面与组件路径、新增或调整的 ARB 词条、按 [docs/defensive-patterns/ui.md](../../../docs/defensive-patterns/ui.md) 逐项给出的核对结果（含是否优先复用 `prism_ui` 原语并隐藏同名 Material 控件），以及静态分析与单测的实际结果。
