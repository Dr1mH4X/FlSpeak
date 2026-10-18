import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 虚线圆角描边。空状态与「添加服务器」行用虚线表达「这里还不是实体」，
/// Flutter 没有内置虚线边框，只能沿路径按段裁切。
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    required this.color,
    required this.radius,
    required this.child,
    this.dash = 5,
    this.gap = 4,
    super.key,
  });

  final Color color;
  final double radius;
  final Widget child;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedBorderPainter(
      color: color,
      radius: radius,
      dash: dash,
      gap: gap,
    ),
    child: child,
  );
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // 内缩半像素，让 1px 描边完整落进绘制区，不被父级裁掉一半。
    final rect = (Offset.zero & size).deflate(0.5);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}
