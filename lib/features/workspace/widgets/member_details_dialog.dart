import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/channel_display.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';
import 'member_avatar.dart';

Future<void> showMemberDetails(BuildContext context, ClientView client) {
  final epoch = ProviderScope.containerOf(context)
      .read(sessionViewProvider)
      .connectionEpoch;
  return showAppModal<void>(
    context,
    title: AppLocalizations.of(context).memberDetails,
    builder: (_) => _MemberDetails(
      clientId: client.id,
      uid: client.uid,
      connectionEpoch: epoch,
    ),
  );
}

class _MemberDetails extends ConsumerWidget {
  const _MemberDetails({
    required this.clientId,
    required this.uid,
    required this.connectionEpoch,
  });

  final int clientId;
  final String uid;
  final int connectionEpoch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final member = view.connected && view.connectionEpoch == connectionEpoch
        ? view.clients
              .where((peer) => peer.id == clientId && peer.uid == uid)
              .firstOrNull
        : null;
    if (member == null) {
      return Text(l10n.memberUnavailable);
    }
    final channel = view.channelById(member.channelId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SessionMemberAvatar(
            uid: member.uid,
            nickname: member.nickname,
            size: AvatarSize.extraLarge,
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.memberNickname),
          subtitle: SelectableText(member.nickname),
        ),
        if (member.uid.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.memberUid),
            subtitle: SelectableText(member.uid),
          ),
        if (channel != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.memberChannel),
            subtitle: SelectableText(channelDisplayName(channel)),
          ),
        if (member.clientType != ClientType.standard) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              member.clientType == ClientType.bot
                  ? Icons.smart_toy_rounded
                  : Icons.electric_bolt_rounded,
              color: member.clientType == ClientType.bot
                  ? context.scheme.tertiary
                  : context.scheme.primary,
            ),
            title: Text(l10n.memberClientSoftware),
            subtitle: SelectableText(
              [
                member.appName ?? l10n.clientTypeBot,
                if (member.appVersion != null && member.appVersion!.isNotEmpty)
                  'v${member.appVersion}',
              ].join(' '),
            ),
          ),
          if (member.capabilities.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cap in member.capabilities)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(cap, style: context.texts.labelSmall),
                    ),
                ],
              ),
            ),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(
                view.speaking.contains(member.id) ||
                        (member.id == view.selfClientId && view.selfSpeaking)
                    ? l10n.memberSpeaking
                    : l10n.memberListening,
              ),
            ),
            if (member.inputMuted == true)
              Chip(label: Text(l10n.memberMicMuted)),
            if (member.outputMuted == true)
              Chip(label: Text(l10n.memberSpeakerMuted)),
            if (member.away == true)
              Chip(
                label: Text(switch (member.awayMessage) {
                  null || '' => l10n.memberAway,
                  final message => l10n.memberAwayWith(message),
                }),
              ),
          ],
        ),
      ],
    );
  }
}
