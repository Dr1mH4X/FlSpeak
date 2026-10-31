# AGENTS.md — 本地化文案资源

本目录管理应用全量多语言文案源文件（Application Resource Bundle, ARB）。

## 规则与约束

- 所有用户可见文案均在此维护（`intl_en.arb` 与 `intl_zh.arb`），严禁在 Dart Widget 源码中硬编码中英文自然语言字符串。
- `intl_en.arb` 与 `intl_zh.arb` 的 Key 集合必须严格对齐；新增文案时中英两份文件同步添加。
- 本目录为唯一事实来源。生成代码存放在 `lib/l10n/**`，修改本目录后必须运行：
  ```sh
  flutter gen-l10n
  ```
- 严禁手改 `lib/l10n/**`。
