# AGENTS.md — Linux 平台工程

本目录管理 Linux 平台 CMake / GTK 原生宿主工程。

## 规则与约束

- **系统依赖**：要求具备 `libasound2-dev` (ALSA) 等 cpal 与音频后端基础库支持。
- **打包规范**：CI 统一输出 tar.gz 绿色包与 AppImage 等发布形态，动态库依赖必须正确包含在运行时 `LD_LIBRARY_PATH` 可见路径内。
- **构建适配**：通过 `CMakeLists.txt` 构建原生可执行文件，不得擅自修改 Flutter 嵌入器核心参数。
