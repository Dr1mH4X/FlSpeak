import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// 与按钮状态同步的按压反馈；点击区域与语义保持原尺寸。
Widget pressFeedback(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  final pressed =
      states.contains(WidgetState.pressed) &&
      !states.contains(WidgetState.disabled);
  return AnimatedScale(
    scale: pressed ? 0.94 : 1,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: pressed ? 80 : 160),
    curve: Motion.effectsFastCurve,
    child: child,
  );
}

/// 自绘交互区域复用按钮反馈，保留 InkWell 的触摸区域与手势判定。
class AnimatedInkWell extends StatefulWidget {
  const AnimatedInkWell({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.customBorder,
    this.hoverColor,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;
  final Color? hoverColor;

  @override
  State<AnimatedInkWell> createState() => _AnimatedInkWellState();
}

class _AnimatedInkWellState extends State<AnimatedInkWell> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InkWell(
    statesController: _states,
    onTap: widget.onTap,
    onLongPress: widget.onLongPress,
    borderRadius: widget.borderRadius,
    customBorder: widget.customBorder,
    hoverColor: widget.hoverColor,
    child: AnimatedBuilder(
      animation: _states,
      builder: (context, child) => pressFeedback(context, _states.value, child),
      child: widget.child,
    ),
  );
}
