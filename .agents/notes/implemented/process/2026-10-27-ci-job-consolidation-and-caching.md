# Agent Note: CI 作业合并与依赖缓存

Status: implemented

## Problem

`checks.yml` 的 `dart-test` 与 `plugins` 各自准备 checkout、Flutter、pub get、音频构建
依赖和 rust-cache。`flutter test` 与插件目录的 `flutter analyze` 都会触发 native
assets，同一套 Rust 被编译两次。Android 作业没有 Gradle 缓存，Setup NDK 装好的 NDK
也不会被 Flutter 的 Gradle 插件复用，构建阶段会再下载一份。codegen 通过
`cargo install` 安装，缓存未命中时要从源码编译。

## Decision

- `dart-test` 与 `plugins` 合并为一个 `dart-test` 作业：FFI 生成物校验与插件分析在前，
  单测在后，共用一次 checkout、Flutter 安装、音频依赖与 native assets 编译。两道门禁
  各自保留为独立 step。
- codegen 使用官方 release 的 `x86_64-unknown-linux-gnu` 预编译附件；版本与 sha256
  固定在 `checks.yml` 顶部（`FRB_CODEGEN_VERSION`、`FRB_CODEGEN_SHA256`），解压到
  `$RUNNER_TEMP/bin` 并加入 `GITHUB_PATH`。
- Android 作业给 `nttld/setup-ndk` 设置 `link-to-sdk: true`，Flutter 的 Gradle 插件
  从 SDK 目录找到 NDK。
- `ci.yml` 与 `release.yml` 的 Android 作业使用 `gradle/actions/setup-gradle`
  （`cache-provider: basic`）。PR 与 tag 上只读，main push 写入。

## Alternatives considered

- **保留两个作业，抽 composite action**：checkout、Flutter 安装与 apt 依赖仍按作业各跑
  一次，native assets 仍编译两次。
- **用 `taiki-e/install-action` 或 `cargo-binstall` 安装 codegen**：多一层第三方工具与
  版本解析；直接下载固定附件更可控。
- **缓存 NDK 目录**：压缩后接近 GB，Setup NDK 本身只占二十多秒，缓存传输的成本高于收益。
- **`actions/setup-java` 的 `cache: gradle`**：只恢复依赖，不覆盖 Gradle wrapper 与
  构建状态。

## Consequences

- checks 的并行度从三个作业降为两个，最长作业变长；Android 的
  `flutter build apk --debug` 仍是整体关键路径。
- 升级 `flutter_rust_bridge` 要同时改 `plugins/flspeak_ffi/pubspec.yaml`、
  `FRB_CODEGEN_VERSION` 与 `FRB_CODEGEN_SHA256`；校验和不匹配会让作业在下载步骤失败。
- codegen 附件只覆盖 x86_64 linux，`dart-test` 作业需要留在 `ubuntu-latest` 的 x64
  runner 上。

## Testing

- 本地校验 workflow YAML，并用 `actionlint` 检查三个工作流。
- 用同一附件与校验和模拟下载步骤：正确哈希解出 2.13.0 二进制，错误哈希按预期失败。
- 实际耗时与缓存命中在下一次 main push 后确认。