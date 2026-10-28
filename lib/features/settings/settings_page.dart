import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/global_hotkey.dart';
import '../../core/hotkey_codes.dart';
import '../../core/models.dart';
import '../../core/notices.dart';
import '../../core/preferences.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'settings_state.dart';
import 'widgets/settings_card.dart';
import 'widgets/appearance_picker.dart';
import 'widgets/settings_dialogs.dart';
import 'widgets/image_host_dialog.dart';

/// 该路由是顶层路由，所以页面自带 Scaffold；从工作区或登录页进入都能原路返回。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  int _selectedSection = 0;
  final _sectionKeys = List.generate(4, (_) => GlobalKey());

  void _jumpTo(int index) {
    setState(() => _selectedSection = index);
    final section = _sectionKeys[index].currentContext;
    if (section != null) {
      Scrollable.ensureVisible(
        section,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        alignment: 0.05,
      );
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      // 工作区用 go() 进入设置页，栈里没有上一页；回到工作区是唯一合理的落点。
      context.go(AppRoutes.workspace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preferences = ref.watch(preferencesProvider);
    final view = ref.watch(sessionViewProvider);
    final audioSelection = ref.watch(audioSelectionProvider);
    final storePath = ref.watch(storePathProvider);
    final compact = context.isCompact;
    final pttHotkeyKey = preferences.pttHotkey == null
        ? null
        : LogicalKeyboardKey.findKeyByKeyId(preferences.pttHotkey!);

    final sections = <Widget>[
      SettingsGroup(
        title: l10n.settingsGeneral,
        children: [
          SettingsRow(
            icon: Icons.cloud_upload_outlined,
            title: l10n.imageHostTitle,
            onTap: () => showImageHostSettings(context),
          ),
          SettingsRow(
            icon: Icons.translate_rounded,
            title: l10n.settingsLanguage,
            subtitle: _localeLabel(l10n, preferences.locale),
            onTap: () => unawaited(_pickLanguage(preferences.locale)),
          ),
        ],
      ),
      SettingsGroup(
        title: l10n.settingsVoice,
        children: [
          SettingsRow(
            icon: Icons.record_voice_over_rounded,
            title: l10n.settingsPttMode,
            trailing: Switch(
              value: view.pttMode,
              onChanged: (enabled) => unawaited(
                ref.read(sessionViewProvider.notifier).setPttMode(enabled),
              ),
            ),
            onTap: () => unawaited(
              ref.read(sessionViewProvider.notifier).setPttMode(!view.pttMode),
            ),
          ),
          SettingsRow(
            icon: Icons.keyboard_rounded,
            title: l10n.settingsPttHotkey,
            subtitle: pttHotkeyKey == null
                ? l10n.settingsPttHotkeyNone
                : pttHotkeyDisplayName(pttHotkeyKey),
            onTap: () => unawaited(_pickPttHotkey()),
          ),
          SettingsRow(
            icon: Icons.mic_rounded,
            title: l10n.settingsInputDevice,
            subtitle: audioSelection.inputName ?? l10n.settingsDeviceDefault,
            onTap: () => unawaited(
              _pickAudioDevice(selection: audioSelection, output: false),
            ),
          ),
          SettingsRow(
            icon: Icons.volume_up_rounded,
            title: l10n.settingsOutputDevice,
            subtitle: audioSelection.outputName ?? l10n.settingsDeviceDefault,
            onTap: () => unawaited(
              _pickAudioDevice(selection: audioSelection, output: true),
            ),
          ),
          SettingsRow(
            icon: Icons.graphic_eq_rounded,
            title: l10n.settingsVoiceMeter,
            subtitle: _voiceMeterLabel(l10n, preferences.voiceMeterSource),
            onTap: () =>
                unawaited(_pickVoiceMeter(preferences.voiceMeterSource)),
          ),
        ],
      ),
      SettingsGroup(
        title: l10n.settingsData,
        children: [
          SettingsRow(
            icon: Icons.folder_rounded,
            title: l10n.settingsStorePath,
            subtitle: storePath,
            trailing: IconButton(
              onPressed: () => unawaited(_copyStorePath(storePath)),
              icon: Icon(
                Icons.copy_rounded,
                size: 18,
                semanticLabel: l10n.commonCopy,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: Sizes.touch,
                height: Sizes.touch,
              ),
            ),
          ),
        ],
      ),
      SettingsGroup(title: l10n.settingsAbout, children: [_about(l10n)]),
    ];

    final titles = [
      l10n.settingsGeneral,
      l10n.settingsVoice,
      l10n.settingsData,
      l10n.settingsAbout,
    ];
    final icons = [
      Icons.tune_rounded,
      Icons.headphones_outlined,
      Icons.folder_outlined,
      Icons.info_outline_rounded,
    ];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsTopBar(onBack: _back),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 40,
              24,
              compact ? 20 : 40,
              40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyedSubtree(
                      key: _sectionKeys.first,
                      child: AppearancePicker(
                        value: preferences.theme,
                        onChanged: ref
                            .read(preferencesProvider.notifier)
                            .setTheme,
                      ),
                    ),
                    sections.first,
                    for (var index = 1; index < sections.length; index++)
                      KeyedSubtree(
                        key: _sectionKeys[index],
                        child: sections[index],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: context.pageColor,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact)
              SizedBox(
                width: 224,
                child: Material(
                  color: context.scheme.surfaceContainerLow,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        child: Text(
                          l10n.appName,
                          style: context.texts.titleLarge,
                        ),
                      ),
                      for (var index = 0; index < titles.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            selected: _selectedSection == index,
                            selectedTileColor: context.scheme.primaryContainer,
                            selectedColor: context.scheme.onPrimaryContainer,
                            leading: Icon(icons[index], size: 20),
                            title: Text(
                              titles[index],
                              style: context.texts.bodyMedium,
                            ),
                            onTap: () => _jumpTo(index),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLanguage(String? current) async {
    final l10n = AppLocalizations.of(context);
    // 空串表示「跟随系统」：null 已经被「用户关掉对话框」占用，不能再用它区分。
    final code = await showSettingsOptions<String>(
      context,
      title: l10n.settingsLanguage,
      options: const ['', 'en', 'zh'],
      current: current ?? '',
      labelBuilder: (context, value) =>
          _localeLabel(l10n, value.isEmpty ? null : value),
    );
    if (code == null) {
      return;
    }
    ref
        .read(preferencesProvider.notifier)
        .setLocale(code.isEmpty ? null : code);
  }

  Future<void> _pickVoiceMeter(VoiceMeterSource current) async {
    final l10n = AppLocalizations.of(context);
    final source = await showSettingsOptions<VoiceMeterSource>(
      context,
      title: l10n.settingsVoiceMeter,
      options: VoiceMeterSource.values,
      current: current,
      labelBuilder: (context, value) => _voiceMeterLabel(l10n, value),
    );
    if (source == null) {
      return;
    }
    ref.read(preferencesProvider.notifier).setVoiceMeterSource(source);
  }

  Future<void> _pickAudioDevice({
    required AudioDeviceSelection selection,
    required bool output,
  }) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showAppModal<AudioDeviceChoice>(
      context,
      title: output ? l10n.settingsOutputDevice : l10n.settingsInputDevice,
      builder: (context) => _AudioDevicePicker(
        output: output,
        selectedId: output ? selection.outputId : selection.inputId,
      ),
    );
    if (choice == null) {
      return;
    }
    final controller = ref.read(audioSelectionProvider.notifier);
    await _applyAudioChange(
      () => output
          ? controller.selectOutput(choice.device)
          : controller.selectInput(choice.device),
    );
  }

  Future<void> _applyAudioChange(Future<void> Function() change) async {
    try {
      await change();
    } on CoreError catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(noticeCenterProvider.notifier).show(describeCoreError(error));
    }
  }

  Future<void> _copyStorePath(String path) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) {
      return;
    }
    ref
        .read(noticeCenterProvider.notifier)
        .show(l10n.commonCopied, tone: NoticeTone.info);
  }

  Future<void> _pickPttHotkey() async {
    final l10n = AppLocalizations.of(context);
    final currentKeyId = ref.read(preferencesProvider).pttHotkey;
    // 录制期间先注销：macOS 的 Carbon 热键在系统层吞按键，不注销就录不到同一个键。
    await const GlobalHotkey().unregister();
    if (!mounted) {
      return;
    }
    await showAppModal<void>(
      context,
      title: l10n.settingsPttHotkeyRecordTitle,
      builder: (context) => _PttHotkeyRecorder(currentKeyId: currentKeyId),
    );
    // 面板里保存/清除都会写偏好，app 层的偏好监听负责重新注册；取消（偏好
    // 没变）时把原绑定注册回去。
    if (ref.read(preferencesProvider).pttHotkey == currentKeyId) {
      await const GlobalHotkey().registerByKeyId(currentKeyId);
    }
  }

  Widget _about(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Text(l10n.appName, style: context.texts.titleMedium),
    );
  }
}

