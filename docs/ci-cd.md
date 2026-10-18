# CI 与发布

## `ci.yml`

| 作业 | 内容 |
| --- | --- |
| `rust` | `cargo fmt --check`、`clippy -D warnings`、`cargo test`（`--all-features`，含音频） |
| `dart` | `dart format --output=none --set-exit-if-changed lib setup.dart`、`flutter analyze` |
| `plugins` | 重跑 `flutter_rust_bridge_codegen generate` 并用 `git diff` 校验生成物一致；再分析插件 |
| `desktop` | linux / windows / macos 各跑一次 `flutter build <platform> --debug`，验证 native assets 钩子能编出 Rust |
| `android` | 装 NDK 后 `flutter build apk --debug` |

两个环境细节：

- **`rust-toolchain.toml` 放在 `plugins/flspeak_ffi/rust/`**：native assets 钩子只在 crate
  目录里找它，找不到就直接失败。因此 cargo 也从那个目录跑（`defaults.run.working-directory`），
  这样锁定的工具链与 10 个 target 才会生效。同目录的 `rustfmt.toml`（`style_edition = "2024"`）
  让 rustfmt 的导入排序与 frb 生成代码一致，否则「生成物最新」与「格式干净」两个闸门会
  互相改写同一个文件。
- **`CMAKE_POLICY_VERSION_MINIMUM=3.5`**：`audiopus_sys` 内置的 Opus 用
  `cmake_minimum_required(VERSION <3.5)`，CMake 4 默认拒绝；没装系统 libopus 的 runner
  只能走源码构建这条路。

## `release.yml`

打 `v*` tag（或手动给版本号）后：

1. `meta` 从 tag 推导版本号；
2. `build` 在 7 个条目上跑 `dart setup.dart <platform> <arch> --version <version>`，
   产物上传为 artifact：

   | 平台 | runner | 架构 |
   | --- | --- | --- |
   | android | ubuntu-latest | 通用 APK |
   | windows | windows-2022 | amd64 |
   | windows | windows-11-arm | arm64 |
   | linux | ubuntu-22.04 | amd64 |
   | linux | ubuntu-24.04-arm | arm64 |
   | macos | macos-15-intel | amd64 |
   | macos | macos-latest | arm64 |

3. `publish` 汇总产物，生成 `SHA256SUMS.txt`，用 draft release 发布。

版本号只在 `meta` 作业里从 tag 推导，并通过 `--version` 传给 `setup.dart`；
产物名和 Flutter build name 使用这个值。

## `setup.dart` 做了与没做什么

做：读版本号 → `flutter build <platform> --release --build-name/--build-number` →
把平台产物按 `flspeak-<version>-<platform>-<arch>.<ext>` 归拢进 `dist/`。

没做（**已知简化**，需要各自的打包工具）：

- dmg / pkg 与 Apple 公证；
- deb / rpm / AppImage；
- MSI / 安装器与 Windows 代码签名（当前产物是未签名 zip）；
- F-Droid 元数据。

`setup.dart` 还只会给**当前主机**能构建的平台打包：在 macOS 上请求 `windows` 会直接报错
退出，交叉平台打包交给 release 矩阵。

## 本地复现 CI

```sh
# Rust（从 crate 目录跑，吃锁定工具链）
cd plugins/flspeak_ffi/rust
cargo fmt --all -- --check
CMAKE_POLICY_VERSION_MINIMUM=3.5 cargo clippy --workspace --all-targets --all-features -- -D warnings
CMAKE_POLICY_VERSION_MINIMUM=3.5 cargo test --workspace --all-features

# Dart
cd ../../..
flutter pub get && flutter analyze --no-fatal-infos
```
