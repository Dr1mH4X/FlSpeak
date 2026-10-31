# AGENTS.md — 着色器资源

本目录管理 Flutter Impeller / Skia 自定义片段着色器（Fragment Shaders）。

## 规则与约束

- 着色器代码遵循 Flutter GLSL (SPIR-V) 规范，通过 `pubspec.yaml` 中的 `flutter.shaders` 配置声明引入。
- 保证跨平台兼容性（macOS Metal, Windows/Linux Vulkan/OpenGL, Android Vulkan/GLES），严禁使用平台私有扩展语法。
- 动效与着色器应受全局动效开关（`AppearanceSettings.reduced_motion`）约束，开启减少动效时降级为静态背景。
