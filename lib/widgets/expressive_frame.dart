import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_ui/shapes/shapes.dart';

import '../theme/app_theme.dart';

const Duration _spinPeriod = Duration(milliseconds: 1500);
final Path _cloverPath = MaterialShapes.clover4Leaf.toPath();

class ExpressiveFrame extends StatefulWidget {
  const ExpressiveFrame({
    required this.child,
    this.loading = false,
    this.size = 40,
    this.color,
    super.key,
  });

  final Widget child;
  final bool loading;
  final double size;
  final Color? color;

  @override
  State<ExpressiveFrame> createState() => _ExpressiveFrameState();
}

class _ExpressiveFrameState extends State<ExpressiveFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: _spinPeriod,
  );

  @override
  void initState() {
    super.initState();
    if (widget.loading) {
      _turns.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ExpressiveFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading) {
      _syncSpin();
    }
  }

  void _syncSpin() {
    if (widget.loading) {
      _turns.repeat();
    } else {
      // 四叶花每转 1/4 圈外观对称，结束加载时顺滑停到下一个 1/4 圈。
      final rest = (_turns.value * 4).ceil() / 4;
      _turns.animateTo(rest, duration: _spinPeriod * (rest - _turns.value));
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.color ?? context.scheme.primaryContainer;
    return AnimatedBuilder(
      animation: _turns,
      child: widget.child,
      builder: (context, child) => CustomPaint(
        painter: _CloverPainter(
          path: _cloverPath,
          color: fill,
          rotation: _turns.value * 2 * math.pi,
        ),
        child: SizedBox.square(
          dimension: widget.size,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _CloverPainter extends CustomPainter {
  const _CloverPainter({
    required this.path,
    required this.color,
    required this.rotation,
  });

  final Path path;
  final Color color;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(rotation)
      ..scale(size.width, size.height)
      ..translate(-0.5, -0.5)
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_CloverPainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.rotation != rotation;
}
