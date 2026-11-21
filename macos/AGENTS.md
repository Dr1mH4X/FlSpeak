# AGENTS.md — macOS 平台工程

本目录管理 macOS 平台原生 Cocoa/Flutter 宿主工程。

## 规则与约束

- **权限与沙盒**：`Runner/DebugProfile.entitlements` 与 `Runner/Release.entitlements` 严格保留 `com.apple.security.app-sandbox`（禁用 `com.apple.security.temporary-exception.sbpl` 等私有例外，也不引入任何沙盒目录迁移逻辑）；麦克风权限（`NSMicrophoneUsageDescription`）与网络权限（`com.apple.security.network.client`、`com.apple.security.network.server`）在 Entitlements 与 `Info.plist` 中维护，Hardened Runtime 下必须保证 Rust 原生动态库正确签名。
- **全局按键与本地调试签名**：全局按住说话在 App Sandbox 内通过 `Runner/MainFlutterWindow.swift` 的 Listen-Only `CGEventTap` 实现只观察不吞键，依赖系统「输入监控」（Input Monitoring）权限（禁止使用需要辅助功能权限的 `NSEvent.addGlobalMonitorForEvents`）。本地调试构建须使用固定签名证书，避免每次重新编译导致代码签名变化、从而使 TCC 输入监控授权失效。
- **构建适配**：支持 Apple Silicon (`arm64`) 与 Intel (`x86_64`) 双架构；Opus 与 cpal 音频依赖由系统 AudioUnit 与 CoreAudio 框架支持。
- **窗口与标题栏**：采用无边框与内容融合设计，窗口自绘顶栏避免与系统红绿灯按钮重叠。
