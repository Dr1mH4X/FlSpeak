# Flutter 界面性能与帧预算

本文定义 FlSpeak 前端 UI 线程与光栅线程的强制性反面模式与替代做法；运行期渲染契约与液态玻璃开销见 [Flutter 界面设计规范](../subsystems/ui-design.md)，内置探针与剖析流程见 [fls-ui-performance](../../.agents/skills/fls-ui-performance/SKILL.md)。

## 帧预算基线

60 Hz 屏单帧预算为 `16 ms`，120 Hz 屏为 `8 ms`，Android 上 UI isolate 运行在平台主线程。路由推入、弹出、菜单展开、标签切换与面板调整期间，首帧准备之外的运动阶段不掉帧，并确保单条数据更新引起的重建数、重绘边界数与查询计算开销不随数据总规模增长。

## 列表按需构建

- **错误做法**：在频道树、成员列表、聊天记录、服务器列表或文件清单等随用户数据增长的容器中，使用 `ListView(children: ...)`、`Column` 铺展子项、全量 `generateSection`，或在长列表中继续使用 Flutter 原生 `ListView.builder` / `SliverList`（快速拖动滚动条时沿途子项仍全量 layout）。
- **正确做法**：所有随数据增长的滚动列表通过 [lib/widgets/prism.dart](../../lib/widgets/prism.dart) 使用 `PrismListView` 或 `SliverPrismList`；固定高度行声明 `itemExtent`，变高行提供 `estimatedItemExtent`，行间距通过 `gap` 参数声明而非插入分隔组件。行数上界可控的短页（例如设置概览卡片与有限选项列表）可保持直接构建。

## 重建作用域与窄订阅

- **错误做法**：在页面壳层、顶层路由或行列表宿主直接 `ref.watch(sessionViewProvider)` 或 `ref.watch(preferencesProvider)`，导致网络遥测 1 Hz 采样、说话状态闪烁、连接阶段微调或无关偏好变化触发整屏重建；在列表中让子项依赖整份模型对象而每次全体重绘；在仅依赖宽度的容器中使用 `LayoutBuilder` 导致高频率或竖向拉伸时重排整棵子树；在历史消息滚回视口时为每一行维护独立入场 `AnimationController` 与 `FadeTransition` / `SlideTransition`。
- **正确做法**：通过 `ref.watch(provider.select(...))` 仅订阅本组件实际消费的最小字段或值语义记录，将说话标记、音视频图标、选中高亮与网络状态拆入各自独立的叶级消费组件；通过 `MemoBuilder` 缓存列表行，将影响行渲染的外部状态收入 `inputs`；仅随宽度布局的区域经 `Prism` 桥接使用 `WidthBuilder`；历史消息直接静态挂载，入场动效仅作用于新到达消息并受 `MediaQuery.disableAnimationsOf` 控制。

## 重绘边界与低光栅成本

- **错误做法**：在 `AnimatedBuilder` 内调用或触发父级 `setState` 驱动每帧动画；让高频电平条（50 Hz）、说话光环或四叶加载框直接并入工作区主表面、频道面板或壳层的同一光栅层；对未裁剪尺寸的原图或列表缩略图全分辨率解码后缩放；为每张卡片重复包裹 `Opacity`、离屏 `ImageFilter.blur` / `BackdropFilter` 滤镜层；未获授权或未感知系统减动效（`MediaQuery.disableAnimationsOf`）时仍持续空转动画或默认开启 `LiquidGlassMode`。
- **正确做法**：连续动画与高频波形通过 `CustomPaint` 的 `repaint` 参数直接传递 `Listenable` / `Animation` 并以独立 `RepaintBoundary` 包裹；布局敏感作用域（如 `WidthBuilder`）外围隔离 `RepaintBoundary`，防止子树动画把脏标传播到外层容器；缩略图（如网格与消息内联图片）通过 `RemoteImage` 传入与显示面积和设备像素比匹配的 `cacheWidth` / `cacheHeight` 约束，大图查看保留原图分辨率；常规按钮与卡片阴影优先直接绘制超椭圆表面与色彩层级，少建离屏合成层；默认将 `SessionPreferences.liquidGlass` 设为 `LiquidGlassMode.none`。

## 后台与不可见状态休眠

- **错误做法**：界面进入后台、窗口最小化、页签切出视觉树外或祖先 `TickerMode` 关闭时继续执行 `Timer.periodic` 网络探测或消费 50 Hz `voiceLevelsProvider` 电平流；仅依赖状态标志调用 `setState` 后等待下一次 `build()` 取消订阅（系统切入后台即停止调度帧，`build()` 在后台期间不会执行）；桌面端切到同屏其他窗口触发 `AppLifecycleState.inactive` 时误关闭实时显示；在仍有动画 ticker 运行时使用 `SchedulerBinding.scheduleTask(..., Priority.idle)` 投递空转回调导致每帧反复唤醒事件循环。
- **正确做法**：高频流与周期定时器通过 `WidgetsBindingObserver` 与 `TickerMode.valuesOf(context).enabled` 实施双门控；网络采样与信号流监听（借助 `ref.listenManual` 与 `StreamProvider.autoDispose`）在 `didChangeAppLifecycleState` 与 `didChangeDependencies` 内同步取消与恢复，不等待延迟帧；生命周期在 `hidden`、`paused`、`detached` 休眠，而 `resumed` 与桌面双窗口失焦的 `inactive` 保持活跃；动画停稳后再收尾的操作等待 `AnimationStatus` 完成或路由/动画显式通知，不使用 `Priority.idle` 自旋轮询。

## UI 线程计算与线性复杂度

- **错误做法**：在 `build()` 或列表渲染回调中执行随数据量超线性退化的算法（如每行全表扫描的 $O(C^2)$ 频道树扁平化、重复筛选与整表复制），或把同步阻塞型 I/O、大体积图片解码、协议解析放在 Dart UI 线程执行。
- **正确做法**：树扁平化、成员分组索引与过滤器先采用线性扫描并按不可变引用记忆化（$O(C + N)$）；大数据拷贝量小的计算先在内存结构上降为线性，无法在帧预算内完成的计算任务通过 Flutter `compute` / `Isolate.run` 或下沉 Rust `core/` 异步完成。

## 回归钉入与测量纪律

- **错误做法**：仅靠主观体感或 Flutter `flutter test` JIT 毫秒耗时断言来判定优化有效，或把绝对耗时阈值写死为测试断言。
- **正确做法**：以确定性计数（重建元素数、实际重绘对象数、祖先 `RenderRepaintBoundary` 累积重绘次数、流监听挂起状态与按需挂载子项数）作为单测回归断言（参考 `test/features/workspace/workspace_performance_test.dart`）；真实帧耗时对比在统一 `--profile` / `--release` 构建的目标设备上采集。
