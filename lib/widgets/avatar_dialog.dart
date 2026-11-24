import 'dart:typed_data';

import 'package:material_ui/material_ui.dart'
    hide FilledButton, IconButton, TextButton;
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/identity/avatars.dart';
import '../core/models.dart';
import '../core/notices.dart';
import '../core/providers.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'monogram.dart';
import 'prism.dart';

Future<void> showAvatarDialog(
  BuildContext context, {
  required String uid,
  required String nickname,
}) {
  return showAppModal<void>(
    context,
    title: AppLocalizations.of(context).avatarTitle,
    builder: (_) => _AvatarDialogContent(uid: uid, nickname: nickname),
  );
}

class _AvatarDialogContent extends ConsumerStatefulWidget {
  const _AvatarDialogContent({required this.uid, required this.nickname});

  final String uid;
  final String nickname;

  @override
  ConsumerState<_AvatarDialogContent> createState() =>
      _AvatarDialogContentState();
}

class _AvatarDialogContentState extends ConsumerState<_AvatarDialogContent> {
  Uint8List? _picked;
  bool _busy = false;

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context);
    try {
      final bytes = await ref.read(avatarInputProvider).pick();
      if (!mounted || bytes == null) return;
      setState(() => _picked = bytes);
    } on AvatarInputException catch (error) {
      if (!mounted) return;
      ref
          .read(noticeCenterProvider.notifier)
          .show(
            error.failure == AvatarInputFailure.tooLarge
                ? l10n.avatarTooLargeWithLimit(formatByteSize(maxAvatarBytes()))
                : l10n.avatarUnavailable,
          );
    } on Object {
      if (!mounted) return;
      ref.read(noticeCenterProvider.notifier).show(l10n.avatarUnavailable);
    }
  }

  Future<void> _save() async {
    final bytes = _picked;
    if (bytes == null || _busy) return;
    setState(() => _busy = true);
    final saved = await ref
        .read(sessionViewProvider.notifier)
        .uploadAvatar(bytes);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = false);
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    final deleted = await ref.read(sessionViewProvider.notifier).deleteAvatar();
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(memberAvatarProvider(widget.uid)).asData?.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
            color: surfaceColorFor(context.raisedSurfaceLevel, context.scheme),
            shape: AppShape.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MemberAvatar(
                label: initialsOf(widget.nickname),
                image: _picked ?? current,
                size: 120,
                onSurface: true,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.avatarChoose),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : _delete,
              child: Text(l10n.avatarDelete),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: _busy || _picked == null ? null : _save,
              child: _busy
                  ? const ActivityIndicator(size: 18)
                  : Text(l10n.commonSave),
            ),
          ],
        ),
      ],
    );
  }
}
