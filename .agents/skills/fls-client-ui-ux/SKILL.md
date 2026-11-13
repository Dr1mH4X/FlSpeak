---
name: fls-client-ui-ux
description: 设计、修改或审查 Flutter 界面与交互时使用：核对文案精简、无悬停提示/Tooltip、无障碍语义、多语言词条及暗色模式。
---

# FlSpeak UI/UX 开发与审查

本技能是 FlSpeak 前端界面（Flutter UI/UX）设计、实现与审查的专用入口，确保所有界面改动遵守仓库对操作文案、交互形式与无障碍支持的硬性约定。

## Sources of truth

- [docs/defensive-patterns/README.md](../../../docs/defensive-patterns/README.md)
- [docs/defensive-patterns/ui.md](../../../docs/defensive-patterns/ui.md)
- [docs/subsystems/ui-design.md](../../../docs/subsystems/ui-design.md)
- [lib/AGENTS.md](../../../lib/AGENTS.md)
- [lib/widgets/AGENTS.md](../../../lib/widgets/AGENTS.md)
- [lib/theme/AGENTS.md](../../../lib/theme/AGENTS.md)
- [arb/intl_zh.arb](../../../arb/intl_zh.arb)
- [arb/intl_en.arb](../../../arb/intl_en.arb)

## 工作流步骤

1. **确定改动面**：列出本次涉及的页面、组件、主题与文案入口。
2. **核对规则**：按 [docs/defensive-patterns/README.md](../../../docs/defensive-patterns/README.md) 的映射表打开对应文档，逐条核对本次改动。判据以文档为准，本技能不重述。
3. **实现与生成**：
   - 若改动了 `arb/` 文件，运行 `flutter gen-l10n` 更新本地化生成代码，不手改 `lib/l10n/**`。
   - 控件、布局与样式优先经 [lib/widgets/prism.dart](../../../lib/widgets/prism.dart) 选用 `plugins/prism_ui` 原语，并复用 `context.scheme`、`context.texts` 与标准尺寸常量，确保亮暗主题与交互反馈表现一致。
4. **验证与回归检查**：
   - 运行格式化与静态代码分析。
   - 针对修改的界面与组件运行定向测试。

## 验证命令

```sh
# 重新生成本地化代码（若改动了 arb/）
flutter gen-l10n

# 格式化与静态检查
dart format lib test
flutter analyze --no-fatal-infos

# 检查是否误引入了 Tooltip 或 tooltip: 属性
grep -rn "Tooltip" lib/
grep -rn "tooltip:" lib/

# 运行受影响组件的单测
flutter test test/features/...
```

## 报告要求

列出：
- 受影响的页面或组件路径。
- 新增或调整的 ARB 词条（若有）。
- 按 [docs/defensive-patterns/ui.md](../../../docs/defensive-patterns/ui.md) 的检查项逐条给出核对结果（含是否优先复用 `prism_ui` 原语并隐藏同名 Material 控件）。
- 本地静态分析与单测通过情况。
