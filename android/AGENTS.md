# AGENTS.md — Android 平台工程

本目录管理 Android 平台原生宿主工程与 Gradle 构建配置。

## 规则与约束

- **签名安全**：`android/app/*.jks` 与本地 `android/key.properties` 严禁提交入库。本地通过 `key.properties` 配置，CI/CD 统一通过 GitHub Secrets 动态注入签名。
- **权限规范**：录音权限（`RECORD_AUDIO`）、网络权限（`INTERNET`）与网络状态权限（`ACCESS_NETWORK_STATE`，供 `MainActivity` 通过 `ConnectivityManager` 读取并监听活跃网络 DNS 同步至 Rust）在 `AndroidManifest.xml` 中声明，麦克风权限需在使用时动态申请。
- **构建规范**：NDK 与 C++ 预编译产物通过 `setup.dart` 准备；严禁随意修改 Gradle Wrapper 版本。
