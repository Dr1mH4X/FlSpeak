import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common.dart';

Future<bool> requestChannelPassword(
  BuildContext context,
  WidgetRef ref,
  int channelId,
) async {
  if (!context.mounted) return false;
  final view = ref.read(sessionViewProvider);
  return await showAppModal<bool>(
        context,
        title: AppLocalizations.of(context).channelPasswordTitle,
        builder: (_) => _PasswordForm(
          channelId: channelId,
          serverId: view.activeServerId,
          epoch: view.connectionEpoch,
        ),
      ) ??
      false;
}

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm({
    required this.channelId,
    required this.serverId,
    required this.epoch,
  });
  final int channelId;
  final String? serverId;
  final int epoch;
  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_busy) return;
    final view = ref.read(sessionViewProvider);
    if (!view.connected ||
        view.activeServerId != widget.serverId ||
        view.connectionEpoch != widget.epoch) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final moved = await ref
          .read(sessionViewProvider.notifier)
          .joinChannel(widget.channelId, password: _password.text);
      if (mounted && moved) Navigator.of(context).pop(true);
    } on CoreError_ChannelPasswordRequired {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).channelPasswordWrong,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _password,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: l10n.channelPasswordLabel,
            errorText: _error,
          ),
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: Text(l10n.channelJoinMenu),
            ),
          ],
        ),
      ],
    );
  }
}
