import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/image_host.dart';
import '../../../core/notices.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common.dart';

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
          () => _error = switch (error) {
            CoreError_InvalidAddress(:final message) ||
            CoreError_BlockedAddress(:final message) ||
            CoreError_Connection(:final message) ||
            CoreError_Internal(:final message) => message,
          },
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _upload,
              enabled: !_busy,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.imageHostUploadBase,
                hintText: l10n.imageHostUploadHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _public,
              enabled: !_busy,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.imageHostPublicBase,
                hintText: l10n.imageHostPublicHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: l10n.imageHostToken),
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
