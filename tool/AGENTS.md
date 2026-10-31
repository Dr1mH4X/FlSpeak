# AGENTS.md — 仓库工具与维护脚本

本目录包含维护仓库版本发布、代码工程自动化等本地 Dart 脚本。

## 规则与约束

- 脚本一律使用 Dart 编写，确保在 Flutter / Dart 标准环境下直接使用 `dart run tool/<script>.dart` 即可执行，零外部未锁定的二进制依赖。
- 每个工具脚本应配备对应的同目录单元测试（如 `bump_version.dart` 与 `bump_version_test.dart`），由 `just test` 覆盖。
- 不要在本目录放置针对特定操作系统的 Ad-hoc shell 脚本，跨平台逻辑由 Dart 或 `setup.dart` 统一承担。
