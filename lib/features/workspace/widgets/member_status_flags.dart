import 'package:flutter/material.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

/// 成员行右侧的状态图标，固定按「麦 → 扬声器 → 离开 → 屏幕共享」自左向右对齐。
class MemberStatusFlags extends StatelessWidget {
  const MemberStatusFlags({
    required this.client,
    required this.sharingScreen,
    this.foregroundColor,
    this.streamKey,
    super.key,
  });

  final ClientView client;
  final bool sharingScreen;
  final Color? foregroundColor;
  final Key? streamKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final awayLabel = switch (client.awayMessage) {
      null || '' => l10n.memberAway,
      final message => l10n.memberAwayWith(message),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 服务器回显的设备状态：快照没带标志（null）时不显示。
        if (client.inputMuted ?? false)
          _StatusFlagIcon(
            label: l10n.memberMicMuted,
            icon: Icons.mic_off_rounded,
            color: foregroundColor ?? scheme.error,
          ),
        if (client.outputMuted ?? false)
          _StatusFlagIcon(
            label: l10n.memberSpeakerMuted,
            icon: Icons.volume_off_rounded,
            color: foregroundColor ?? scheme.error,
          ),
        if (client.away ?? false)
          _StatusFlagIcon(
            label: awayLabel,
            icon: Icons.schedule_rounded,
            color: foregroundColor ?? scheme.primary,
          ),
        if (sharingScreen)
          _StatusFlagIcon(
            key: streamKey,
            label: l10n.streamSharing,
            icon: Icons.screen_share_rounded,
            color: foregroundColor ?? scheme.primary,
          ),
      ],
    );
  }
}

class _StatusFlagIcon extends StatelessWidget {
  const _StatusFlagIcon({
    required this.label,
    required this.icon,
    required this.color,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(
        icon,
        size: IconSizes.state,
        color: color,
        semanticLabel: label,
      ),
    );
  }
}
