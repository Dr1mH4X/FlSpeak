import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../router.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/press_feedback.dart';
import '../workspace_state.dart';
import 'member_permissions_dialog.dart';
import 'kick_client_dialog.dart';

class ClientActionsButton extends ConsumerWidget {
  const ClientActionsButton({
    required this.client,
    this.child = const SizedBox.shrink(),
    super.key,
  });

  final ClientView client;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sessionViewProvider);
    final scheme = context.scheme;
    final selectedMember = ref.watch(selectedMemberProvider);
    final isSelected =
        selectedMember != null &&
        selectedMember.serverId == view.activeServerId &&
        selectedMember.clientId == client.id &&
        selectedMember.uid == client.uid;
    final foreground = isSelected ? scheme.onPrimaryContainer : null;

    final details = Semantics(
      button: true,
      selected: isSelected,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.effectsFast,
        curve: Motion.effectsDefaultCurve,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isSelected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: Radii.mediumAll,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: Radii.mediumAll,
          clipBehavior: Clip.antiAlias,
          child: AnimatedInkWell(
            onTap: () {
              ref
                  .read(selectedMemberProvider.notifier)
                  .select(client, serverId: view.activeServerId);
              ref.read(routerProvider).go(AppRoutes.workspace);
              Scaffold.maybeOf(context)?.closeDrawer();
            },
            borderRadius: Radii.mediumAll,
            child: DefaultTextStyle.merge(
              style: isSelected ? TextStyle(color: foreground) : null,
              child: IconTheme.merge(
                data: isSelected
                    ? IconThemeData(color: foreground)
                    : const IconThemeData(),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    if (client.id == view.selfClientId || client.uid.isEmpty) {
      return details;
    }
    final l10n = AppLocalizations.of(context);
    final access = ref.watch(sessionAccessProvider).asData?.value;
    final canManage =
        (access?.memberAddPower ?? 0) > 0 ||
        (access?.memberRemovePower ?? 0) > 0;
    final stream = view.streamForClient(client.id);
    final isWatchingStream =
        stream != null && view.watchingStreamId == stream.id;
    return SecondaryMenu(
      openOnSecondaryTap: true,
      enabled: view.connected && !view.busy,
      moreSemanticLabel: l10n.memberActions(client.nickname),
      items: [
        if (stream != null)
          MenuItemButton(
            leadingIcon: Icon(
              isWatchingStream
                  ? Icons.stop_screen_share_rounded
                  : Icons.screen_share_rounded,
            ),
            onPressed: () {
              final controller = ref.read(sessionViewProvider.notifier);
              if (isWatchingStream) {
                controller.leaveStream(stream.id);
              } else {
                controller.watchStream(stream);
              }
              ref.read(routerProvider).go(AppRoutes.workspace);
            },
            child: Text(
              isWatchingStream
                  ? l10n.streamStopWatching
                  : l10n.streamWatchScreen,
            ),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.chat_bubble_outline_rounded),
          onPressed: () {
            ref
                .read(sessionViewProvider.notifier)
                .selectDirectRecipient(client.uid, clientId: client.id);
            ref.read(routerProvider).go(AppRoutes.workspace);
          },
          child: Text(l10n.chatDirectAction),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.touch_app_rounded),
          onPressed: () => showAppModal<void>(
            context,
            title: l10n.pokeTitle(client.nickname),
            builder: (_) => _PokeForm(client: client),
          ),
          child: Text(l10n.pokeAction),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.admin_panel_settings_outlined),
          onPressed: canManage
              ? () => showMemberPermissions(context, client)
              : null,
          child: Text(l10n.memberPermissions),
        ),
        for (final target in KickTarget.values)
          MenuItemButton(
            leadingIcon: Icon(
              target == KickTarget.channel
                  ? Icons.logout_rounded
                  : Icons.person_remove_outlined,
            ),
            onPressed:
                view.connected &&
                    !view.busy &&
                    access?.connectionEpoch != null &&
                    (target == KickTarget.channel
                            ? access?.kickChannelPower ?? 0
                            : access?.kickServerPower ?? 0) >
                        0
                ? () => showKickClient(
                    context,
                    client,
                    target,
                    access!.connectionEpoch!,
                  )
                : null,
            child: Text(
              target == KickTarget.channel ? l10n.kickChannel : l10n.kickServer,
            ),
          ),
      ],
      builder: (_, _) => details,
    );
  }
}

class _PokeForm extends ConsumerStatefulWidget {
  const _PokeForm({required this.client});
  final ClientView client;
  @override
  ConsumerState<_PokeForm> createState() => _PokeFormState();
}

class _PokeFormState extends ConsumerState<_PokeForm> {
  final _message = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _message.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final sent = await ref
        .read(sessionViewProvider.notifier)
        .pokeClient(
          widget.client.uid,
          _message.text.trim(),
          clientId: widget.client.id,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (sent) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _message,
          autofocus: true,
          enabled: !_busy,
          decoration: InputDecoration(labelText: l10n.pokeMessage),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: _message,
              builder: (context, value, _) => FilledButton(
                onPressed: _busy || value.text.trim().isEmpty ? null : _send,
                child: Text(l10n.pokeAction),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
