import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/preferences.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'settings_state.dart';
import 'widgets/settings_card.dart';
import 'widgets/settings_dialogs.dart';

/// 该路由是顶层路由，所以页面自带 Scaffold；从工作区或登录页进入都能原路返回。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
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

    final sections = <Widget>[
      SettingsGroup(
        title: l10n.settingsGeneral,
        children: [
          SettingsRow(
            icon: Icons.translate_rounded,
            title: l10n.settingsLanguage,
            subtitle: _localeLabel(l10n, preferences.locale),
            onTap: () => unawaited(_pickLanguage(preferences.locale)),
          ),
          SettingsRow(
            icon: Icons.palette_outlined,
            title: l10n.settingsTheme,
            subtitle: _themeLabel(l10n, preferences.theme),
            description: l10n.settingsThemeDesc,
            onTap: () => unawaited(_pickTheme(preferences.theme)),
          ),
        ],
      ),
      SettingsGroup(
        title: l10n.settingsVoice,
        children: [
          SettingsRow(
            icon: Icons.record_voice_over_outlined,
            title: l10n.settingsPttMode,
            description: l10n.settingsPttModeDesc,
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
            icon: Icons.mic_none_rounded,
            title: l10n.settingsInputDevice,
            subtitle: audioSelection.inputName ?? l10n.settingsDeviceDefault,
            onTap: () => unawaited(
              _pickAudioDevice(selection: audioSelection, output: false),
            ),
          ),
          SettingsRow(
            icon: Icons.volume_up_outlined,
            title: l10n.settingsOutputDevice,
            subtitle: audioSelection.outputName ?? l10n.settingsDeviceDefault,
            onTap: () => unawaited(
              _pickAudioDevice(selection: audioSelection, output: true),
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: l10n.settingsData,
        children: [
          SettingsRow(
            icon: Icons.folder_outlined,
            title: l10n.settingsStorePath,
            subtitle: storePath,
            description: l10n.settingsStorePathDesc,
            trailing: IconButton(
              tooltip: l10n.commonCopy,
              onPressed: () => unawaited(_copyStorePath(storePath)),
              icon: const Icon(Icons.copy_rounded, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            ),
          ),
        ],
      ),
      SettingsGroup(title: l10n.settingsAbout, children: [_about(l10n)]),
    ];

    return Scaffold(
      backgroundColor: context.pageColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsTopBar(onBack: _back),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24,
                  compact ? 0 : 8,
                  compact ? 16 : 24,
                  32,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: sections,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

  Future<void> _pickTheme(AppThemePreference current) async {
    final l10n = AppLocalizations.of(context);
    final theme = await showSettingsOptions<AppThemePreference>(
      context,
      title: l10n.settingsTheme,
      options: AppThemePreference.values,
      current: current,
      labelBuilder: (context, value) => _themeLabel(l10n, value),
    );
    if (theme == null) {
      return;
    }
    ref.read(preferencesProvider.notifier).setTheme(theme);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeCoreError(error))));
    }
  }

  Future<void> _copyStorePath(String path) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.commonCopied)));
  }

  Widget _about(AppLocalizations l10n) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: Radii.mediumAll,
            ),
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 22,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.appName, style: context.texts.titleMedium),
                const SizedBox(height: 2),
                Text(
                  l10n.settingsAboutTagline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: onBack,
                  iconSize: 20,
                  icon: const Icon(Icons.arrow_back_rounded),
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
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          l10n.settingsAudioUnavailable,
          style: context.texts.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
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

String _themeLabel(AppLocalizations l10n, AppThemePreference theme) =>
    switch (theme) {
      AppThemePreference.system => l10n.settingsThemeSystem,
      AppThemePreference.light => l10n.settingsThemeLight,
      AppThemePreference.dark => l10n.settingsThemeDark,
    };
