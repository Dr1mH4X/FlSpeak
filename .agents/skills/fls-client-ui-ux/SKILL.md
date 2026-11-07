---
name: fls-client-ui-ux
description: 设计、修改或审查 Flutter 界面与交互时使用：核对文案精简、无悬停提示/Tooltip、无障碍语义、多语言词条及暗色模式。
---

# FlSpeak UI/UX 开发与审查

本技能是 FlSpeak 前端界面（Flutter UI/UX）设计、实现与审查的专用入口，确保所有界面改动遵守仓库对操作文案、交互形式与无障碍支持的硬性约定。

## Sources of truth

- [docs/defensive-patterns/ui.md](../../../docs/defensive-patterns/ui.md)：Flutter 界面文案与操作按钮约束（最简文案、说明文案例外、禁止 Tooltip/悬停提示）。
- [lib/AGENTS.md](../../../lib/AGENTS.md)：Flutter 前端架构、单向状态流（`SessionView`）、通知系统（`NoticeCenter`）。
- [lib/theme/AGENTS.md](../../../lib/theme/AGENTS.md)：主题扩展（`context.scheme`、`context.status`、`context.texts`）与暗色模式规范。
- [arb/intl_zh.arb](../../../arb/intl_zh.arb) 与 [arb/intl_en.arb](../../../arb/intl_en.arb)：全部用户可见文案来源。

## 工作流步骤

1. **动手前约束自查**：
   - **禁止 Tooltip 与悬停提示**：不引入 Flutter `Tooltip` 组件，不给 `IconButton` 等传入 `tooltip:` 参数。图标按钮的无障碍名称统一通过 `semanticLabel` 或 `Semantics` 提供。
   - **文案极简与杜绝赘述**：按钮已表达操作时不追加小字、副标题或解释性标签；不在弹窗或面板底部放置解释内部实现机制（如采样刷新、限流等待、协议细节）的文本。仅允许三类必要说明：破坏性操作的安全警告、按钮不可用原因、表单字段校验提示。
   - **多语言全覆盖**：所有新增的用户可见文字必须同时录入 `arb/intl_zh.arb` 与 `arb/intl_en.arb`，严禁在 widget 源码中硬编码中英文。
   - **瞬时反馈归一**：轻量反馈走 `lib/core/notices.dart` 的 `NoticeCenter`，不自建临时横幅，不使用 `SnackBar`。
2. **实现与生成**：
   - 若改动了 `arb/` 文件，运行 `flutter gen-l10n` 更新本地化生成代码，不手改 `lib/l10n/**`。
   - 布局与样式优先复用 `context.scheme`、`context.texts` 与标准尺寸常量，确保亮暗主题表现一致。
3. **验证与回归检查**：
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
- 检查项确认：已确认无 Tooltip/悬停、无多余解释性文本、无障碍语义覆盖完备。
- 本地静态分析与单测通过情况。
