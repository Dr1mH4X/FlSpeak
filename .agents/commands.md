# 命令

所有命令都在仓库根目录执行，除非写明 `working-directory`。

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

只跑核心 crate（不碰音频依赖）：

```sh
cargo test -p policy -p proto -p session
```

## FFI 绑定

改了 `plugins/flspeak_ffi/rust/src/api/**` 或其中的类型，就要重跑生成：

```sh
cd plugins/flspeak_ffi
flutter_rust_bridge_codegen generate      # 需要 flutter_rust_bridge_codegen 2.13.0
```

生成物：`rust/src/frb_generated.rs`、`lib/src/rust/**`。CI 会重跑并 `git diff` 校验一致性。
配置在 `flutter_rust_bridge.yaml`（`type_64bit_int: true`：频道/客户端 ID 用 Dart `int`）。

## Flutter

```sh
flutter pub get
flutter gen-l10n                          # 改了 arb/ 之后（pub get 也会触发）
dart format lib test tool setup.dart
flutter analyze --no-fatal-infos
flutter test
```

`plugins/flspeak_ffi` 单独分析：

```sh
cd plugins/flspeak_ffi && flutter analyze && flutter test
```

`flutter test` / `flutter build` 会通过 native assets 钩子自动编译 Rust（首次会下载
`rust-toolchain.toml` 里列的 10 个 target）。想跳过：`--dart-define` 无效，用
`hooks.user_defines.flspeak_ffi.build_assets=false` 改 `pubspec.yaml`。

## 闸门

```sh
bash tool/audit_policy.sh                 # 官方域名只出现在策略层
bash tool/check_commit_msg_test.sh        # 提交信息闸门自测
bash tool/check_commit_msg.sh .git/COMMIT_EDITMSG   # 单条提交信息
```

## 发版

```sh
bash tool/set_version.sh 0.2.0 1          # 写 pubspec.yaml 与 workspace Cargo.toml
dart setup.dart macos arm64                # 内置 flutter build + 归拢产物到 dist/
```

CI 上打 `v*` tag 会自动跑 `tool/set_version.sh` 再按 7 个平台矩阵打包，见
`docs/ci-cd.md`。

## 本地改上游 tsclient-rs

```toml
# Cargo.toml，临时用，不要提交
[patch.crates-io]
tsclient-rs = { path = "../tsclient-rs" }
```