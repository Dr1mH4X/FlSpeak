import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';

/// 频道栏与主区域之间的分隔条：拖动调整频道栏宽度，双击恢复默认。
///
/// 宽度存在 preferences 里跨启动沿用。拖动过程中只改本地状态，松手才写
/// 一次 `preferences.json`；每帧落盘会把拖动变成同步 IO 抖动。
class ChannelPaneResizer extends ConsumerStatefulWidget {
  const ChannelPaneResizer({
    required this.maxWidth,
    required this.child,
    super.key,
  });

  /// 拖动条自身的可点宽度：细到不抢版面，又要够鼠标点中。
  static const handleWidth = 8.0;

  /// 读屏与键盘每次增减的步长。
  static const step = 16.0;

  /// 拖动条的可击中区域，测试用。
  static const handleKey = ValueKey('channelPaneResizeHandle');

  /// 悬停时浮出的握把，测试用。
  static const gripKey = ValueKey('channelPaneResizeGrip');

  /// 窗口收紧后的上限：主区域至少要留出 [Sizes.mainPaneMin]。
  final double maxWidth;

  final Widget child;

  @override
  ConsumerState<ChannelPaneResizer> createState() => _ChannelPaneResizerState();
}

class _ChannelPaneResizerState extends ConsumerState<ChannelPaneResizer> {
  /// 拖动中的实时宽度；松手后交给 preferences 并置空。
  double? _dragging;

  bool _hovered = false;

  /// 两个上限取小：偏好的最大值，以及窗口允许的宽度。
  double get _upperBound => math.max(
    Sizes.channelPanelMin,
    math.min(Sizes.channelPanelMax, widget.maxWidth),
  );

  double _clamp(double width) =>
      width.clamp(Sizes.channelPanelMin, _upperBound).toDouble();

  /// 当前生效宽度：拖动中优先本地值，否则用存下的偏好（缺省用默认宽度）。
  double get _width => _clamp(_dragging ?? _storedWidth);

  double get _storedWidth =>
      ref.read(preferencesProvider).channelPanelWidth ?? Sizes.channelPanel;

  void _endDrag() {
    final width = _width;
    setState(() => _dragging = null);
    _persist(width);
  }

  /// 与默认宽度一致时写 `null`：偏好里只保留「偏离默认」的值，
  /// 以后改默认值不会让老用户的偏好卡在旧尺寸上。
  void _persist(double width) {
    final rounded = width.roundToDouble();
    final atDefault = (rounded - Sizes.channelPanel).abs() < 0.5;
    ref
        .read(preferencesProvider.notifier)
        .setChannelPanelWidth(atDefault ? null : rounded);
  }

  void _reset() {
    setState(() => _dragging = null);
    ref.read(preferencesProvider.notifier).setChannelPanelWidth(null);
  }

  void _nudge(double delta) => _persist(_clamp(_width + delta));

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final l10n = AppLocalizations.of(context);
    final stored =
        ref.watch(
          preferencesProvider.select((prefs) => prefs.channelPanelWidth),
        ) ??
        Sizes.channelPanel;
    final width = _clamp(_dragging ?? stored);
    final dragging = _dragging != null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.effectsFast;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: width, child: widget.child),
        Semantics(
          slider: true,
          label: l10n.channelPaneResize,
          value: '${width.round()}',
          increasedValue: '${_clamp(width + ChannelPaneResizer.step).round()}',
          decreasedValue: '${_clamp(width - ChannelPaneResizer.step).round()}',
          onIncrease: () => _nudge(ChannelPaneResizer.step),
          onDecrease: () => _nudge(-ChannelPaneResizer.step),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              key: ChannelPaneResizer.handleKey,
              behavior: HitTestBehavior.opaque,
              // 分隔条贴在频道栏右侧：向右拖就是加宽频道栏。
              onHorizontalDragStart: (_) => setState(() => _dragging = width),
              onHorizontalDragUpdate: (details) =>
                  setState(() => _dragging = _clamp(_width + details.delta.dx)),
              onHorizontalDragEnd: (_) => _endDrag(),
              onHorizontalDragCancel: _endDrag,
              onDoubleTap: _reset,
              child: SizedBox(
                width: ChannelPaneResizer.handleWidth,
                child: Center(
                  // 指针靠近时才浮出的握把：告诉用户这里可以拖，
                  // 静止画面里不画任何线。
                  child: AnimatedContainer(
                    key: ChannelPaneResizer.gripKey,
                    duration: duration,
                    curve: Motion.effectsDefaultCurve,
                    width: dragging ? 4 : 3,
                    height: dragging ? 48 : (_hovered ? 32 : 0),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(
                        alpha: dragging ? 1 : 0.72,
                      ),
                      borderRadius: Radii.pillAll,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
