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
import '../../widgets/app_navigation_sidebar.dart';
import '../../widgets/common.dart';
import '../../widgets/window_header.dart';
import 'settings_state.dart';
import 'widgets/appearance_picker.dart';
import 'widgets/image_host_dialog.dart';
import 'widgets/ptt_hotkey_recorder.dart';
import 'widgets/settings_dialogs.dart';
import 'widgets/settings_section.dart';

enum SettingsCategory { appearance, voice, general, data, about }

/// 设置项页面：左侧全局导航侧边栏，右侧为两级菜单设计（二级占满内容区）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  SettingsCategory? _activeCategory;

  void _back() {
    if (_activeCategory != null) {
      setState(() => _activeCategory = null);
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.workspace);
    }
  }

  Future<void> _pickLanguage(String? current) async {
    final l10n = AppLocalizations.of(context);
    final code = await showSettingsOptions<String>(
      context,
      title: l10n.settingsLanguage,
      options: const ['', 'en', 'zh'],
      current: current ?? '',
      labelBuilder: (context, value) =>
          _localeLabel(l10n, value.isEmpty ? null : value),
    );
    if (!mounted || code == null) {
      return;
    }
    ref
        .read(preferencesProvider.notifier)
        .setLocale(code.isEmpty ? null : code);
  }

  Future<void> _pickMotion(AppMotionPreference current) async {
    final l10n = AppLocalizations.of(context);
    final motion = await showSettingsOptions<AppMotionPreference>(
      context,
      title: l10n.settingsMotion,
      options: AppMotionPreference.values,
      current: current,
      labelBuilder: (context, value) => _motionLabel(l10n, value),
    );
    if (!mounted || motion == null) {
      return;
    }
    ref.read(preferencesProvider.notifier).setMotion(motion);
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
    if (!mounted || source == null) {
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
    if (!mounted || choice == null) {
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
    if (!mounted) return;
    ref
        .read(noticeCenterProvider.notifier)
        .show(l10n.commonCopied, tone: NoticeTone.info);
  }

  Future<void> _pickPttHotkey() async {
    if (ref.read(pttHotkeyRecordingProvider)) return;
    await pickPttHotkey(context, ref);
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

    final isSubPage = _activeCategory != null;

    final String pageTitle = switch (_activeCategory) {
      SettingsCategory.appearance => l10n.settingsTheme,
      SettingsCategory.voice => l10n.settingsVoice,
      SettingsCategory.general => l10n.settingsGeneral,
      SettingsCategory.data => l10n.settingsData,
      SettingsCategory.about => l10n.settingsAbout,
      null => l10n.settingsTitle,
    };

    // 一级概览卡片入口
    final Widget overviewContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        generateSection(
          title: l10n.settingsGeneral,
          items: [
            SettingsTile(
              icon: Icons.palette_outlined,
              title: l10n.settingsTheme,
              subtitle: _themeLabel(l10n, preferences.theme),
              onTap: () =>
                  setState(() => _activeCategory = SettingsCategory.appearance),
            ),
            SettingsTile(
              icon: Icons.headphones_outlined,
              title: l10n.settingsVoice,
              subtitle: view.pttMode
                  ? l10n.settingsPttMode
                  : (audioSelection.inputName ?? l10n.settingsDeviceDefault),
              onTap: () =>
                  setState(() => _activeCategory = SettingsCategory.voice),
            ),
            SettingsTile(
              icon: Icons.tune_rounded,
              title: l10n.settingsGeneral,
              subtitle: _localeLabel(l10n, preferences.locale),
              onTap: () =>
                  setState(() => _activeCategory = SettingsCategory.general),
            ),
            SettingsTile(
              icon: Icons.folder_outlined,
              title: l10n.settingsData,
              subtitle: storePath,
              onTap: () =>
                  setState(() => _activeCategory = SettingsCategory.data),
            ),
            SettingsTile(
              icon: Icons.info_outline_rounded,
              title: l10n.settingsAbout,
              subtitle: l10n.appName,
              onTap: () =>
                  setState(() => _activeCategory = SettingsCategory.about),
            ),
          ],
        ),
      ],
    );

    // 二级页面（占满主区域）
    Widget subPageContent;
    switch (_activeCategory) {
      case SettingsCategory.appearance:
        subPageContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: AppearancePicker(
                value: preferences.theme,
                onChanged: ref.read(preferencesProvider.notifier).setTheme,
              ),
            ),
            generateSection(
              title: l10n.settingsMotion,
              items: [
                SettingsTile(
                  icon: Icons.animation_rounded,
                  title: l10n.settingsMotion,
                  subtitle: _motionLabel(l10n, preferences.motion),
                  onTap: () => unawaited(_pickMotion(preferences.motion)),
                ),
                SettingsTile(
                  icon: Icons.graphic_eq_rounded,
                  title: l10n.settingsVoiceMeter,
                  subtitle: _voiceMeterLabel(
                    l10n,
                    preferences.voiceMeterSource,
                  ),
                  onTap: () =>
                      unawaited(_pickVoiceMeter(preferences.voiceMeterSource)),
                ),
              ],
            ),
          ],
        );
      case SettingsCategory.voice:
        subPageContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            generateSection(
              title: l10n.settingsPttMode,
              items: [
                SettingsTile(
                  icon: Icons.record_voice_over_rounded,
                  title: l10n.settingsPttMode,
                  trailing: Switch(
                    value: view.pttMode,
                    onChanged: (enabled) => unawaited(
                      ref
                          .read(sessionViewProvider.notifier)
                          .setPttMode(enabled),
                    ),
                  ),
                  onTap: () => unawaited(
                    ref
                        .read(sessionViewProvider.notifier)
                        .setPttMode(!view.pttMode),
                  ),
                ),
                SettingsTile(
                  icon: Icons.keyboard_rounded,
                  title: l10n.settingsPttHotkey,
                  subtitle: pttHotkeyKey == null
                      ? l10n.settingsPttHotkeyNone
                      : pttHotkeyDisplayName(pttHotkeyKey),
                  onTap: () => unawaited(_pickPttHotkey()),
                ),
              ],
            ),
            generateSection(
              title: l10n.settingsInputDevice,
              items: [
                SettingsTile(
                  icon: Icons.mic_rounded,
                  title: l10n.settingsInputDevice,
                  subtitle:
                      audioSelection.inputName ?? l10n.settingsDeviceDefault,
                  onTap: () => unawaited(
                    _pickAudioDevice(selection: audioSelection, output: false),
                  ),
                ),
                SettingsTile(
                  icon: Icons.volume_up_rounded,
                  title: l10n.settingsOutputDevice,
                  subtitle:
                      audioSelection.outputName ?? l10n.settingsDeviceDefault,
                  onTap: () => unawaited(
                    _pickAudioDevice(selection: audioSelection, output: true),
                  ),
                ),
              ],
            ),
          ],
        );
      case SettingsCategory.general:
        subPageContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            generateSection(
              title: l10n.settingsLanguage,
              items: [
                SettingsTile(
                  icon: Icons.translate_rounded,
                  title: l10n.settingsLanguage,
                  subtitle: _localeLabel(l10n, preferences.locale),
                  onTap: () => unawaited(_pickLanguage(preferences.locale)),
                ),
                SettingsTile(
                  icon: Icons.cloud_upload_outlined,
                  title: l10n.imageHostTitle,
                  onTap: () => showImageHostSettings(context),
                ),
              ],
            ),
          ],
        );
      case SettingsCategory.data:
        subPageContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            generateSection(
              title: l10n.settingsStorePath,
              items: [
                SettingsTile(
                  icon: Icons.folder_rounded,
                  title: l10n.settingsStorePath,
                  subtitle: storePath,
                  trailing: IconButton(
                    onPressed: () => unawaited(_copyStorePath(storePath)),
                    icon: Icon(
                      Icons.copy_rounded,
                      size: IconSizes.medium,
                      semanticLabel: l10n.commonCopy,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case SettingsCategory.about:
        subPageContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: context.scheme.primaryContainer,
                        borderRadius: Radii.largeAll,
                      ),
                      child: Icon(
                        Icons.record_voice_over_rounded,
                        size: 36,
                        color: context.scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.appName,
                      style: context.texts.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v0.1.0',
                      style: context.texts.bodySmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            generateSection(
              items: [
                SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: l10n.settingsAbout,
                  subtitle: l10n.appName,
                ),
              ],
            ),
          ],
        );
      case null:
        subPageContent = const SizedBox.shrink();
    }

    final rightContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsTopBar(title: pageTitle, onBack: _back),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 32,
              16,
              compact ? 16 : 32,
              40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: isSubPage ? subPageContent : overviewContent,
              ),
            ),
          ),
        ),
      ],
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _back();
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: context.pageColor,
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact)
                  const AppNavigationSidebar(
                    selectedDestination: AppNavDestination.settings,
                  ),
                Expanded(child: rightContent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.header),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
            padding: EdgeInsets.fromLTRB(context.isCompact ? 8 : 12, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  iconSize: IconSizes.toolbar,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    semanticLabel: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: WindowDragRegion(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.titleLarge,
                      ),
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
              size: IconSizes.medium,
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

String _themeLabel(AppLocalizations l10n, AppThemePreference theme) =>
    switch (theme) {
      AppThemePreference.system => l10n.settingsThemeSystem,
      AppThemePreference.light => l10n.settingsThemeLight,
      AppThemePreference.dark => l10n.settingsThemeDark,
    };

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

String _motionLabel(AppLocalizations l10n, AppMotionPreference motion) =>
    switch (motion) {
      AppMotionPreference.system => l10n.settingsMotionSystem,
      AppMotionPreference.on => l10n.settingsMotionOn,
      AppMotionPreference.off => l10n.settingsMotionOff,
    };
