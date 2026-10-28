import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common.dart';

Future<void> showKickClient(
  BuildContext context,
  ClientView client,
  KickTarget target,
  int connectionEpoch,
) => showAppModal<void>(
  context,
  title: target == KickTarget.channel
      ? AppLocalizations.of(context).kickChannel
      : AppLocalizations.of(context).kickServer,
  builder: (_) => _KickForm(
    client: client,
    target: target,
    connectionEpoch: connectionEpoch,
  ),
);

class _KickForm extends ConsumerStatefulWidget {
  const _KickForm({
    required this.client,
    required this.target,
    required this.connectionEpoch,
  });
  final ClientView client;
  final KickTarget target;
  final int connectionEpoch;
  @override
  ConsumerState<_KickForm> createState() => _KickFormState();
}

class _KickFormState extends ConsumerState<_KickForm> {
  final _reason = TextEditingController();
  late final _connection = (
    ref.read(sessionViewProvider).activeServerId,
    ref.read(sessionViewProvider).connectionEpoch,
  );
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _kick() async {
    if (_busy) return;
    final view = ref.read(sessionViewProvider);
    if (!view.connected ||
        _connection != (view.activeServerId, view.connectionEpoch)) {
      return;
    }
    setState(() => _busy = true);
    try {
      final sent = await ref
          .read(sessionViewProvider.notifier)
          .kickClient(
            widget.client.uid,
            widget.client.channelId,
            widget.target,
            _reason.text,
            widget.connectionEpoch,
          );
      if (mounted && sent) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final sameConnection =
        view.connected &&
        _connection == (view.activeServerId, view.connectionEpoch);
    final access = ref.watch(sessionAccessProvider).asData?.value;
    final peer = view.clients
        .where(
          (client) =>
              client.uid == widget.client.uid && client.id != view.selfClientId,
        )
        .firstOrNull;
    final targetAvailable =
        peer != null &&
        (widget.target == KickTarget.server ||
            peer.channelId == widget.client.channelId);
    final allowed =
        access?.connectionEpoch == widget.connectionEpoch &&
        (widget.target == KickTarget.channel
                ? access?.kickChannelPower ?? 0
                : access?.kickServerPower ?? 0) >
            0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.target == KickTarget.channel
              ? l10n.kickChannelConfirm(widget.client.nickname)
              : l10n.kickServerConfirm(widget.client.nickname),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reason,
          enabled: !_busy && sameConnection,
          maxLines: 2,
          decoration: InputDecoration(labelText: l10n.kickReason),
        ),
        if (sameConnection && !targetAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(l10n.kickTargetUnavailable),
          ),
        if (!sameConnection)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(l10n.kickConnectionChanged),
          ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed:
                  _busy || !sameConnection || !targetAvailable || !allowed
                  ? null
                  : _kick,
              child: Text(l10n.kickConfirm),
            ),
          ],
        ),
      ],
    );
  }
}
