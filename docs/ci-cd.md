# CI 与发布

## 工作流划分

| 文件 | 触发 | 内容 |
| --- | --- | --- |
| `checks.yml` | `workflow_call` | 可复用的检查作业：`rust`、`dart`、`dart-test` |
| `ci.yml` | main push、PR、手动 | 调用 `checks.yml`，再跑 `desktop` 与 `android` 的 debug 构建 |
| `release.yml` | `v*` tag、手动输入版本号 | `meta`、`checks`、七平台 `build` 矩阵、`publish` |

tag 推送只启动 `release.yml`，平台打包因此只发生一次；main 与 PR 仍由 `ci.yml`
覆盖桌面与 Android 的编译。`release.yml` 的 `build` 通过 `needs: [meta, checks]`
等待检查，任一检查失败时打包矩阵不会启动，手动输入版本号的发版路径也走同一套检查。

## `checks.yml`

| 作业 | 内容 |
| --- | --- |
| `rust` | `cargo fmt --check`、`clippy -D warnings`、`cargo test`（`--all-features`，含音频） |
| `dart` | `dart format --output=none --set-exit-if-changed lib setup.dart`、`flutter analyze` |
| `dart-test` | `flutter test lib`（用例与实现同目录）与插件检查共用一个作业：重跑 `flutter_rust_bridge_codegen generate` 并用 `git diff` 校验生成物，再分析插件。`flutter test` 会触发 native assets 钩子，因此作业装 Rust 音频依赖并缓存 cargo 与钩子产物；两项检查共用这次编译 |

codegen 用官方 release 的 x86_64 linux 预编译附件（版本与 sha256 固定在
`checks.yml` 顶部），不再从源码 `cargo install`；升级 `flutter_rust_bridge` 时把
`plugins/flspeak_ffi/pubspec.yaml`、`FRB_CODEGEN_VERSION` 与 `FRB_CODEGEN_SHA256`
一起改。

两个环境细节：

- **`rust-toolchain.toml` 放在 `plugins/flspeak_ffi/rust/`**：native assets 钩子只在 crate
  目录里找它，找不到就直接失败。因此 cargo 也从那个目录跑（`defaults.run.working-directory`），
  这样锁定的工具链与 10 个 target 才会生效。同目录的 `rustfmt.toml`（`style_edition = "2024"`）
  让 rustfmt 的导入排序与 frb 生成代码一致，否则「生成物最新」与「格式干净」两个闸门会
  互相改写同一个文件。
- **`CMAKE_POLICY_VERSION_MINIMUM=3.5`**：`audiopus_sys` 内置的 Opus 用
  `cmake_minimum_required(VERSION <3.5)`，CMake 4 默认拒绝；没装系统 libopus 的 runner
  只能走源码构建这条路。

`FLUTTER_VERSION` 在 `checks.yml`、`ci.yml`、`release.yml` 各有一份，升级时三处一起改。

## `ci.yml`

调用 `checks.yml`，另有两个平台作业：

| 作业 | 内容 |
| --- | --- |
| `desktop` | linux / windows / macos 各跑一次 `flutter build <platform> --debug`，验证 native assets 钩子能编出 Rust |
| `android` | 装 NDK（链接进 SDK，避免构建时重复下载）后 `flutter build apk --debug`；Gradle 依赖与构建状态由 `gradle/actions/setup-gradle` 缓存 |

## `release.yml`

打 `v*` tag（或手动给版本号）后：

1. `meta` 从 tag 推导版本号；
2. `checks` 调用可复用工作流，覆盖 Rust、Dart、插件与 FFI 生成物；
3. `build` 等待 `meta` 与 `checks`，在 7 个条目上跑
   `dart setup.dart <platform> <arch> --version <version>`，产物上传为 artifact：

   | 平台 | runner | 架构 |
   | --- | --- | --- |
   | android | ubuntu-latest | 通用 APK |
   | windows | windows-2022 | amd64 |
   | windows | windows-11-arm | arm64 |
   | linux | ubuntu-22.04 | amd64 |
   | linux | ubuntu-24.04-arm | arm64 |
   | macos | macos-15-intel | amd64 |
   | macos | macos-latest | arm64 |

4. `publish` 汇总产物，生成 `SHA256SUMS.txt`，用 draft release 发布。

版本号只在 `meta` 作业里从 tag 推导，并通过 `--version` 传给 `setup.dart`；
产物名和 Flutter build name 使用这个值。

## Android 签名

`android/app/build.gradle.kts` 从 `android/key.properties` 或环境变量读取两套签名，
debug 与 release 分开配置，四项齐全才启用：

| 用途 | key.properties 键 | 环境变量 |
| --- | --- | --- |
| debug | `debugStoreFile`、`debugStorePassword`、`debugKeyAlias`、`debugKeyPassword` | `ANDROID_DEBUG_KEYSTORE_PATH`、`ANDROID_DEBUG_KEYSTORE_PASSWORD`、`ANDROID_DEBUG_KEY_ALIAS`、`ANDROID_DEBUG_KEY_PASSWORD` |
| release | `releaseStoreFile`、`releaseStorePassword`、`releaseKeyAlias`、`releaseKeyPassword` | `ANDROID_RELEASE_KEYSTORE_PATH`、`ANDROID_RELEASE_KEYSTORE_PASSWORD`、`ANDROID_RELEASE_KEY_ALIAS`、`ANDROID_RELEASE_KEY_PASSWORD` |

debug 缺省时退回平台默认 debug keystore；release 缺省时退回 debug 配置，方便本地
`flutter run --release`。CI 的 release 打包步骤设置 `REQUIRE_RELEASE_SIGNING=true`，
release 配置不完整时 Gradle 直接失败，release 产物不会在无提示的情况下使用调试密钥。

GitHub secrets 的八个键：

| secret | 内容 |
| --- | --- |
| `ANDROID_DEBUG_KEYSTORE_BASE64` | debug keystore 经 `base64`（单行）编码后的文本 |
| `ANDROID_DEBUG_KEYSTORE_PASSWORD` | debug keystore 密码 |
| `ANDROID_DEBUG_KEY_ALIAS` | debug key alias |
| `ANDROID_DEBUG_KEY_PASSWORD` | debug key 密码 |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | release keystore 经 `base64`（单行）编码后的文本 |
| `ANDROID_RELEASE_KEYSTORE_PASSWORD` | release keystore 密码 |
| `ANDROID_RELEASE_KEY_ALIAS` | release key alias |
| `ANDROID_RELEASE_KEY_PASSWORD` | release key 密码 |

`ci.yml` 的 Android 作业把 debug keystore 还原到 `android/app/debug-upload.jks`；
未配置 `ANDROID_DEBUG_KEYSTORE_BASE64` 时使用 runner 默认 debug keystore，外部 PR
不会因缺 secret 失败。`release.yml` 把 release keystore 还原到
`android/app/release.jks`，四个 release secret 缺一即失败。keystore 文件与
`android/key.properties` 都在 `.gitignore` 里。

本地 `android/key.properties` 示例（路径相对 `android/app/`）：

```properties
debugStoreFile=debug.keystore
debugStorePassword=<密码>
debugKeyAlias=<alias>
debugKeyPassword=<密码>
releaseStoreFile=release.jks
releaseStorePassword=<密码>
releaseKeyAlias=<alias>
releaseKeyPassword=<密码>
```

切换 release 密钥后，已装旧签名的 Android 包无法原地升级，Release 正文要写明需要
卸载重装。

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
flutter test lib          # 会先编 native assets（Rust），故需要上面那组音频依赖
```