# AGENTS.md — 主题与视觉样式 (lib/theme)

本规则补充 [../AGENTS.md](../AGENTS.md)，覆盖 `lib/theme/`。

## 规则与约束

- **Material 3 规范**：遵循 Material Design 3 色彩与排版体系，保证深色模式（Dark）与浅色模式（Light）的高对比度与无障碍表现。
- **动效管理**：所有动画曲线与时长受 `AppMotion` 控制；当用户开启「减少动效」时，动画应被跳过或降级为瞬时切换。
- **全屏与无边框适配**：配合桌面端窗口自绘顶栏（Window Chrome），确保窗口阴影、圆角与系统自适应高亮符合平台标准。
