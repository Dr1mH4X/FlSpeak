import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/global_hotkey.dart';
import '../../../core/hotkey_codes.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';

/// 快捷键录制面板：按下任意受支持的键即保存并关闭，Esc 取消。
class PttHotkeyRecorder extends ConsumerStatefulWidget {
  const PttHotkeyRecorder({required this.currentKeyId, super.key});

  final int? currentKeyId;

  @override
  ConsumerState<PttHotkeyRecorder> createState() => _PttHotkeyRecorderState();
}

class _PttHotkeyRecorderState extends ConsumerState<PttHotkeyRecorder> {
  static final _modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.fn,
  };

  final _focus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event is KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (_modifiers.contains(key) || !isSupportedPttHotkey(key)) {
      setState(
        () =>
            _error = AppLocalizations.of(context).settingsPttHotkeyUnsupported,
      );
      return KeyEventResult.handled;
    }
    ref.read(preferencesProvider.notifier).setPttHotkey(key.keyId);
    Navigator.of(context).pop();
    return KeyEventResult.handled;
  }

  void _clear() {
    ref.read(preferencesProvider.notifier).setPttHotkey(null);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final currentKey = widget.currentKeyId == null
        ? null
        : LogicalKeyboardKey.findKeyByKeyId(widget.currentKeyId!);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (currentKey != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Text(
                    l10n.settingsPttHotkey,
                    style: context.texts.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pttHotkeyDisplayName(currentKey),
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.keyboard_rounded,
                  size: IconSizes.toolbar,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.settingsPttHotkeyRecordHint,
                    style: context.texts.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: context.texts.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          if (widget.currentKeyId != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _clear,
                child: Text(l10n.settingsPttHotkeyClear),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> pickPttHotkey(BuildContext context, WidgetRef ref) async {
  if (ref.read(pttHotkeyRecordingProvider)) return;
  final l10n = AppLocalizations.of(context);
  final currentKeyId = ref.read(preferencesProvider).pttHotkey;
  final recording = ref.read(pttHotkeyRecordingProvider.notifier);
  recording.setRecording(true);
  try {
    await const GlobalHotkey().unregister();
    if (!context.mounted) return;
    await showAppModal<void>(
      context,
      title: l10n.settingsPttHotkeyRecordTitle,
      builder: (context) => PttHotkeyRecorder(currentKeyId: currentKeyId),
    );
  } finally {
    recording.setRecording(false);
  }
}
