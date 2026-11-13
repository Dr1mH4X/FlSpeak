import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../workspace_state.dart';
import 'client_actions.dart';
import 'member_avatar.dart';

class MembersPane extends ConsumerWidget {
  const MembersPane({required this.view, required this.channelId, super.key});

  final SessionView view;
  final int channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final controller = ref.read(sessionViewProvider.notifier);
    final selectedMember = ref.watch(selectedMemberProvider);
    final members = view.clients
        .where((client) => client.channelId == channelId)
        .toList();
    return Container(
      width: 224,
      margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.largeAll,
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.membersTitle, style: context.texts.titleSmall),
              ),
              Text(
                '${members.length}',
                style: context.texts.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final member in members) ...[
            () {
              final isSelected =
                  selectedMember != null &&
                  selectedMember.serverId == view.activeServerId &&
                  selectedMember.clientId == member.id &&
                  selectedMember.uid == member.uid;
              final foreground = isSelected ? scheme.onPrimaryContainer : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ClientActionsButton(
                  client: member,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        SessionMemberAvatar(
                          uid: member.uid,
                          nickname: member.nickname,
                          size: 36,
                          speaking:
                              view.speaking.contains(member.id) ||
                              (member.id == view.selfClientId &&
                                  view.selfSpeaking),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: foreground,
                                ),
                              ),
                              Text(
                                view.speaking.contains(member.id) ||
                                        (member.id == view.selfClientId &&
                                            view.selfSpeaking)
                                    ? l10n.memberSpeaking
                                    : (member.away ?? false)
                                    ? l10n.memberAway
                                    : l10n.memberListening,
                                style: context.texts.bodySmall?.copyWith(
                                  color: isSelected
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (view.streamForClient(member.id) case final stream?)
                          IconButton(
                            key: ValueKey('member-stream-${member.id}'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              if (view.watchingStreamId == stream.id) {
                                controller.leaveStream(stream.id);
                              } else {
                                controller.watchStream(stream);
                              }
                            },
                            icon: Icon(
                              Icons.screen_share_rounded,
                              size: IconSizes.small,
                              color: isSelected
                                  ? scheme.onPrimaryContainer
                                  : (view.watchingStreamId == stream.id
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant),
                              semanticLabel: view.watchingStreamId == stream.id
                                  ? l10n.streamStopWatching
                                  : l10n.streamWatchScreen,
                            ),
                          ),
                        if (member.inputMuted ?? false)
                          Icon(
                            Icons.mic_off_rounded,
                            size: IconSizes.small,
                            color: isSelected
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                            semanticLabel: l10n.memberMicMuted,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }(),
          ],
        ],
      ),
    );
  }
}
