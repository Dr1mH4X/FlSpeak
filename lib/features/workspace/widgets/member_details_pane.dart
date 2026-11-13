import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/channel_display.dart';
import '../../../core/notices.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/channel_icon.dart';
import '../../../widgets/monogram.dart';
import '../../../widgets/prism.dart' hide Divider;
import 'member_avatar.dart';

/// 工作区详情面板中的极简用户资料视图。
class MemberDetailsPane extends ConsumerWidget {
  const MemberDetailsPane({
    required this.client,
    this.isOffline = false,
    super.key,
  });

  final ClientView client;
  final bool isOffline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final texts = context.texts;
    final view = ref.watch(sessionViewProvider);
    final compact = context.isCompact;
    final padding = EdgeInsets.all(compact ? 16.0 : 24.0);

    final live = !isOffline && view.connected
        ? view.clients
              .where((peer) => peer.id == client.id && peer.uid == client.uid)
              .firstOrNull
        : null;
    final member = live ?? client;
    final channel = view.channelById(member.channelId);
    final isSpeaking =
        !isOffline &&
        (view.speaking.contains(member.id) ||
            (member.id == view.selfClientId && view.selfSpeaking));

    return SizedBox.expand(
      child: SingleChildScrollView(
        padding: padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 896),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: Radii.largeAll,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hero Header
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SessionMemberAvatar(
                          uid: member.uid,
                          nickname: member.nickname,
                          size: AvatarSize.large,
                          speaking: isSpeaking,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      member.nickname,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: texts.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (isOffline) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.errorContainer,
                                        borderRadius: Radii.pillAll,
                                      ),
                                      child: Text(
                                        l10n.memberUnavailable,
                                        maxLines: 1,
                                        style: texts.labelSmall?.copyWith(
                                          color: scheme.onErrorContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (member.inputMuted == true ||
                                  member.outputMuted == true ||
                                  member.away == true) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    if (member.away == true)
                                      Flexible(
                                        child: _StatusPill(
                                          icon:
                                              Icons.history_toggle_off_rounded,
                                          color: scheme.tertiary,
                                          backgroundColor:
                                              scheme.tertiaryContainer,
                                          textColor: scheme.onTertiaryContainer,
                                          label: switch (member.awayMessage) {
                                            null || '' => l10n.memberAway,
                                            final msg => l10n.memberAwayWith(
                                              msg,
                                            ),
                                          },
                                        ),
                                      ),
                                    if (member.away == true &&
                                        (member.inputMuted == true ||
                                            member.outputMuted == true))
                                      const SizedBox(width: 8),
                                    if (member.inputMuted == true)
                                      _StatusPill(
                                        icon: Icons.mic_off_rounded,
                                        color: scheme.error,
                                        backgroundColor: scheme.errorContainer,
                                        textColor: scheme.onErrorContainer,
                                        label: l10n.memberMicMuted,
                                      ),
                                    if (member.inputMuted == true &&
                                        member.outputMuted == true)
                                      const SizedBox(width: 8),
                                    if (member.outputMuted == true)
                                      _StatusPill(
                                        icon: Icons.volume_off_rounded,
                                        color: scheme.error,
                                        backgroundColor: scheme.errorContainer,
                                        textColor: scheme.onErrorContainer,
                                        label: l10n.memberSpeakerMuted,
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 分割线
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant,
                  ),

                  // 单行精炼属性列表
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (channel != null)
                          _AttributeRow(
                            label: l10n.memberChannel,
                            content: Row(
                              children: [
                                ChannelIcon(
                                  iconId: channel.iconId,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    channelDisplayName(channel),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: texts.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (member.uid.isNotEmpty)
                          _AttributeRow(
                            label: l10n.memberUid,
                            content: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    member.uid,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: texts.bodyMedium?.copyWith(
                                      fontFamily: 'RobotoMono',
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  iconSize: IconSizes.small,
                                  style: ButtonStyle.from(
                                    padding: const EdgeInsets.all(4),
                                    minimumSize: const Size.square(32),
                                  ),
                                  icon: const Icon(Icons.copy_rounded),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: member.uid),
                                    );
                                    if (!context.mounted) return;
                                    ref
                                        .read(noticeCenterProvider.notifier)
                                        .show(
                                          l10n.commonCopied,
                                          tone: NoticeTone.info,
                                        );
                                  },
                                ),
                              ],
                            ),
                          ),
                        if (member.clientType != ClientType.standard ||
                            (member.appName != null &&
                                member.appName!.isNotEmpty))
                          _AttributeRow(
                            label: l10n.memberClientSoftware,
                            content: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    member.clientType == ClientType.bot
                                        ? Icons.smart_toy_rounded
                                        : Icons.electric_bolt_rounded,
                                    size: IconSizes.small,
                                    color: member.clientType == ClientType.bot
                                        ? scheme.tertiary
                                        : scheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    [
                                      member.appName ?? l10n.clientTypeBot,
                                      if (member.appVersion != null &&
                                          member.appVersion!.isNotEmpty)
                                        'v${member.appVersion}',
                                    ].join(' '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: texts.bodyMedium,
                                  ),
                                  if (member.clientType == ClientType.bot &&
                                      member.capabilities.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    for (final cap in member.capabilities)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                scheme.surfaceContainerHighest,
                                            borderRadius: Radii.smallAll,
                                          ),
                                          child: Text(
                                            cap,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: texts.labelSmall?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.textColor,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color textColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: Radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: texts.labelSmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttributeRow extends StatelessWidget {
  const _AttributeRow({required this.label, required this.content});

  final String label;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: texts.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: content),
        ],
      ),
    );
  }
}
