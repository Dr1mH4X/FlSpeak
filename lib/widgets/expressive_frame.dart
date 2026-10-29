import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart'
    show MaterialShapeBorder, MaterialShapes;

import '../theme/app_theme.dart';

class ExpressiveFrame extends StatefulWidget {
  const ExpressiveFrame({
    required this.child,
    this.loading = false,
    this.size = 40,
    this.color,
    this.shapeSeed = 0,
    super.key,
  });

  final Widget child;
  final bool loading;
  final double size;
  final Color? color;
  final int shapeSeed;

  @override
  State<ExpressiveFrame> createState() => _ExpressiveFrameState();
}

class _ExpressiveFrameState extends State<ExpressiveFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
    value: (widget.shapeSeed % 5) / 5,
  );
  final _shape = ShapeBorderTween(
    begin: MaterialShapeBorder(shape: MaterialShapes.cookie4Sided),
    end: MaterialShapeBorder(shape: MaterialShapes.clover4Leaf),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ExpressiveFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.loading && !MediaQuery.disableAnimationsOf(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      // stop 保留加载完成当帧的形状，不切回预设起点。
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ClipPath(
        clipper: ShapeBorderClipper(shape: _shape.evaluate(_controller)!),
        child: ColoredBox(
          color: widget.color ?? context.scheme.primaryContainer,
          child: Center(child: child),
        ),
      ),
    ),
  );
}
