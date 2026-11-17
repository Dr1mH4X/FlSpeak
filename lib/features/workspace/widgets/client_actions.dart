import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        InputDecoration,
        OutlinedButton,
        PopupMenuItem,
        Switch,
        TextButton,
        TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../router.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/prism.dart';
import '../workspace_state.dart';
import 'member_permissions_dialog.dart';
import 'kick_client_dialog.dart';

class ClientActionsButton extends ConsumerWidget {
  const ClientActionsButton({
    required this.client,
    this.child = const SizedBox.shrink(),
    this.compactMenuOnTap = false,
    this.onShowDetails,
    this.onDirectChat,
    this.onWatchStream,
    super.key,
  });

  final ClientView client;
  final Widget child;
  final bool compactMenuOnTap;
  final VoidCallback? onShowDetails;
  final VoidCallback? onDirectChat;
  final ValueChanged<StreamView>? onWatchStream;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeServerId = ref.watch(
      sessionViewProvider.select((view) => view.activeServerId),
    );
    final isSelf = ref.watch(
      sessionViewProvider.select((view) => view.selfClientId == client.id),
    );
    final scheme = context.scheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final isSelected =
        !compactMenuOnTap &&
        ref.watch(
          selectedMemberProvider.select(
            (selected) =>
                selected != null &&
                selected.serverId == activeServerId &&
                selected.clientId == client.id &&
                selected.uid == client.uid,
          ),
        );
    final foreground = isSelected ? scheme.onPrimaryContainer : null;

    Widget buildTile(VoidCallback? onTap) => Semantics(
      button: true,
      selected: isSelected,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : Motion.effectsFast,
        curve: Motion.effectsDefaultCurve,
        decoration: ShapeDecoration(
          color: isSelected ? scheme.primaryContainer : Colors.transparent,
          shape: AppShape.md,
        ),
        child: ClipRSuperellipse(
          borderRadius: AppRadius.md,
          child: AnimatedInkWell(
            onTap: onTap,
            customBorder: AppShape.md,
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

    if (isSelf || client.uid.isEmpty) {
      if (compactMenuOnTap) {
        return buildTile(client.uid.isNotEmpty ? onShowDetails : null);
      }
      return buildTile(() {
        ref
            .read(selectedMemberProvider.notifier)
            .select(client, serverId: activeServerId);
        ref.read(routerProvider).go(AppRoutes.workspace);
        Scaffold.maybeOf(context)?.closeDrawer();
      });
    }
    final l10n = AppLocalizations.of(context);
    final access = ref.watch(
      sessionAccessProvider.select((value) => value.asData?.value),
    );
    final canManage =
        (access?.memberAddPower ?? 0) > 0 ||
        (access?.memberRemovePower ?? 0) > 0;
    final (:connected, :busy, :stream, :isWatchingStream) = ref.watch(
      sessionViewProvider.select((view) {
        final stream = view.streamForClient(client.id);
        return (
          connected: view.connected,
          busy: view.busy,
          stream: stream,
          isWatchingStream:
              stream != null && view.watchingStreamId == stream.id,
        );
      }),
    );
    final menuItems = [
      if (compactMenuOnTap && onShowDetails != null)
        PopupMenuItem(
          glyph: AppGlyphs.person,
          label: l10n.memberDetails,
          onPressed: onShowDetails,
        ),
      if (stream != null)
        PopupMenuItem(
          glyph: isWatchingStream
              ? AppGlyphs.stopScreenShare
              : AppGlyphs.screenShare,
          label: isWatchingStream
              ? l10n.streamStopWatching
              : l10n.streamWatchScreen,
          onPressed: () {
            final controller = ref.read(sessionViewProvider.notifier);
            if (isWatchingStream) {
              controller.leaveStream(stream.id);
            } else {
              controller.watchStream(stream);
            }
            if (onWatchStream != null) {
              onWatchStream!(stream);
            } else {
              ref.read(routerProvider).go(AppRoutes.workspace);
            }
          },
        ),
      PopupMenuItem(
        glyph: AppGlyphs.chat,
        label: l10n.chatDirectAction,
        onPressed: () {
          ref
              .read(sessionViewProvider.notifier)
              .selectDirectRecipient(client.uid, clientId: client.id);
          if (onDirectChat != null) {
            onDirectChat!();
          } else {
            ref.read(routerProvider).go(AppRoutes.workspace);
          }
        },
      ),
      PopupMenuItem(
        glyph: AppGlyphs.poke,
        label: l10n.pokeAction,
        onPressed: () => showAppModal<void>(
          context,
          title: l10n.pokeTitle(client.nickname),
          builder: (_) => _PokeForm(client: client),
        ),
      ),
      PopupMenuItem(
        glyph: AppGlyphs.permissions,
        label: l10n.memberPermissions,
        onPressed: canManage
            ? () => showMemberPermissions(context, client)
            : null,
      ),
      for (final target in KickTarget.values)
        PopupMenuItem(
          glyph: target == KickTarget.channel
              ? AppGlyphs.logout
              : AppGlyphs.personRemove,
          label: target == KickTarget.channel
              ? l10n.kickChannel
              : l10n.kickServer,
          danger: true,
          onPressed:
              connected &&
                  !busy &&
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
        ),
    ];

    if (compactMenuOnTap) {
      final menuEnabled = connected && !busy;
      return PopupAnchor(
        bare: true,
        placement: PopupPlacement.overAnchorStart,
        targetBuilder: (open) => ContextMenuRegion(
          menuItems: menuEnabled ? menuItems : null,
          child: buildTile(menuEnabled ? open : (onShowDetails ?? () {})),
        ),
        popupBuilder: (_) => PopupMenu(items: menuItems),
      );
    }

    final details = buildTile(() {
      ref
          .read(selectedMemberProvider.notifier)
          .select(client, serverId: activeServerId);
      ref.read(routerProvider).go(AppRoutes.workspace);
      Scaffold.maybeOf(context)?.closeDrawer();
    });

    return SecondaryMenu(
      openOnSecondaryTap: true,
      enabled: connected && !busy,
      moreSemanticLabel: l10n.memberActions(client.nickname),
      items: menuItems,
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
        Text(
          l10n.pokeMessage,
          style: context.texts.bodyMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _message,
          autofocus: true,
          enabled: !_busy,
          decoration: const InputDecoration(),
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
