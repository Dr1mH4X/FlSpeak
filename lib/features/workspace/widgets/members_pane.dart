import 'package:flutter/material.dart';

import '../../../core/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/monogram.dart';
import 'client_actions.dart';

class MembersPane extends StatelessWidget {
  const MembersPane({required this.view, required this.channelId, super.key});

  final SessionView view;
  final int channelId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
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
          const SizedBox(height: 20),
          for (final member in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                children: [
                  MemberAvatar(
                    label: initialsOf(member.nickname),
                    size: 36,
                    speaking:
                        view.speaking.contains(member.id) ||
                        (member.id == view.selfClientId && view.selfSpeaking),
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
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ClientActionsButton(client: member),
                  if (member.inputMuted ?? false)
                    Icon(
                      Icons.mic_off_rounded,
                      size: IconSizes.small,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: l10n.memberMicMuted,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
