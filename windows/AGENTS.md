# AGENTS.md — Windows 平台工程

本目录管理 Windows 平台 Win32 / CMake 原生宿主工程。

## 规则与约束

- **原生音频与动态库**：音频由 Windows WASAPI 后端驱动，Rust 编译产物以 `.dll` 随主程序同目录打包发布。
- **打包与安装**：Release 生成 Inno Setup 安装程序（`-setup.exe`）与绿色便携 `.zip` 压缩包，并随包携带 MSVC 运行库；安装包脚本、语言文件与原生图标在 `windows/packaging/exe/` 及 `windows/runner/resources/` 中维护。
- **构建适配**：保持 Visual Studio 2022 / MSVC 构建工具链兼容，不引入 POSIX 独占 API。
