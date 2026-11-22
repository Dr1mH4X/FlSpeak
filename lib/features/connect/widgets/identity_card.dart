import 'dart:typed_data';

import 'package:material_ui/material_ui.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/monogram.dart';
import '../../../widgets/prism.dart';

/// 桌面端身份卡：连接页左侧的「你是谁」。
///
/// 后端目前只有单一身份，所以卡片只展示当前昵称并给一个管理入口；
/// 身份数量仍然透传，等后端支持多身份时这里直接长出列表。
class IdentityCard extends StatelessWidget {
  const IdentityCard({
    required this.nickname,
    required this.onManage,
    this.avatarBytes,
    this.onAvatarTap,
    super.key,
  });

  final String nickname;
  final VoidCallback onManage;
  final Uint8List? avatarBytes;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return SurfaceCard(
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
                      decoration: ShapeDecoration(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.3),
                        shape: AppShape.full,
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
                if (onAvatarTap == null)
                  IdentityAvatar(
                    nickname: nickname,
                    size: 56,
                    image: avatarBytes,
                  )
                else
                  Semantics(
                    button: true,
                    label: l10n.avatarManage,
                    child: AnimatedInkWell(
                      customBorder: AppShape.circle,
                      onTap: onAvatarTap,
                      child: IdentityAvatar(
                        nickname: nickname,
                        size: 56,
                        image: avatarBytes,
                      ),
                    ),
                  ),
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
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onManage,
                  style: ButtonStyle.from(
                    minimumSize: const Size.fromHeight(Sizes.touch),
                  ),
                  icon: const Icon(
                    Icons.badge_outlined,
                    size: IconSizes.medium,
                  ),
                  label: Text(l10n.identityManage),
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
    this.avatarBytes,
    this.onAvatarTap,
    super.key,
  });

  final String nickname;
  final int serverCount;
  final VoidCallback onManage;
  final Uint8List? avatarBytes;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final avatar = IdentityAvatar(
      nickname: nickname,
      size: 40,
      image: avatarBytes,
    );
    final avatarSlot = onAvatarTap == null
        ? avatar
        : Semantics(
            button: true,
            label: l10n.avatarManage,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAvatarTap,
                child: avatar,
              ),
            ),
          );

    return SurfaceCard(
      clip: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            avatarSlot,
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedInkWell(
                onTap: onManage,
                customBorder: AppShape.xl,
                child: Row(
                  children: [
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
                      size: IconSizes.medium,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
