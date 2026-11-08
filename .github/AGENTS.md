# AGENTS.md — CI and release

这些规则补充根 [AGENTS.md](../AGENTS.md)，只覆盖 `.github/`。

- 检查作业集中在可复用的 `checks.yml`（`workflow_call`）：Rust 格式与 Clippy、Flutter analyze、FFI 生成物一致性；单测集中在 `tests.yml`（`workflow_call`）。`ci.yml` 与 `release.yml` 都调用它们。文档检查不进 CI。
- `ci.yml` 负责 main 与 PR：调用 `checks.yml` 与 `tests.yml`，桌面与 Android 的 debug 构建仅依赖 `checks.yml`，不等待耗时的 `tests.yml`；tag 不触发它，发布时的平台构建只在 `release.yml` 里发生一次。
- `ci.yml` 用 `paths-ignore` 跳过只改 `**/*.md` 或 `LICENSE` 的运行；文档检查不进 CI，纯文档改动不产生状态，把检查设为合并必需时要一并处理这一点。
- `release.yml` 的 `build` 依赖 `checks` 与 `tests`，任一失败时打包矩阵不启动。
- Rust 作业从 `plugins/flspeak_ffi/rust` 目录运行，才能使用锁定的工具链。
- Dart 作业只格式化 `lib` 与 `setup.dart`，并运行 `flutter analyze`。
- `bindings` 作业负责 FFI 生成物校验与插件分析；生成物校验重跑 `flutter_rust_bridge_codegen generate`，再用 `git diff` 检查。
- codegen 用官方 release 的 x86_64 linux 预编译附件，版本与 sha256 固定在 `checks.yml` 顶部；升级 `flutter_rust_bridge` 时同步 `pubspec.yaml` 与这两个值。
- Android 作业把 NDK 链接进 SDK，避免构建阶段再下一份；Gradle 依赖由 `gradle/actions/setup-gradle` 缓存（`cache-provider: basic`），`release.yml` 只读复用。
- 发版作业从 tag 或手动输入推导版本号，把版本传给 `dart setup.dart <platform> <arch> --version <version>`，不依赖额外的版本脚本。
- 平台构建保持现有矩阵；新增目标时同时更新 `setup.dart` 和发布工作流。
- Android 签名分两套：debug 用 `ANDROID_DEBUG_KEYSTORE_BASE64`、`ANDROID_DEBUG_KEYSTORE_PASSWORD`、`ANDROID_DEBUG_KEY_ALIAS`、`ANDROID_DEBUG_KEY_PASSWORD`；release 用对应的 `ANDROID_RELEASE_*`。本地配置写进 `android/key.properties`，键名分别以 `debugStore*` / `releaseStore*` 开头。
- `ci.yml` 的 Android 作业把 debug keystore 还原成 `android/app/debug-upload.jks`；未配置 debug secret 时使用 runner 默认 debug keystore，外部 PR 不会因此失败。
- `release.yml` 把 release keystore 还原成 `android/app/release.jks`，并设置 `REQUIRE_RELEASE_SIGNING`，四个 release secret 缺一即失败，避免 debug 签名包流出。
- `android/app/*.jks` 与本地 `android/key.properties` 都在 `.gitignore` 里，不要提交。
- `pull_request_template.md` 定义仓库标准 PR 描述结构（改动描述、验证方式及末尾的 AI 使用信息区）；非 AI PR 可删除 AI 区块或填不适用。
