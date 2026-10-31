# AGENTS.md — 国际化生成代码 (lib/l10n)

本目录为 Flutter gen-l10n 自动化生成的本地化 Dart 代码。

## 规则与约束

- **严禁手改**：本目录下的任何文件均为构建机器生成物，严禁人工修改。
- **文案变更流程**：修改 `arb/intl_zh.arb` 与 `arb/intl_en.arb` 后，运行：
  ```sh
  flutter gen-l10n
  ```
- 保持中英文键值集合完全对称，生成产物随代码一并提交入库。
