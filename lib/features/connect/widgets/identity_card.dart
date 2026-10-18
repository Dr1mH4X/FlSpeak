import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/monogram.dart';

/// 桌面端身份卡：连接页左侧的「你是谁」。
///
/// 后端目前只有单一身份，所以卡片只展示当前昵称并给一个管理入口；
/// 身份数量仍然透传，等后端支持多身份时这里直接长出列表。
class IdentityCard extends StatelessWidget {
  const IdentityCard({
    required this.nickname,
    required this.identityCount,
    required this.serverCount,
    required this.onManage,
    super.key,
  });

  final String nickname;
  final int identityCount;
  final int serverCount;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: Radii.xxxlAll,
        border: Border.fromBorderSide(hairlineSide(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A171D1B),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IdentityAvatar(nickname: nickname, size: 64),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              l10n.identityCurrent.toUpperCase(),
              style: context.texts.labelSmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.9,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleLarge?.copyWith(height: 1.25),
          ),
          const SizedBox(height: 4),
          if (serverCount > 0)
            Text(
              l10n.serversUsedBy(serverCount),
              maxLines: 2,
              style: context.texts.bodyMedium?.copyWith(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onManage,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(Sizes.touch),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              foregroundColor: scheme.onSurface,
              backgroundColor: scheme.surface,
              textStyle: context.texts.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    l10n.identityManage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$identityCount',
                  style: context.texts.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
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

    return Material(
      color: context.cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.xxlAll,
        side: hairlineSide(context),
      ),
      child: InkWell(
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
