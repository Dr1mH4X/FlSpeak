import 'package:material_ui/material_ui.dart'
    hide FilledButton, InputDecoration, TextButton, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/image_host.dart';
import '../../../core/models.dart';
import '../../../core/notices.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/prism.dart';

Future<void> showImageHostSettings(BuildContext context) => showAppModal<void>(
  context,
  title: AppLocalizations.of(context).imageHostTitle,
  builder: (_) => const _ImageHostForm(),
);

class _ImageHostForm extends ConsumerStatefulWidget {
  const _ImageHostForm();
  @override
  ConsumerState<_ImageHostForm> createState() => _ImageHostFormState();
}

String _describeImageHostError(CoreError error, AppLocalizations l10n) =>
    switch (error) {
      CoreError_InvalidAddress() => l10n.imageHostErrorInvalid,
      CoreError_BlockedAddress() => l10n.imageHostErrorBlocked,
      CoreError_Connection() => l10n.imageHostErrorConnection,
      CoreError_ChannelPasswordRequired() => l10n.channelPasswordWrong,
      CoreError_AvatarTooLarge() ||
      CoreError_AvatarPermissionDenied() ||
      CoreError_AvatarUnsupportedFormat() ||
      CoreError_AvatarUnavailable() => l10n.imageHostErrorInternal,
      CoreError_ImageTooLarge(:final maxBytes) =>
        l10n.chatImageTooLargeWithLimit(formatByteSize(maxBytes)),
      CoreError_ImageUnsupportedFormat() => l10n.chatImageUnsupportedFormat,
      CoreError_Internal() => l10n.imageHostErrorInternal,
    };

class _ImageHostFormState extends ConsumerState<_ImageHostForm> {
  final _upload = TextEditingController();
  final _public = TextEditingController();
  final _token = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _upload.dispose();
    _public.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(imageHostProvider.notifier)
          .save(
            remove
                ? null
                : ImageHostConfiguration(
                    uploadBase: _upload.text.trim(),
                    publicBase: _public.text.trim(),
                    token: _token.text.trim(),
                  ),
          );
      if (mounted) Navigator.of(context).pop();
    } on CoreError catch (error) {
      if (mounted) {
        setState(
          () => _error = _describeImageHostError(
            error,
            AppLocalizations.of(context),
          ),
        );
      }
    } on Exception {
      if (mounted) {
        ref
            .read(noticeCenterProvider.notifier)
            .show(AppLocalizations.of(context).imageHostStorageFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(imageHostProvider);
    return config.when(
      loading: () => const Center(child: ActivityIndicator(size: 36)),
      error: (error, stack) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.imageHostStorageFailed),
          TextButton(
            onPressed: () => ref.invalidate(imageHostProvider),
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
      data: (value) {
        if (!_loaded) {
          _loaded = true;
          _upload.text = value?.uploadBase ?? '';
          _public.text = value?.publicBase ?? '';
          _token.text = value?.token ?? '';
        }
        final labelStyle = context.texts.bodyMedium?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.imageHostUploadBase, style: labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: _upload,
              enabled: !_busy,
              autocorrect: false,
              decoration: InputDecoration(hintText: l10n.imageHostUploadHint),
            ),
            const SizedBox(height: 12),
            Text(l10n.imageHostPublicBase, style: labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: _public,
              enabled: !_busy,
              autocorrect: false,
              decoration: InputDecoration(hintText: l10n.imageHostPublicHint),
            ),
            const SizedBox(height: 12),
            Text(l10n.imageHostToken, style: labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: _token,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (value != null)
                  TextButton(
                    onPressed: _busy ? null : () => _save(remove: true),
                    child: Text(l10n.imageHostRemove),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(l10n.imageHostSave),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
