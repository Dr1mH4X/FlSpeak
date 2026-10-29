import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common.dart';

Future<void> showMemberPermissions(BuildContext context, ClientView client) =>
    showAppModal<void>(
      context,
      title: AppLocalizations.of(context).memberPermissions,
      builder: (_) => _PermissionsForm(client: client),
    );

class _PermissionsForm extends ConsumerStatefulWidget {
  const _PermissionsForm({required this.client});
  final ClientView client;
  @override
  ConsumerState<_PermissionsForm> createState() => _PermissionsFormState();
}

class _PermissionsFormState extends ConsumerState<_PermissionsForm> {
  bool _busy = false;
  late final _target = ref.read(sessionViewProvider).connectionEpoch;
  MemberGroupTarget get _member =>
      (clientId: widget.client.id, uid: widget.client.uid);
  Future<void> _set(MemberGroupView group, bool enabled) async {
    if (_busy || ref.read(sessionViewProvider).connectionEpoch != _target) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionViewProvider.notifier)
          .setMemberGroup(
            widget.client.uid,
            group,
            enabled,
            clientId: widget.client.id,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(memberGroupsProvider(_member));
    final view = ref.watch(sessionViewProvider);
    final available =
        view.connected &&
        view.connectionEpoch == _target &&
        view.clients.any(
          (peer) =>
              peer.id == widget.client.id && peer.uid == widget.client.uid,
        );
    return groups.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.permissionsUnavailable),
          TextButton(
            onPressed: () => ref.invalidate(memberGroupsProvider(_member)),
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
      data: (groups) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final kind in GroupKind.values) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                kind == GroupKind.server
                    ? l10n.serverGroups
                    : l10n.channelGroups,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final group in groups.where((group) => group.kind == kind))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(group.name),
                trailing: kind == GroupKind.server
                    ? Switch(
                        value: group.member,
                        onChanged:
                            !available ||
                                _busy ||
                                !(group.member ? group.canRemove : group.canAdd)
                            ? null
                            : (enabled) => _set(group, enabled),
                      )
                    : TextButton(
                        onPressed:
                            !available || _busy || group.member || !group.canAdd
                            ? null
                            : () => _set(group, true),
                        child: Text(
                          group.member ? l10n.groupCurrent : l10n.groupAssign,
                        ),
                      ),
              ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonClose),
            ),
          ),
        ],
      ),
    );
  }
}
