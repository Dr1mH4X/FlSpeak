import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models.dart';
import '../../../core/network_quality.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';

class NetworkStatus extends StatelessWidget {
  const NetworkStatus({
    required this.view,
    required this.channelLabel,
    super.key,
  });

  final SessionView view;
  final String channelLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quality = networkQuality(view.network);
    final color = !view.connected
        ? context.scheme.primary
        : switch (quality) {
            NetworkQuality.unknown => context.scheme.onSurfaceVariant,
            NetworkQuality.good => context.status.live,
            NetworkQuality.degraded =>
              context.isDark ? Colors.amber.shade300 : const Color(0xFF8A6500),
            NetworkQuality.poor => context.scheme.error,
          };
    final label = !view.connected
        ? l10n.sessionConnecting
        : switch (quality) {
            NetworkQuality.unknown => l10n.networkMeasuring,
            NetworkQuality.good => l10n.voiceConnected,
            NetworkQuality.degraded => l10n.networkDegraded,
            NetworkQuality.poor => l10n.networkPoor,
          };
    return Row(
      children: [
        IconButton(
          onPressed: () => showAppModal<void>(
            context,
            title: l10n.networkDetails,
            builder: (_) => const _NetworkDetails(),
          ),
          color: color,
          icon: Icon(
            Icons.wifi_rounded,
            size: IconSizes.toolbar,
            semanticLabel: l10n.networkDetails,
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

class _NetworkDetails extends ConsumerWidget {
  const _NetworkDetails();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final telemetry = view.network;
    if (!view.connected) {
      return Text(
        view.reconnecting ? l10n.sessionConnecting : l10n.workspaceDropped,
      );
    }
    if (telemetry == null) return Text(l10n.networkMeasuring);
    final rows = [
      (
        l10n.networkLatency,
        telemetry.roundTripMs == null
            ? l10n.networkUnavailable
            : l10n.networkMilliseconds(
                telemetry.roundTripMs!.toStringAsFixed(1),
              ),
      ),
      (
        l10n.networkJitter,
        telemetry.jitterMs == null
            ? l10n.networkUnavailable
            : l10n.networkMilliseconds(telemetry.jitterMs!.toStringAsFixed(1)),
      ),
      (
        l10n.networkFailureRate,
        '${telemetry.recentFailurePercent.toStringAsFixed(1)}%',
      ),
      (l10n.networkProbesSent, '${telemetry.probesSent}'),
      (l10n.networkProbesFailed, '${telemetry.probesFailed}'),
      (
        l10n.networkConnectedTime,
        Duration(seconds: telemetry.connectedSeconds)
            .toString()
            .split('.')
            .first,
      ),
      (
        l10n.networkUpdatedAt,
        DateFormat.Hms().format(
          DateTime.fromMillisecondsSinceEpoch(telemetry.sampledAt),
        ),
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            subtitle: SelectableText(value),
          ),
      ],
    );
  }
}
