import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/directory_launcher.dart';
import '../../core/global_hotkey.dart';
import '../../core/hotkey_codes.dart';
import '../../core/models.dart';
import '../../core/notices.dart';
import '../../core/preferences.dart';
import '../../core/providers.dart';
import '../../core/update_check.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation_sidebar.dart';
import '../../widgets/common.dart';
import '../../widgets/update_dot.dart';
import '../../widgets/window_header.dart';
import 'settings_state.dart';
import 'widgets/about_card.dart';
import 'widgets/appearance_picker.dart';
import 'widgets/image_host_dialog.dart';
import 'widgets/ptt_hotkey_recorder.dart';
import 'widgets/settings_dialogs.dart';
import 'widgets/settings_section.dart';

enum SettingsCategory { appearance, general, data, about }

enum GeneralSubcategory { voice, screenShare }

/// 设置项页面：左侧全局导航侧边栏，右侧为多级菜单设计（二级/三级占满内容区）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  SettingsCategory? _activeCategory;
  GeneralSubcategory? _activeGeneralSubcategory;

  void _back() {
    if (_activeGeneralSubcategory != null) {
      setState(() => _activeGeneralSubcategory = null);
      return;
    }
    if (_activeCategory != null) {
      setState(() => _activeCategory = null);
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (router != null) {
      final view = ref.read(sessionViewProvider);
      router.go(view.connected ? AppRoutes.workspace : AppRoutes.connect);
    }
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

  Future<void> _pickScreenShareResolution(
    ScreenShareResolutionPreset current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final preset = await showSettingsOptions<ScreenShareResolutionPreset>(
      context,
      title: l10n.settingsScreenShareResolution,
      options: ScreenShareResolutionPreset.values,
      current: current,
      labelBuilder: (context, value) =>
          _screenShareResolutionLabel(l10n, value),
    );
    if (!mounted || preset == null) {
      return;
    }
    ref.read(preferencesProvider.notifier).setScreenShareResolution(preset);
  }

  Future<void> _pickScreenShareFrameRate(
    ScreenShareFrameRatePreset current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final preset = await showSettingsOptions<ScreenShareFrameRatePreset>(
      context,
      title: l10n.settingsScreenShareFrameRate,
      options: ScreenShareFrameRatePreset.values,
      current: current,
      labelBuilder: (context, value) => _screenShareFrameRateLabel(l10n, value),
    );
    if (!mounted || preset == null) {
      return;
    }
    ref.read(preferencesProvider.notifier).setScreenShareFrameRate(preset);
  }

  Future<void> _pickScreenShareCodec(ScreenShareCodecPreference current) async {
    final l10n = AppLocalizations.of(context);
    final codec = await showSettingsOptions<ScreenShareCodecPreference>(
      context,
      title: l10n.settingsScreenShareCodec,
      options: ScreenShareCodecPreference.values,
      current: current,
      labelBuilder: (context, value) => _screenShareCodecLabel(l10n, value),
    );
    if (!mounted || codec == null) {
      return;
    }
    ref.read(preferencesProvider.notifier).setScreenShareCodec(codec);
  }

  Future<void> _pickScreenShareDegradation(
    ScreenShareDegradationPreference current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final degradation =
        await showSettingsOptions<ScreenShareDegradationPreference>(
          context,
          title: l10n.settingsScreenShareDegradation,
          options: ScreenShareDegradationPreference.values,
          current: current,
          labelBuilder: (context, value) =>
              _screenShareDegradationLabel(l10n, value),
        );
    if (!mounted || degradation == null) {
      return;
    }
    ref
        .read(preferencesProvider.notifier)
        .setScreenShareDegradation(degradation);
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

  Future<void> _copyPath(String path) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ref
        .read(noticeCenterProvider.notifier)
        .show(l10n.commonCopied, tone: NoticeTone.info);
  }

  Future<void> _openOrCopyDirectory(String path) async {
    final launcher = ref.read(directoryLauncherProvider);
    final opened = await launcher(path);
    if (!opened && mounted) {
      await _copyPath(path);
    }
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
    final update = ref.watch(updateProvider);
    final latestVersion = update.available ? update.latestVersion : null;
    final audioSelection = ref.watch(audioSelectionProvider);
    final storePath = ref.watch(storePathProvider);
    final logPath = ref.watch(logPathProvider);
    final compact = context.isCompact;

    final pttHotkeyKey = preferences.pttHotkey == null
        ? null
        : LogicalKeyboardKey.findKeyByKeyId(preferences.pttHotkey!);

    final isSubPage =
        _activeCategory != null || _activeGeneralSubcategory != null;

    final String pageTitle = switch (_activeGeneralSubcategory) {
      GeneralSubcategory.voice => l10n.settingsVoice,
      GeneralSubcategory.screenShare => l10n.settingsScreenShare,
      null => switch (_activeCategory) {
        SettingsCategory.appearance => l10n.settingsTheme,
        SettingsCategory.general => l10n.settingsGeneral,
        SettingsCategory.data => l10n.settingsData,
        SettingsCategory.about => l10n.settingsAbout,
        null => l10n.settingsTitle,
      },
    };

    // 一级概览卡片入口（一级不允许小标题）
    final Widget overviewContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        generateSection(
          items: [
            SettingsOptionsTile<String?>(
              icon: Icons.translate_rounded,
              title: l10n.settingsLanguage,
              options: const [null, 'zh', 'en'],
              value: preferences.locale,
              textBuilder: (locale) => _localeLabel(l10n, locale),
              onChanged: (locale) {
                if (!mounted) return;
                ref.read(preferencesProvider.notifier).setLocale(locale);
              },
            ),
            SettingsTile(
              icon: Icons.palette_outlined,
              title: l10n.settingsTheme,
              onTap: () =>
                  setState(() => _activeCategory = SettingsCategory.appearance),
            ),
            SettingsTile(
              icon: Icons.tune_rounded,
              title: l10n.settingsGeneral,
              onTap: () =>
                  setState(() => _activeCategory = SettingsCategory.general),
            ),
            SettingsTile(
              icon: Icons.folder_outlined,
              title: l10n.settingsData,
              onTap: () =>
                  setState(() => _activeCategory = SettingsCategory.data),
            ),
            SettingsTile(
              icon: Icons.info_outline_rounded,
              title: l10n.settingsAbout,
              badge: latestVersion == null
                  ? null
                  : UpdateDot(
                      semanticLabel: l10n.updateAvailableBadge(latestVersion),
                    ),
              onTap: () =>
                  setState(() => _activeCategory = SettingsCategory.about),
            ),
          ],
        ),
      ],
    );

    // 二级/三级页面（占满主区域）
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
      case SettingsCategory.general:
        if (_activeGeneralSubcategory == null) {
          subPageContent = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              generateSection(
                items: [
                  SettingsTile(
                    icon: Icons.headphones_outlined,
                    title: l10n.settingsVoice,
                    onTap: () => setState(
                      () =>
                          _activeGeneralSubcategory = GeneralSubcategory.voice,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.screen_share_outlined,
                    title: l10n.settingsScreenShare,
                    onTap: () => setState(
                      () => _activeGeneralSubcategory =
                          GeneralSubcategory.screenShare,
                    ),
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
        } else {
          switch (_activeGeneralSubcategory!) {
            case GeneralSubcategory.voice:
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
                            audioSelection.inputName ??
                            l10n.settingsDeviceDefault,
                        onTap: () => unawaited(
                          _pickAudioDevice(
                            selection: audioSelection,
                            output: false,
                          ),
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.volume_up_rounded,
                        title: l10n.settingsOutputDevice,
                        subtitle:
                            audioSelection.outputName ??
                            l10n.settingsDeviceDefault,
                        onTap: () => unawaited(
                          _pickAudioDevice(
                            selection: audioSelection,
                            output: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            case GeneralSubcategory.screenShare:
              subPageContent = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  generateSection(
                    title: l10n.settingsScreenShareCapture,
                    items: [
                      SettingsTile(
                        icon: Icons.hd_rounded,
                        title: l10n.settingsScreenShareResolution,
                        subtitle: _screenShareResolutionLabel(
                          l10n,
                          preferences.screenShareResolution,
                        ),
                        onTap: () => unawaited(
                          _pickScreenShareResolution(
                            preferences.screenShareResolution,
                          ),
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.speed_rounded,
                        title: l10n.settingsScreenShareFrameRate,
                        subtitle: _screenShareFrameRateLabel(
                          l10n,
                          preferences.screenShareFrameRate,
                        ),
                        onTap: () => unawaited(
                          _pickScreenShareFrameRate(
                            preferences.screenShareFrameRate,
                          ),
                        ),
                      ),
                    ],
                  ),
                  generateSection(
                    title: l10n.settingsScreenShareEncoding,
                    items: [
                      SettingsTile(
                        icon: Icons.memory_rounded,
                        title: l10n.settingsScreenShareCodec,
                        subtitle: _screenShareCodecLabel(
                          l10n,
                          preferences.screenShareCodec,
                        ),
                        onTap: () => unawaited(
                          _pickScreenShareCodec(preferences.screenShareCodec),
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.network_check_rounded,
                        title: l10n.settingsScreenShareDegradation,
                        subtitle: _screenShareDegradationLabel(
                          l10n,
                          preferences.screenShareDegradation,
                        ),
                        onTap: () => unawaited(
                          _pickScreenShareDegradation(
                            preferences.screenShareDegradation,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
          }
        }
      case SettingsCategory.data:
        final dataDirPath = p.dirname(storePath);
        subPageContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            generateSection(
              items: [
                SettingsTile(
                  icon: Icons.folder_rounded,
                  title: l10n.settingsDataPath,
                  onTap: () => unawaited(_copyPath(dataDirPath)),
                  trailing: IconButton(
                    onPressed: () =>
                        unawaited(_openOrCopyDirectory(dataDirPath)),
                    icon: Icon(
                      Icons.folder_open_rounded,
                      size: IconSizes.medium,
                      semanticLabel: l10n.commonOpenDirectory,
                    ),
                  ),
                ),
                SettingsTile(
                  icon: Icons.article_rounded,
                  title: l10n.settingsLogPath,
                  onTap: () => unawaited(_copyPath(logPath)),
                  trailing: IconButton(
                    onPressed: () => unawaited(_openOrCopyDirectory(logPath)),
                    icon: Icon(
                      Icons.folder_open_rounded,
                      size: IconSizes.medium,
                      semanticLabel: l10n.commonOpenDirectory,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case SettingsCategory.about:
        subPageContent = const AboutCard();
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
        child: Focus(
          autofocus: true,
          child: PopScope(
            canPop:
                _activeCategory == null && _activeGeneralSubcategory == null,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_activeGeneralSubcategory != null) {
                setState(() => _activeGeneralSubcategory = null);
              } else if (_activeCategory != null) {
                setState(() => _activeCategory = null);
              }
            },
            child: Scaffold(
              backgroundColor: context.pageColor,
              body: SafeArea(
                top: compact,
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

String _screenShareResolutionLabel(
  AppLocalizations l10n,
  ScreenShareResolutionPreset preset,
) => switch (preset) {
  ScreenShareResolutionPreset.p720 => l10n.settingsScreenShareResolution720p,
  ScreenShareResolutionPreset.p1080 => l10n.settingsScreenShareResolution1080p,
};

String _screenShareFrameRateLabel(
  AppLocalizations l10n,
  ScreenShareFrameRatePreset preset,
) => switch (preset) {
  ScreenShareFrameRatePreset.fps30 => l10n.settingsScreenShareFrameRate30,
  ScreenShareFrameRatePreset.fps60 => l10n.settingsScreenShareFrameRate60,
};

String _screenShareCodecLabel(
  AppLocalizations l10n,
  ScreenShareCodecPreference codec,
) => switch (codec) {
  ScreenShareCodecPreference.vp8 => l10n.settingsScreenShareCodecVp8,
  ScreenShareCodecPreference.h264 => l10n.settingsScreenShareCodecH264,
};

String _screenShareDegradationLabel(
  AppLocalizations l10n,
  ScreenShareDegradationPreference degradation,
) => switch (degradation) {
  ScreenShareDegradationPreference.maintainResolution =>
    l10n.settingsScreenShareDegradationResolution,
  ScreenShareDegradationPreference.maintainFramerate =>
    l10n.settingsScreenShareDegradationFramerate,
};
