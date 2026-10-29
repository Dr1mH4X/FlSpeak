import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences.dart';
import '../../../core/providers.dart';
import '../../../core/voice_levels.dart';
import '../../../theme/app_theme.dart';

/// 所选声源的响度历史；电平与连接标记只重建这块画布。
class VoiceActivityRibbon extends ConsumerWidget {
  const VoiceActivityRibbon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(
      preferencesProvider.select((prefs) => prefs.voiceMeterSource),
    );
    final levels = ref.watch(voiceLevelsProvider).value ?? VoiceLevels.silent;
    final connection = ref.watch(
      sessionViewProvider.select(
        (view) => (
          connected: view.connected,
          serverId: view.activeServerId,
          epoch: view.connectionEpoch,
        ),
      ),
    );
    return ExcludeSemantics(
      child: _Ribbon(
        key: ValueKey((connection.serverId, connection.epoch)),
        levels: levels,
        source: source,
        connected: connection.connected,
      ),
    );
  }
}

class _Ribbon extends StatefulWidget {
  const _Ribbon({
    required this.levels,
    required this.source,
    required this.connected,
    super.key,
  });

  final VoiceLevels levels;
  final VoiceMeterSource source;
  final bool connected;

  @override
  State<_Ribbon> createState() => _RibbonState();
}

class _RibbonState extends State<_Ribbon> {
  static const _historyLength = 24;

  /// 最近约 480ms 的电平，每个新读数左移一格。
  List<double> _history = List.filled(_historyLength, 0);

  double get _level => !widget.connected
      ? 0
      : widget.source == VoiceMeterSource.microphone
      ? widget.levels.mic
      : widget.levels.received;

  @override
  void initState() {
    super.initState();
    _history = [..._history.skip(1), _level.clamp(0.0, 1.0).toDouble()];
  }

  @override
  void didUpdateWidget(covariant _Ribbon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.connected) {
      _history = List.filled(_historyLength, 0);
      return;
    }
    final switched = widget.source != oldWidget.source;
    if (switched) {
      _history = List.filled(_historyLength, 0);
    }
    // 每个电平事件都是新对象；其他无关重建保持同一对象，
    // 不会把历史推快。
    if (switched || !identical(widget.levels, oldWidget.levels)) {
      _history = [..._history.skip(1), _level.clamp(0.0, 1.0).toDouble()];
    }
  }

  @override
  Widget build(BuildContext context) {
    // 音频线程已经完成平滑；界面直接绘制，避免插值再次延迟峰值。
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

  static const _barWidth = 4.0;
  static const _minGap = 4.0;
  static const _maxGap = 8.0;
  static const _idleHeight = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || history.isEmpty) {
      return;
    }
    final inset = math.min(12.0, size.width * 0.1);
    final available = size.width - inset * 2;
    final count = ((available + _minGap) / (_barWidth + _minGap)).floor().clamp(
      1,
      40,
    );
    final gap = count == 1
        ? 0.0
        : ((available - count * _barWidth) / (count - 1)).clamp(0.0, _maxGap);
    final total = count * _barWidth + (count - 1) * gap;
    final start = (size.width - total) / 2;
    final center = size.height / 2;
    final maxHeight = math.max(_idleHeight, size.height - 16);
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
      final height = _idleHeight + level * (maxHeight - _idleHeight);
      paint.color = color.withValues(alpha: 0.24 + level * 0.66);
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
