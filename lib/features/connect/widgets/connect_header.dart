import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';

/// 连接页顶栏：桌面端显示连接状态，窄屏显示应用名。
///
/// 「返回工作区」只在已连接时出现，避免未连接时给出一个进不去的入口。
class ConnectHeader extends StatelessWidget {
  const ConnectHeader({
    required this.desktop,
    required this.connected,
    required this.status,
    required this.statusColor,
    required this.onWorkspace,
    required this.onSettings,
    super.key,
  });

  final bool desktop;
  final bool connected;
  final String status;
  final Color statusColor;
  final VoidCallback onWorkspace;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final animations = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.effectsDefault;

    return SizedBox(
      height: Sizes.header,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: desktop ? 24 : 16),
        child: Row(
          children: [
            // 状态变化要让读屏软件也能感知，视觉上只有一个小圆点。
            Semantics(liveRegion: true, label: status),
            if (desktop) ...[
              AnimatedContainer(
                duration: animations,
                curve: Motion.effectsDefaultCurve,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                child: Text(
                  l10n.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (connected) ...[
              // 按钮宽度的上限让「返回工作区」在极端字号下省略而不是撑破顶栏。
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: FilledButton(
                  onPressed: onWorkspace,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, Sizes.touch),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: Radii.xlAll),
                    textStyle: context.texts.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          l10n.workspaceReturn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (!desktop)
              IconButton(
                tooltip: l10n.settingsTitle,
                onPressed: onSettings,
                iconSize: 20,
                color: scheme.onSurfaceVariant,
                style: IconButton.styleFrom(
                  minimumSize: const Size(Sizes.touch, Sizes.touch),
                  maximumSize: const Size(Sizes.touch, Sizes.touch),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.settings_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
