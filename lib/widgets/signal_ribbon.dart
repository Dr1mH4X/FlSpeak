import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 通用信号条：把一组 0–1 的采样画成居中的圆角竖条。
///
/// 语音电平与网络延迟共用同一绘制，避免两处各写一份波形。
class SignalRibbon extends StatelessWidget {
  const SignalRibbon({
    required this.values,
    required this.color,
    this.idleHeight = 3,
    this.barWidth = 4,
    this.minGap = 4,
    this.maxGap = 8,
    this.verticalInset = 8,
    super.key,
  });

  /// 从旧到新排列的采样值，超出范围会被钳到 0–1。
  final List<double> values;
  final Color color;
  final double idleHeight;
  final double barWidth;
  final double minGap;
  final double maxGap;

  /// 上下留白；小尺寸轨迹可以收紧，让高低差更明显。
  final double verticalInset;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(
      painter: _SignalRibbonPainter(
        values: values,
        color: color,
        idleHeight: idleHeight,
        barWidth: barWidth,
        minGap: minGap,
        maxGap: maxGap,
        verticalInset: verticalInset,
      ),
    ),
  );
}

class _SignalRibbonPainter extends CustomPainter {
  _SignalRibbonPainter({
    required this.values,
    required this.color,
    required this.idleHeight,
    required this.barWidth,
    required this.minGap,
    required this.maxGap,
    required this.verticalInset,
  });

  final List<double> values;
  final Color color;
  final double idleHeight;
  final double barWidth;
  final double minGap;
  final double maxGap;
  final double verticalInset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || values.isEmpty) {
      return;
    }
    final inset = math.min(12.0, size.width * 0.1);
    final available = size.width - inset * 2;
    final count = ((available + minGap) / (barWidth + minGap)).floor().clamp(
      1,
      40,
    );
    final gap = count == 1
        ? 0.0
        : ((available - count * barWidth) / (count - 1)).clamp(0.0, maxGap);
    final total = count * barWidth + (count - 1) * gap;
    final start = (size.width - total) / 2;
    final center = size.height / 2;
    final maxHeight = math.max(idleHeight, size.height - verticalInset * 2);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var index = 0; index < count; index++) {
      final position = count == 1
          ? 0.0
          : index / (count - 1) * (values.length - 1);
      final left = position.floor();
      final right = position.ceil();
      final fraction = position - left;
      final level = (values[left] * (1 - fraction) + values[right] * fraction)
          .clamp(0.0, 1.0);
      final height = idleHeight + level * (maxHeight - idleHeight);
      paint.color = color.withValues(alpha: 0.24 + level * 0.66);
      final rect = Rect.fromLTWH(
        start + index * (barWidth + gap),
        center - height / 2,
        barWidth,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalRibbonPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.idleHeight != idleHeight ||
      oldDelegate.barWidth != barWidth ||
      oldDelegate.minGap != minGap ||
      oldDelegate.maxGap != maxGap ||
      oldDelegate.verticalInset != verticalInset ||
      !listEquals(oldDelegate.values, values);
}
