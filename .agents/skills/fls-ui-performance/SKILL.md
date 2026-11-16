---
name: fls-ui-performance
description: 诊断、剖析与优化 Flutter 界面掉帧、过量重建、整屏重绘、长列表卡顿、图片解码占内存或后台空转时使用；包含内置探针测量方法、确定性计数测试及性能验证流程。
---

# FlSpeak UI 性能诊断与优化

本技能用于测量、定位与验证 FlSpeak 前端 UI 线程、光栅负载与后台空转消耗，坚持零第三方性能包原则，优先固定确定性计数回归测试并在真机 profile/release 构建确认视觉流畅度。

## Sources of truth

- [docs/defensive-patterns/README.md](../../../docs/defensive-patterns/README.md)
- [docs/defensive-patterns/ui-performance.md](../../../docs/defensive-patterns/ui-performance.md)
- [docs/subsystems/ui-design.md](../../../docs/subsystems/ui-design.md)
- [lib/AGENTS.md](../../../lib/AGENTS.md)
- [test/features/workspace/workspace_performance_test.dart](../../../test/features/workspace/workspace_performance_test.dart)

## 工作流步骤

1. **界定测量场景**：明确触发抖动或高负载的单一场景（如 50 Hz 语音电平刷新、1 Hz 网络遥测更新、成员说话态切换、长频道树展开、聊天历史回滚或应用切后台）。
2. **构造足量压测夹具**：使用贴近上限的测试数据集驱动（数十至上百频道、百人级成员与百条以上富文本消息），防止用空视图或 2 行数据掩盖超线性开销。
3. **先数后计时**：用零侵入的 Flutter 内置探针统计确定性计数，定位根因后再动手改动：
   - **重建统计**：临时挂接 `debugOnRebuildDirtyWidget` 记录每帧重建总数与组件类型分布，可用 `element.toDiagnosticsNode().getProperties()` 或沿着祖先 `ComponentElement` 查找最小未重建根。
   - **重绘统计与脏标溯源**：开启 `debugProfilePaintsEnabled = true` 搭配 `debugOnProfilePaint`（跳过仅合成无需重绘的 `ro.isRepaintBoundary && !ro.debugNeedsPaint`），或重置并读取祖先 `RenderRepaintBoundary.debugSymmetricPaintCount` 与 `debugAsymmetricPaintCount`；定位意外标脏来源时临时开启单帧 `debugPrintMarkNeedsLayoutStacks` / `debugPrintMarkNeedsPaintStacks`。
   - **临时探针纪律**：探针脚本可置于对话临时目录，运行时复制到 `test/` 并在单条命令完成后清理，不向仓库遗留临时探针测试文件。
4. **按因施治（规则正文见 `ui-performance.md`）**：按规则选择对应手段收窄 `.select(...)` 订阅、引入 `PrismListView` / `MemoBuilder` / `WidthBuilder`、以 `RepaintBoundary` + `CustomPaint(repaint:)` 隔离高频绘制、补齐 `WidgetsBindingObserver` + `TickerMode` 同步休眠，或为缩略图补齐 `cacheWidth`。
5. **固定计数测试与真机复核**：把能反映瓶颈的关键计数（例如重建上限、祖先边界重绘为 0、长列表按需挂载行数、后台流监听释放）固化进对应测试文件或 `workspace_performance_test.dart`；严禁把 JIT `flutter test` 的毫秒绝对值写成易脆断言。涉及光栅或端到端掉帧的改动，在 `--profile` / `--release` 构建上验证 Android `atrace` 与桌面渲染帧。

## 验证命令

```sh
# 运行工作区性能计数回归测试与界面相关测试
flutter test test/features/workspace/workspace_performance_test.dart test/features/workspace/widgets/voice_activity_ribbon_test.dart test/features/workspace/widgets/network_status_test.dart test/widgets/expressive_frame_test.dart test/widgets/remote_image_test.dart test/features/settings/settings_page_test.dart test/app_test.dart

# Android 帧与表面流水线真机采样（profile 构建）
flutter build apk --profile
```

## 报告要求

列出：
- 测量场景、夹具规模与基线对比数据（重建数、重绘对象数、祖先边界重绘次数；说明来自 `flutter test` JIT 探针或指定平台 profile 真机）。
- 定位到的主要瓶颈、对应根因与采用的规则条目（链接至 `docs/defensive-patterns/ui-performance.md`）。
- 未被修改但核查后放弃或保留的项及其依据。
- 回归测试文件名及全量静态检查与单测通过结果。
