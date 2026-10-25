# 命令

所有命令都在仓库根目录执行，除非写明 `working-directory`。

日常入口是仓库根的 `justfile`：`just`（或 `just --list`）列出全部任务；`just check` 是提交前的聚合验证，`just ci` 对齐 CI 的静态检查，`just codegen-check` 校验 FFI 生成物。本文保留原始命令，作为各任务的展开与平台细节。

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

只跑档案/协议测试（不碰音频依赖）：

```sh
cargo test -p server -p proto
```

`session` 现在依赖 `audio` 的 `audio` feature（Opus/cpal），跑它需要 Opus 工具链。
仓库根 `.cargo/config.toml` 已设置 `CMAKE_POLICY_VERSION_MINIMUM=3.5`；macOS 上若
`audiopus_sys` 找不到 `pkg-config` 会走内置源码构建，装了 `pkgconf` 可以省掉这一步。

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
dart format lib test setup.dart
flutter analyze --no-fatal-infos
flutter test                              # Dart 单测（test/）
```

`plugins/flspeak_ffi` 单独分析：

```sh
cd plugins/flspeak_ffi && flutter analyze
```

`flutter build` 会通过 native assets 钩子自动编译 Rust（首次会下载
`rust-toolchain.toml` 里列的 10 个 target）。想跳过：`--dart-define` 无效，用
`hooks.user_defines.flspeak_ffi.build_assets=false` 改 `pubspec.yaml`。

## 真实服务器连接测试（手动，不走 CI）

`core/session/tests/live_connect.rs` 默认 `#[ignore]`，只在显式指定时运行；它关闭音频，
不会申请麦克风/扬声器权限：

```sh
cd plugins/flspeak_ffi/rust
FLSPEAK_TEST_SERVER=ts.example.com \
FLSPEAK_TEST_NICKNAME=flspeak-probe \
cargo test -p session --test live_connect -- --ignored --nocapture
```

注意：tsclient-rs 走 UDP 9987。`proto::resolve_target` 会先查标准 DNS 的
`_ts3._udp.<domain>` SRV；最终目标由 `proto::client` 检查一次，DNS 查询失败时回退到档案字面地址。
TSDNS 尚未实现。服务器对访客关闭 `channellist` 时，测试只验证连接与状态，列表调用
会打印权限拒绝而不判失败。

### 最小消息探针（后台等消息）

`core/session/examples/live_probe.rs` 会保持在线，把收到的文本消息**原文**写到 stdout 和
`/tmp/flspeak-probe.log`，用于抓 TS6 图片消息的 BBCode/URL 格式：

```sh
cd plugins/flspeak_ffi/rust
FLSPEAK_TEST_SERVER=example.com \
FLSPEAK_TEST_NICKNAME=flspeak-probe \
FLSPEAK_PROBE_SECONDS=1800 \
cargo run -p session --example live_probe
```

访客身份可能没有服务器广播权限（`insufficient client permissions`）；连接、收消息不受影响。
停止用 Ctrl-C，或把 `FLSPEAK_PROBE_SECONDS` 设小。

## 发版

```sh
dart setup.dart macos arm64 --version 0.2.0   # 内置 flutter build + 归拢产物到 dist/
```

CI 上打 `v*` tag 会从 tag 推导版本号，再按 7 个平台矩阵打包，见 `docs/ci-cd.md`。

## 本地改上游 tsclient-rs

```toml
# Cargo.toml，临时用，不要提交
[patch.crates-io]
tsclient-rs = { path = "../tsclient-rs" }
```
