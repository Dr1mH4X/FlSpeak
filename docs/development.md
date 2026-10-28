# 开发流程

所有命令都在仓库根目录执行，除非写明工作目录。日常入口是仓库根的 `justfile`：`just`（或 `just --list`）列出全部任务，`just check` 是提交前的聚合验证，`just ci` 对齐 CI 的静态检查，`just codegen-check` 校验 FFI 生成物。本文保留原始命令，作为各任务的展开与平台细节。编码反面见 [defensive-patterns.md](defensive-patterns.md)，测试约定见 [testing.md](testing.md)。

## Rust

`rust-toolchain.toml` 与 `rustfmt.toml` 必须待在 `plugins/flspeak_ffi/rust/`（native assets
钩子只在那里找工具链；rustfmt 配置也跟着 crate 走，用来对齐生成代码的导入排序），所以想吃
锁定工具链、想不被生成物干扰，就从那个目录跑 cargo：

```sh
cd plugins/flspeak_ffi/rust
cargo fmt --all                                              # 格式化
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
```

**macOS 上的 Opus 构建**：`audio` 的 `audio` feature 会拉 `audiopus`。系统装了
Homebrew opus 也只是有 `opus.pc`，没有 `pkg-config` 可执行文件时仍会退化成源码构建，而
内置 Opus 的 `cmake_minimum_required(VERSION <3.5)` 会被 CMake 4 拒绝。两种解法选一个：

```sh
brew install pkgconf                       # 让 pkg-config 找到 /opt/homebrew/lib/pkgconfig
CMAKE_POLICY_VERSION_MINIMUM=3.5 cargo test --workspace --all-features   # 或放宽 CMake 策略
```

仓库根 `.cargo/config.toml` 已设置 `CMAKE_POLICY_VERSION_MINIMUM=3.5`；`session` 依赖
`audio` 的 `audio` feature（Opus/cpal），跑它的测试同样需要 Opus 工具链。

Linux 桌面构建需要 `libsecret-1-dev`，用于图片上传配置的安全存储。开发机使用系统包管理器安装；CI 与发布流水线的 Linux 依赖步骤包含该包。

## FFI 绑定

改了 `plugins/flspeak_ffi/rust/src/api/**` 或其中的类型，就要重跑生成：

```sh
cd plugins/flspeak_ffi
flutter_rust_bridge_codegen generate      # 需要 flutter_rust_bridge_codegen 2.13.0
```

生成物：`plugins/flspeak_ffi/rust/src/frb_generated.rs`、
`plugins/flspeak_ffi/lib/src/rust/**`。CI 会重跑并 `git diff` 校验一致性。
配置在 `flutter_rust_bridge.yaml`（`type_64bit_int: true`：频道/客户端 ID 用 Dart `int`）。

## Flutter

```sh
flutter pub get
flutter gen-l10n                          # 改了 arb/ 之后（pub get 也会触发）
dart format lib setup.dart
flutter analyze --no-fatal-infos
flutter test lib                          # Dart 单测（用例与实现同目录）
```

`plugins/flspeak_ffi` 单独分析：

```sh
cd plugins/flspeak_ffi && flutter analyze
```

`flutter build` 会通过 native assets 钩子自动编译 Rust（首次会下载
`rust-toolchain.toml` 里列的 10 个 target）。想跳过：`--dart-define` 无效，用
`hooks.user_defines.flspeak_ffi.build_assets=false` 改 `pubspec.yaml`。

## 开发流程

动手前先读完相关文件与全部需求，不盲目编辑；只修改当前任务涉及的文件，不给未改动的代码补 docstring 或类型注解，避免无谓 diff。注释只写「为什么」，不写「是什么」，且只在逻辑不清晰处添加；标识符与字符串用 ASCII，注释可以用中文。

语言约定：

- Rust：公共类型字段默认 `pub`，与 tsclient-rs 的风格保持一致；内部细节才收窄。
- Dart：业务逻辑不进 UI 层，页面只做展示与转发；文案全部走 `arb/`，不在 widget 里硬编码中文或英文。

## git 约定

提交用 Conventional Commits 格式，标题 ≤100 字符，描述小写开头、结尾不加句号，中文可用：

```text
feat(session): 增加频道切换命令
fix(proto): reject look-alike official domains
docs(boundary): 记录 SRV 与 TSDNS 的取舍
```

不要写 `Co-authored-by:` 署名编码代理。破坏性改动用 `!` 加 `BREAKING CHANGE:` 页脚。发版日志按这些提交归纳，规则见 [release/AGENTS.md](release/AGENTS.md)。

## 发版

```sh
dart setup.dart macos arm64 --version 0.2.0   # 内置 flutter build + 归拢产物到 dist/
```

CI 上打 `v*` tag 会从 tag 推导版本号，再按 7 个平台矩阵打包。发版日志与 Release 正文见 [release/AGENTS.md](release/AGENTS.md)，发布矩阵与已知简化见 [ci-cd.md](ci-cd.md)。

Android 的 debug 与 release 签名分开配置，都写进 `android/key.properties`：debug 用 `debugStoreFile`、`debugStorePassword`、`debugKeyAlias`、`debugKeyPassword`，release 用 `releaseStoreFile`、`releaseStorePassword`、`releaseKeyAlias`、`releaseKeyPassword`（路径相对 `android/app/` 解析）。没有对应配置时 debug 用平台默认调试密钥、release 退回 debug 配置，方便 `flutter run --release`。CI 侧的八个签名 secret 与 `REQUIRE_RELEASE_SIGNING` 见 [ci-cd.md](ci-cd.md)。

## 本地改上游 tsclient-rs

```toml
# 根 Cargo.toml 中临时替换对应依赖，不要提交
[workspace.dependencies]
tsclient-rs = { path = "../tsclient-rs" }
```

调试结束后恢复 `Cargo.toml` 中的依赖来源及对应 `Cargo.lock`，不提交本地路径。上游关系的其余约定见 [项目结构](../.agents/project.md)。
