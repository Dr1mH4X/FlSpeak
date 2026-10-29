import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';
import '../../../widgets/press_feedback.dart';

/// 桌面端身份卡：连接页左侧的「你是谁」。
///
/// 后端目前只有单一身份，所以卡片只展示当前昵称并给一个管理入口；
/// 身份数量仍然透传，等后端支持多身份时这里直接长出列表。
class IdentityCard extends StatelessWidget {
  const IdentityCard({
    required this.nickname,
    required this.onManage,
    super.key,
  });

  final String nickname;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return HairlineCard(
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 100,
            color: scheme.primaryContainer,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final height in [
                    12.0,
                    24.0,
                    42.0,
                    58.0,
                    34.0,
                    18.0,
                    44.0,
                    66.0,
                    42.0,
                    24.0,
                    12.0,
                  ])
                    Container(
                      width: 5,
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.3),
                        borderRadius: Radii.pillAll,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IdentityAvatar(nickname: nickname, size: 56),
                const SizedBox(height: 20),
                Text(
                  l10n.identityCurrent,
                  style: context.texts.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.connectIdentityBody,
                  style: context.texts.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: onManage,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(Sizes.touch),
                  ),
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: Text(l10n.identityManage),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.connectLocalIdentity,
                        style: context.texts.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 窄屏身份条：整条都是管理身份的入口，不占首屏。
class IdentityStrip extends StatelessWidget {
  const IdentityStrip({
    required this.nickname,
    required this.serverCount,
    required this.onManage,
    super.key,
  });

  final String nickname;
  final int serverCount;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return HairlineCard(
      clip: true,
      child: AnimatedInkWell(
        onTap: onManage,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IdentityAvatar(nickname: nickname, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyLarge?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.serversUsedBy(serverCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
