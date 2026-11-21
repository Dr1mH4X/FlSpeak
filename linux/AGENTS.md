# AGENTS.md — Linux 平台工程

本目录管理 Linux 平台 CMake / GTK 原生宿主工程。

## 规则与约束

- **系统依赖**：要求具备 `libasound2-dev` (ALSA) 等 cpal 与音频后端基础库，以及 `libgtk-3-dev`、`libx11-dev`、`libxi-dev`（XInput2）。
- **全局按键监听**：纯 X11 会话通过 `libXi`（XInput2 `XI_RawKeyPress` / `XI_RawKeyRelease`）在根窗口被动观察按键，不吞键且不受锁键掩码影响；原生 Wayland 与 XWayland 会话通过 `GDBus` 接入 `org.freedesktop.portal.GlobalShortcuts`（Portal 不可用时返回 `unsupportedPlatform` 降级为应用内监听，严禁在 XWayland 下伪装 X11 全局注册成功）。
- **打包规范**：CI 统一输出 tar.gz 绿色包与 AppImage 等发布形态，动态库依赖必须正确包含在运行时 `LD_LIBRARY_PATH` 可见路径内。
- **构建适配**：通过 `CMakeLists.txt` 构建原生可执行文件，不得擅自修改 Flutter 嵌入器核心参数。
