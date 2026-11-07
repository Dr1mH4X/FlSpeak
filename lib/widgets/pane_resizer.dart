import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// 通用分栏拉伸条：支持水平方向（调节侧栏宽度）与垂直方向（调节顶部/底部面板高度）。
///
/// 鼠标靠近时浮现扁胶囊握把，拖动过程中实时更新本地尺寸，松手后触发 [onSizeChanged]，
/// 双击把手触发 [onReset]。支持读屏与键盘增减（[Semantics.slider]）。
class PaneResizer extends StatefulWidget {
  const PaneResizer({
    super.key,
    required this.axis,
    required this.size,
    required this.minSize,
    required this.maxSize,
    this.defaultSize,
    this.step = 16.0,
    this.handleThickness = 8.0,
    this.handleKey,
    this.gripKey,
    required this.semanticLabel,
    required this.onSizeChanged,
    this.onReset,
    this.child,
    this.builder,
  }) : assert(
         child != null || builder != null,
         'Either child or builder must be provided',
       );

  /// 拉伸轴向：[Axis.horizontal] 调节宽度；[Axis.vertical] 调节高度。
  final Axis axis;

  /// 当前生效的受控尺寸（宽度或高度）。
  final double size;

  /// 尺寸下限。
  final double minSize;

  /// 尺寸上限。
  final double maxSize;

  /// 默认推荐尺寸。双击或拖拽接近默认值时可通过 [onReset] 恢复。
  final double? defaultSize;

  /// 读屏与键盘每次增减的步长。
  final double step;

  /// 拖动把手的可触控厚度（横向拉伸时为宽度，纵向拉伸时为高度）。
  final double handleThickness;

  /// 拖动把手的 Key，便于测试击中。
  final Key? handleKey;

  /// 悬停握把的 Key，便于测试定位。
  final Key? gripKey;

  /// 无障碍读屏语义标签。
  final String semanticLabel;

  /// 拖拽结束或键盘修改后的尺寸变更回调。为 `null` 表示恢复默认值。
  final ValueChanged<double?> onSizeChanged;

  /// 双击把手时的重置回调。若未传则默认触发 `onSizeChanged(null)`。
  final VoidCallback? onReset;

  /// 静态固定子组件。若使用 [child]，将自动用 [SizedBox] 约束对应轴向的尺寸。
  final Widget? child;

  /// 动态尺寸子组件构造器。若使用 [builder]，在拖动过程中每次尺寸变化都会传入当前实时尺寸。
  final Widget Function(BuildContext context, double size)? builder;

  @override
  State<PaneResizer> createState() => _PaneResizerState();
}

class _PaneResizerState extends State<PaneResizer> {
  /// 拖动中的实时尺寸；松手后交给 [widget.onSizeChanged] 并置空。
  double? _dragging;

  bool _hovered = false;

  double get _upperBound => math.max(widget.minSize, widget.maxSize);

  double _clamp(double value) =>
      value.clamp(widget.minSize, _upperBound).toDouble();

  double get _effectiveSize => _clamp(_dragging ?? widget.size);

  void _endDrag() {
    final finalSize = _effectiveSize;
    setState(() => _dragging = null);
    if (widget.defaultSize != null &&
        (finalSize - widget.defaultSize!).abs() < 0.5) {
      widget.onSizeChanged(null);
    } else {
      widget.onSizeChanged(finalSize.roundToDouble());
    }
  }

  void _reset() {
    setState(() => _dragging = null);
    if (widget.onReset != null) {
      widget.onReset!();
    } else {
      widget.onSizeChanged(null);
    }
  }

  void _nudge(double delta) {
    final newSize = _clamp(_effectiveSize + delta);
    if (widget.defaultSize != null &&
        (newSize - widget.defaultSize!).abs() < 0.5) {
      widget.onSizeChanged(null);
    } else {
      widget.onSizeChanged(newSize.roundToDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = _effectiveSize;
    final dragging = _dragging != null;
    final isHorizontal = widget.axis == Axis.horizontal;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.effectsFast;

    final handleGrip = Center(
      child: AnimatedContainer(
        key: widget.gripKey,
        duration: duration,
        curve: Motion.effectsDefaultCurve,
        width: isHorizontal
            ? (dragging ? 4.0 : 3.0)
            : (dragging ? 48.0 : (_hovered ? 32.0 : 0.0)),
        height: isHorizontal
            ? (dragging ? 48.0 : (_hovered ? 32.0 : 0.0))
            : (dragging ? 4.0 : 3.0),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: dragging ? 1.0 : 0.72),
          borderRadius: Radii.pillAll,
        ),
      ),
    );

    final handle = Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: '${size.round()}',
      increasedValue: '${_clamp(size + widget.step).round()}',
      decreasedValue: '${_clamp(size - widget.step).round()}',
      onIncrease: () => _nudge(widget.step),
      onDecrease: () => _nudge(-widget.step),
      child: MouseRegion(
        cursor: isHorizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: widget.handleKey,
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: isHorizontal
              ? (_) => setState(() => _dragging = size)
              : null,
          onHorizontalDragUpdate: isHorizontal
              ? (details) => setState(
                  () => _dragging = _clamp(_effectiveSize + details.delta.dx),
                )
              : null,
          onHorizontalDragEnd: isHorizontal ? (_) => _endDrag() : null,
          onHorizontalDragCancel: isHorizontal ? _endDrag : null,
          onVerticalDragStart: !isHorizontal
              ? (_) => setState(() => _dragging = size)
              : null,
          onVerticalDragUpdate: !isHorizontal
              ? (details) => setState(
                  () => _dragging = _clamp(_effectiveSize + details.delta.dy),
                )
              : null,
          onVerticalDragEnd: !isHorizontal ? (_) => _endDrag() : null,
          onVerticalDragCancel: !isHorizontal ? _endDrag : null,
          onDoubleTap: _reset,
          child: SizedBox(
            width: isHorizontal ? widget.handleThickness : null,
            height: !isHorizontal ? widget.handleThickness : null,
            child: handleGrip,
          ),
        ),
      ),
    );

    final sizedContent = widget.builder != null
        ? widget.builder!(context, size)
        : (isHorizontal
              ? SizedBox(width: size, child: widget.child)
              : SizedBox(height: size, child: widget.child));

    if (isHorizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [sizedContent, handle],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [sizedContent, handle],
    );
  }
}
