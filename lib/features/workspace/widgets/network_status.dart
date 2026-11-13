import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/models.dart';
import '../../../core/network_quality.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart';
import '../../../widgets/signal_ribbon.dart';

/// 用户卡里的网络状态入口。点击后在入口上方展开非模态浮层；
/// 浮层只在打开时构建，关闭后连同采样定时器和信号历史一起释放。
class NetworkStatus extends StatelessWidget {
  const NetworkStatus({
    required this.view,
    required this.channelLabel,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final SessionView view;
  final String channelLabel;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _qualityColor(
      context,
      connected: view.connected,
      telemetry: view.network,
    );
    final label = !view.connected
        ? l10n.sessionConnecting
        : switch (networkQuality(view.network)) {
            NetworkQuality.unknown => l10n.networkMeasuring,
            NetworkQuality.good => l10n.voiceConnected,
            NetworkQuality.degraded => l10n.networkDegraded,
            NetworkQuality.poor => l10n.networkPoor,
          };

    return Row(
      children: [
        Semantics(
          expanded: expanded,
          child: IconButton(
            onPressed: onToggle,
            style: ButtonStyle.from(foregroundColor: color),
            icon: Icon(
              Icons.wifi_rounded,
              size: IconSizes.toolbar,
              semanticLabel: l10n.networkStatus,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.texts.labelMedium?.copyWith(color: color),
              ),
              Text(
                channelLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NetworkTelemetryPanel extends ConsumerStatefulWidget {
  const NetworkTelemetryPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<NetworkTelemetryPanel> createState() =>
      _NetworkTelemetryPanelState();
}

class _NetworkTelemetryPanelState extends ConsumerState<NetworkTelemetryPanel> {
  static const _historyLength = 24;
  static const _sampleInterval = Duration(seconds: 1);

  List<double?> _pingHistory = List<double?>.filled(_historyLength, null);
  List<double?> _lossInHistory = List<double?>.filled(_historyLength, null);
  List<double?> _lossOutHistory = List<double?>.filled(_historyLength, null);
  Timer? _timer;
  NetworkTelemetry? _lastTelemetry;

  @override
  void initState() {
    super.initState();
    final telemetry = ref.read(sessionViewProvider).network;
    if (telemetry != null) {
      _lastTelemetry = telemetry;
      _pingHistory = List<double?>.filled(
        _historyLength,
        _pingLevel(telemetry),
      );
      _lossInHistory = List<double?>.filled(
        _historyLength,
        _lossLevel(telemetry.lossInPercent),
      );
      _lossOutHistory = List<double?>.filled(
        _historyLength,
        _lossLevel(telemetry.lossOutPercent),
      );
    }
    unawaited(ref.read(sessionViewProvider.notifier).sampleNetwork());
    _timer = Timer.periodic(_sampleInterval, (_) {
      unawaited(ref.read(sessionViewProvider.notifier).sampleNetwork());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _append(NetworkTelemetry? telemetry) {
    if (telemetry == null || telemetry == _lastTelemetry) {
      return;
    }
    _lastTelemetry = telemetry;
    _pingHistory = [..._pingHistory.skip(1), _pingLevel(telemetry)];
    _lossInHistory = [
      ..._lossInHistory.skip(1),
      _lossLevel(telemetry.lossInPercent),
    ];
    _lossOutHistory = [
      ..._lossOutHistory.skip(1),
      _lossLevel(telemetry.lossOutPercent),
    ];
  }

  static double? _pingLevel(NetworkTelemetry telemetry) {
    final latency = telemetry.roundTripMs;
    if (latency == null) {
      return telemetry.recentFailurePercent > 0 ? 1 : null;
    }
    return math.sqrt((latency / 200).clamp(0.0, 1.0));
  }

  static double? _lossLevel(double? percent) {
    if (percent == null) {
      return null;
    }
    return math.sqrt((percent / 5).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final (:network, :pinned, :connected) = ref.watch(
      sessionViewProvider.select(
        (state) => (
          network: state.network,
          pinned: state.networkPanelPinned,
          connected: state.connected,
        ),
      ),
    );
    ref.listen<NetworkTelemetry?>(
      sessionViewProvider.select((state) => state.network),
      (_, next) {
        if (next == null || next == _lastTelemetry) {
          return;
        }
        setState(() => _append(next));
      },
    );
    final telemetry = network;
    final color = _qualityColor(
      context,
      connected: connected,
      telemetry: network,
    );
    final animate = !MediaQuery.disableAnimationsOf(context);
    final titleStyle = context.texts.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    );
    final labelStyle = context.texts.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final valueStyle = context.texts.titleMedium?.copyWith(
      color: scheme.onSurface,
      fontFeatures: tabularFigures,
    );

    return ConstrainedBox(
      key: const ValueKey('network-telemetry-panel'),
      constraints: BoxConstraints(
        maxHeight: math.min(320, MediaQuery.sizeOf(context).height * 0.45),
      ),
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final traceWidth = animate
                ? (constraints.maxWidth * 0.26).clamp(30.0, 64.0).toDouble()
                : 0.0;
            final valueWidth = (constraints.maxWidth * 0.24)
                .clamp(42.0, 64.0)
                .toDouble();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: Sizes.touch,
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            l10n.networkStatus,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => ref
                            .read(sessionViewProvider.notifier)
                            .setNetworkPanelPinned(!pinned),
                        isSelected: pinned,
                        icon: Icon(
                          Icons.push_pin_outlined,
                          size: IconSizes.toolbar,
                          semanticLabel: l10n.windowPin,
                        ),
                        selectedIcon: Icon(
                          Icons.push_pin_rounded,
                          size: IconSizes.toolbar,
                          semanticLabel: l10n.windowUnpin,
                        ),
                        style: ButtonStyle.from(
                          foregroundColor: pinned
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          backgroundColor: pinned
                              ? scheme.primaryContainer.withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onClose,
                        style: ButtonStyle.from(
                          foregroundColor: scheme.onSurfaceVariant,
                        ),
                        icon: Icon(
                          Icons.close_rounded,
                          size: IconSizes.toolbar,
                          semanticLabel: l10n.commonClose,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                _MetricTraceRow(
                  label: l10n.networkPing,
                  value: _formatPing(l10n, telemetry),
                  history: _pingHistory,
                  color: color,
                  traceWidth: traceWidth,
                  valueWidth: valueWidth,
                  labelStyle: labelStyle,
                  valueStyle: valueStyle,
                ),
                _MetricTraceRow(
                  label: l10n.networkLossIn,
                  value: _formatPercent(l10n, telemetry?.lossInPercent),
                  history: _lossInHistory,
                  color: color,
                  traceWidth: traceWidth,
                  valueWidth: valueWidth,
                  labelStyle: labelStyle,
                  valueStyle: valueStyle,
                ),
                _MetricTraceRow(
                  label: l10n.networkLossOut,
                  value: _formatPercent(l10n, telemetry?.lossOutPercent),
                  history: _lossOutHistory,
                  color: color,
                  traceWidth: traceWidth,
                  valueWidth: valueWidth,
                  labelStyle: labelStyle,
                  valueStyle: valueStyle,
                ),
                _MetricRow(
                  label: l10n.networkIdleTime,
                  value: _formatIdle(l10n, telemetry?.idleSeconds),
                  labelStyle: labelStyle,
                  valueStyle: valueStyle,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetricTraceRow extends StatelessWidget {
  const _MetricTraceRow({
    required this.label,
    required this.value,
    required this.history,
    required this.color,
    required this.traceWidth,
    required this.valueWidth,
    required this.labelStyle,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final List<double?> history;
  final Color color;
  final double traceWidth;
  final double valueWidth;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
            SizedBox(
              width: valueWidth,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: valueStyle,
              ),
            ),
            if (traceWidth > 0) ...[
              const SizedBox(width: 8),
              ExcludeSemantics(
                child: SizedBox(
                  width: traceWidth,
                  height: 24,
                  child: history.any((value) => value != null)
                      ? SignalRibbon(
                          values: history,
                          color: color,
                          idleHeight: 2,
                          barWidth: 3,
                          minGap: 3,
                          maxGap: 4,
                          verticalInset: 3,
                        )
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ],
        ),
      ),
    );
  }
}

Color _qualityColor(
  BuildContext context, {
  required bool connected,
  required NetworkTelemetry? telemetry,
}) {
  final scheme = context.scheme;
  if (!connected) {
    return scheme.primary;
  }
  return switch (networkQuality(telemetry)) {
    NetworkQuality.unknown => scheme.onSurfaceVariant,
    NetworkQuality.good => context.status.live,
    NetworkQuality.degraded =>
      context.isDark ? Colors.amber.shade300 : const Color(0xFF8A6500),
    NetworkQuality.poor => scheme.error,
  };
}

String _formatPing(AppLocalizations l10n, NetworkTelemetry? telemetry) {
  final latency = telemetry?.roundTripMs;
  if (latency == null) {
    return l10n.networkUnavailable;
  }
  return l10n.networkMilliseconds(latency.round().toString());
}

String _formatPercent(AppLocalizations l10n, double? percent) {
  if (percent == null) {
    return l10n.networkUnavailable;
  }
  final value = percent.toStringAsFixed(1);
  return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}%';
}

String _formatIdle(AppLocalizations l10n, int? seconds) {
  if (seconds == null) {
    return l10n.networkUnavailable;
  }
  final duration = Duration(seconds: math.max(0, seconds));
  final days = duration.inDays.toString().padLeft(2, '0');
  final hours = (duration.inHours % 24).toString().padLeft(2, '0');
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final rest = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$days:$hours:$minutes:$rest';
}
