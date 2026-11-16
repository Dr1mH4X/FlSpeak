import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart'
    show AppShape, MemoBuilder, SliverPrismList, SurfaceCard;
import '../workspace_state.dart';
import 'client_actions.dart';
import 'member_avatar.dart';
import 'member_status_flags.dart';

class MembersPane extends ConsumerWidget {
  const MembersPane({this.view, required this.channelId, super.key});

  final SessionView? view;
  final int channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final fixedView = view;
    final List<ClientView> clients = fixedView != null
        ? fixedView.clients
        : ref.watch(sessionViewProvider.select((state) => state.clients));
    final String? activeServerId = fixedView != null
        ? fixedView.activeServerId
        : ref.watch(
            sessionViewProvider.select((state) => state.activeServerId),
          );
    final members = clients
        .where((client) => client.channelId == channelId)
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
      child: SizedBox(
        width: 224,
        child: RepaintBoundary(
          child: SurfaceCard(
            shape: AppShape.lg,
            clip: true,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.membersTitle,
                            style: context.texts.titleSmall,
                          ),
                        ),
                        Text(
                          '${members.length}',
                          style: context.texts.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverPrismList(
                    itemCount: members.length,
                    estimatedItemExtent: 52,
                    gap: 4,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      return MemoBuilder(
                        inputs: [member, activeServerId, fixedView],
                        builder: (context) => _MemberPaneRow(
                          member: member,
                          activeServerId: activeServerId,
                          fixedView: fixedView,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberPaneRow extends ConsumerWidget {
  const _MemberPaneRow({
    required this.member,
    required this.activeServerId,
    this.fixedView,
  });

  final ClientView member;
  final String? activeServerId;
  final SessionView? fixedView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final view = fixedView;
    final isSelected = ref.watch(
      selectedMemberProvider.select(
        (selected) =>
            selected != null &&
            selected.serverId == activeServerId &&
            selected.clientId == member.id &&
            selected.uid == member.uid,
      ),
    );
    final speaking = view != null
        ? (view.speaking.contains(member.id) ||
              (member.id == view.selfClientId && view.selfSpeaking))
        : ref.watch(
            sessionViewProvider.select(
              (state) =>
                  state.speaking.contains(member.id) ||
                  (member.id == state.selfClientId && state.selfSpeaking),
            ),
          );
    final sharingScreen = view != null
        ? view.streamForClient(member.id) != null
        : ref.watch(
            sessionViewProvider.select(
              (state) => state.streamForClient(member.id) != null,
            ),
          );
    final foreground = isSelected ? scheme.onPrimaryContainer : null;
    return ClientActionsButton(
      client: member,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            SessionMemberAvatar(
              uid: member.uid,
              nickname: member.nickname,
              size: 36,
              speaking: speaking,
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
                    speaking
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
            MemberStatusFlags(
              client: member,
              sharingScreen: sharingScreen,
              foregroundColor: isSelected ? scheme.onPrimaryContainer : null,
              streamKey: sharingScreen
                  ? ValueKey('member-stream-${member.id}')
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
