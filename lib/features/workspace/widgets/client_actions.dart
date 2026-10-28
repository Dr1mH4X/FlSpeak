import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../router.dart';
import '../../../widgets/common.dart';

class ClientActionsButton extends ConsumerWidget {
  const ClientActionsButton({required this.client, super.key});

  final ClientView client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sessionViewProvider);
    if (client.id == view.selfClientId || client.uid.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return MenuAnchor(
      builder: (context, menu, child) => IconButton(
        onPressed: !view.connected || view.busy
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
        iconSize: 18,
        icon: Icon(
          Icons.more_horiz_rounded,
          semanticLabel: l10n.memberActions(client.nickname),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.chat_bubble_outline_rounded),
          onPressed: () {
            ref
                .read(sessionViewProvider.notifier)
                .selectDirectRecipient(client.uid);
            ref.read(routerProvider).go(AppRoutes.workspace);
          },
          child: Text(l10n.chatDirectTag),
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
      ],
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
        .pokeClient(widget.client.uid, _message.text.trim());
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
