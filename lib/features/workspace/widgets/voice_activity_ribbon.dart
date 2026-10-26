import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences.dart';
import '../../../core/providers.dart';
import '../../../core/voice_levels.dart';
import '../../../theme/app_theme.dart';

/// 用户卡背景：跟随所选声源的一段电平历史。
///
/// 只订阅 `voiceLevelsProvider`，10Hz 的更新不会牵动频道树。柱子用 M3
/// 的 primary 与圆角画成；静止时是几乎不可见的一条基线。
class VoiceActivityRibbon extends ConsumerWidget {
  const VoiceActivityRibbon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(
      preferencesProvider.select((prefs) => prefs.voiceMeterSource),
    );
    final levels = ref.watch(voiceLevelsProvider).value ?? VoiceLevels.silent;
    return ExcludeSemantics(
      child: _Ribbon(levels: levels, source: source),
    );
  }
}

class _Ribbon extends StatefulWidget {
  const _Ribbon({required this.levels, required this.source});

  final VoiceLevels levels;
  final VoiceMeterSource source;

  @override
  State<_Ribbon> createState() => _RibbonState();
}

class _RibbonState extends State<_Ribbon> {
  static const _historyLength = 24;

  /// 最近约 2.4 秒的电平；每来一个 10Hz 样本左移一格。
  List<double> _history = List.filled(_historyLength, 0);

  double get _level => widget.source == VoiceMeterSource.microphone
      ? widget.levels.mic
      : widget.levels.received;

  @override
  void didUpdateWidget(covariant _Ribbon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final switched = widget.source != oldWidget.source;
    if (switched) {
      _history = List.filled(_historyLength, 0);
    }
    // `VoiceLevels` 每个 10Hz 事件都是新对象；其他无关重建保持同一对象，
    // 不会把历史推快。
    if (switched || !identical(widget.levels, oldWidget.levels)) {
      _history = [..._history.skip(1), _level.clamp(0.0, 1.0).toDouble()];
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _RibbonPainter(
          history: _history,
          color: context.scheme.primary,
        ),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({required this.history, required this.color});

  final List<double> history;
  final Color color;

  static const _barWidth = 3.0;
  static const _minGap = 4.0;
  static const _maxGap = 12.0;
  static const _idleHeight = 3.0;
  static const _maxHeight = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || history.isEmpty) {
      return;
    }
    final count = ((size.width - 24) / (_barWidth + _minGap)).floor().clamp(
      16,
      32,
    );
    final gap = count == 1
        ? 0.0
        : ((size.width - 24 - count * _barWidth) / (count - 1)).clamp(
            _minGap,
            _maxGap,
          );
    final total = count * _barWidth + (count - 1) * gap;
    final start = (size.width - total) / 2;
    final center = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var index = 0; index < count; index++) {
      final position = count == 1
          ? 0.0
          : index / (count - 1) * (history.length - 1);
      final left = position.floor();
      final right = position.ceil();
      final fraction = position - left;
      final level = (history[left] * (1 - fraction) + history[right] * fraction)
          .clamp(0.0, 1.0);
      final height = _idleHeight + level * (_maxHeight - _idleHeight);
      paint.color = color.withValues(alpha: 0.10 + level * 0.24);
      final rect = Rect.fromLTWH(
        start + index * (_barWidth + gap),
        center - height / 2,
        _barWidth,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(_barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter oldDelegate) =>
      oldDelegate.color != color || !listEquals(oldDelegate.history, history);
}