/// 顶栏：返回键 + 页面标题。
class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.header),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
            padding: EdgeInsets.fromLTRB(context.isCompact ? 8 : 0, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  iconSize: 20,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    semanticLabel: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.settingsTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleLarge,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 音频设备选择器：先「系统默认」，再按输入/输出列出设备。
class _AudioDevicePicker extends ConsumerWidget {
  const _AudioDevicePicker({required this.output, required this.selectedId});

  final bool output;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final devices = ref.watch(audioDevicesProvider);
    return devices.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.settingsAudioLoading,
                style: context.texts.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      error: (error, stackTrace) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: context.scheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.settingsAudioUnavailable,
                style: context.texts.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => ref.invalidate(audioDevicesProvider),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
      data: (available) {
        final list = output ? available.outputs : available.inputs;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsOptionRow(
              label: l10n.settingsDeviceDefault,
              selected: selectedId == null,
              onTap: () =>
                  Navigator.of(context).pop(const AudioDeviceChoice(null)),
            ),
            for (final device in list)
              SettingsOptionRow(
                label: device.name,
                selected: device.id == selectedId,
                onTap: () =>
                    Navigator.of(context).pop(AudioDeviceChoice(device)),
              ),
          ],
        );
      },
    );
  }
}

/// 它们不是界面文案，而是语言自己的名字；翻译成「英语」反而认不出来。
String _localeLabel(AppLocalizations l10n, String? locale) => switch (locale) {
  null => l10n.settingsLanguageSystem,
  'en' => 'English',
  'zh' => '中文',
  _ => locale,
};

String _voiceMeterLabel(AppLocalizations l10n, VoiceMeterSource source) =>
    switch (source) {
      VoiceMeterSource.microphone => l10n.settingsVoiceMeterMic,
      VoiceMeterSource.received => l10n.settingsVoiceMeterReceived,
    };

/// 快捷键录制面板：按下任意受支持的键即保存并关闭，Esc 取消。
///
/// 裸修饰键和平台换不出原生键码的键都会被拒，提示换一个。
class _PttHotkeyRecorder extends ConsumerStatefulWidget {
  const _PttHotkeyRecorder({required this.currentKeyId});

  final int? currentKeyId;

  @override
  ConsumerState<_PttHotkeyRecorder> createState() => _PttHotkeyRecorderState();
}

class _PttHotkeyRecorderState extends ConsumerState<_PttHotkeyRecorder> {
  // LogicalKeyboardKey 重写了 ==，只能放非 const 集合。
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
                  size: 20,
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
