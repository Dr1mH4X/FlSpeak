# AGENTS.md — CI and release

这些规则补充根 [AGENTS.md](../AGENTS.md)，只覆盖 `.github/`。

- CI 覆盖 Rust 检查、Flutter analyze、FFI 生成物一致性和平台构建。
  文档检查不进 CI。
- Rust 作业从 `plugins/flspeak_ffi/rust` 目录运行，才能使用锁定的工具链。
- Dart 作业只格式化 `lib` 与 `setup.dart`，并运行 `flutter analyze`。
- `plugins` 作业重跑 `flutter_rust_bridge_codegen generate`，再用
  `git diff` 检查生成物。
- 发版作业从 tag 或手动输入推导版本号，把版本传给
  `dart setup.dart <platform> <arch> --version <version>`，不依赖额外的版本脚本。
- 平台构建保持现有矩阵；新增目标时同时更新 `setup.dart` 和发布工作流。
