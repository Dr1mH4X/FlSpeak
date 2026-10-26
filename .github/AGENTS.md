# AGENTS.md — CI and release

这些规则补充根 [AGENTS.md](../AGENTS.md)，只覆盖 `.github/`。

- 检查作业集中在可复用的 `checks.yml`（`workflow_call`）：Rust 检查、Flutter
  analyze、Dart 单测、FFI 生成物一致性。`ci.yml` 与 `release.yml` 都调用它，
  改检查时只改这一处。文档检查不进 CI。
- `ci.yml` 负责分支与 PR：调用 `checks.yml`，再跑桌面与 Android 的 debug 构建；
  tag 不触发它，发布时的平台构建只在 `release.yml` 里发生一次。
- `release.yml` 的 `build` 依赖 `checks`，检查失败时打包矩阵不启动。
- Rust 作业从 `plugins/flspeak_ffi/rust` 目录运行，才能使用锁定的工具链。
- Dart 作业只格式化 `lib` 与 `setup.dart`，并运行 `flutter analyze`。
- `plugins` 作业重跑 `flutter_rust_bridge_codegen generate`，再用
  `git diff` 检查生成物；`flutter analyze` 会触发 native assets，所以它也要装音频依赖。
- 发版作业从 tag 或手动输入推导版本号，把版本传给
  `dart setup.dart <platform> <arch> --version <version>`，不依赖额外的版本脚本。
- 平台构建保持现有矩阵；新增目标时同时更新 `setup.dart` 和发布工作流。
- Android 签名分两套：debug 用 `ANDROID_DEBUG_KEYSTORE_BASE64`、
  `ANDROID_DEBUG_KEYSTORE_PASSWORD`、`ANDROID_DEBUG_KEY_ALIAS`、
  `ANDROID_DEBUG_KEY_PASSWORD`；release 用对应的 `ANDROID_RELEASE_*`。
  本地配置写进 `android/key.properties`，键名分别以 `debugStore*` / `releaseStore*`
  开头。
- `ci.yml` 的 Android 作业把 debug keystore 还原成 `android/app/debug-upload.jks`；
  未配置 debug secret 时使用 runner 默认 debug keystore，外部 PR 不会因此失败。
- `release.yml` 把 release keystore 还原成 `android/app/release.jks`，并设置
  `REQUIRE_RELEASE_SIGNING`，四个 release secret 缺一即失败，避免 debug 签名包流出。
- `android/app/*.jks` 与本地 `android/key.properties` 都在 `.gitignore` 里，不要提交。