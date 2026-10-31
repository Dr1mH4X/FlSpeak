# AGENTS.md — macOS 平台工程

本目录管理 macOS 平台原生 Cocoa/Flutter 宿主工程。

## 规则与约束

- **权限与沙盒**：麦克风权限（`NSMicrophoneUsageDescription`）与网络权限（`com.apple.security.network.client`）在 Entitlements 与 `Info.plist` 中正确维护，Hardened Runtime 下必须保证 Rust 原生动态库正确签名。
- **构建适配**：支持 Apple Silicon (`arm64`) 与 Intel (`x86_64`) 双架构；Opus 与 cpal 音频依赖由系统 AudioUnit 与 CoreAudio 框架支持。
- **窗口与标题栏**：采用无边框与内容融合设计，窗口自绘顶栏避免与系统红绿灯按钮重叠。
