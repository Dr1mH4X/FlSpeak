# AGENTS.md — Cargo 本地与构建配置

本目录管理 Rust Cargo 编译工具链环境与构建脚本配置。

## 规则与约束

- `config.toml` 用于固化构建环境参数（如 Opus CMake 策略版本 `CMAKE_POLICY_VERSION_MINIMUM = "3.5"`）。
- 不在此处硬编码包含特定个人机器路径的配置；所有跨平台构建环境变量应通过 CI 或 `setup.dart` 统一注入。
