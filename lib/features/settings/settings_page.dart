import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart' hide IconButton, Switch, TextButton;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../widgets/prism.dart';
import '../../widgets/update_dot.dart';
import '../../widgets/window_header.dart';
import 'settings_state.dart';
import 'widgets/about_card.dart';
import 'widgets/appearance_picker.dart';
import 'widgets/image_host_dialog.dart';
import 'widgets/ptt_hotkey_recorder.dart';
import 'widgets/settings_dialogs.dart';
import 'widgets/settings_section.dart';

enum SettingsCategory { appearance, general, about }

enum GeneralSubcategory { voice, screenShare }

const _settingsTransitionDuration = Duration(milliseconds: 300);
const _coveredSlideFactor = 0.3;
const _coveredDimAlpha = 0.1;
final Curve _settingsPushCurve = SpringCurve(
  SpringDescription.withDurationAndBounce(
    duration: _settingsTransitionDuration,
  ),
  seconds: 0.3,
);

/// 设置项页面：左侧全局导航侧边栏，右侧为多级菜单设计（二级/三级占满内容区）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  SettingsCategory? _activeCategory;
  GeneralSubcategory? _activeGeneralSubcategory;
  int _navDirection = 1;

  void _enterCategory(SettingsCategory category) {
    setState(() {
      _navDirection = 1;
      _activeCategory = category;
      _activeGeneralSubcategory = null;
    });
  }

  void _enterGeneralSubcategory(GeneralSubcategory subcategory) {
    setState(() {
      _navDirection = 1;
      _activeGeneralSubcategory = subcategory;
    });
  }

  void _back() {
    if (_activeGeneralSubcategory != null) {
      setState(() {
        _navDirection = -1;
        _activeGeneralSubcategory = null;
      });
      return;
    }
    if (_activeCategory != null) {
      setState(() {
        _navDirection = -1;
        _activeCategory = null;
      });
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
              onTap: () => _enterCategory(SettingsCategory.appearance),
            ),
            SettingsTile(
              icon: Icons.tune_rounded,
              title: l10n.settingsGeneral,
              onTap: () => _enterCategory(SettingsCategory.general),
            ),
            SettingsTile(
              icon: Icons.info_outline_rounded,
              title: l10n.settingsAbout,
              badge: latestVersion == null
                  ? null
                  : UpdateDot(
                      semanticLabel: l10n.updateAvailableBadge(latestVersion),
                    ),
              onTap: () => _enterCategory(SettingsCategory.about),
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
                SettingsOptionsTile<VoiceMeterSource>(
                  icon: Icons.graphic_eq_rounded,
                  title: l10n.settingsVoiceMeter,
                  options: VoiceMeterSource.values,
                  value: preferences.voiceMeterSource,
                  textBuilder: (source) => _voiceMeterLabel(l10n, source),
                  onChanged: (source) {
                    if (!mounted) return;
                    ref
                        .read(preferencesProvider.notifier)
                        .setVoiceMeterSource(source);
                  },
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
                    onTap: () =>
                        _enterGeneralSubcategory(GeneralSubcategory.voice),
                  ),
                  SettingsTile(
                    icon: Icons.screen_share_outlined,
                    title: l10n.settingsScreenShare,
                    onTap: () => _enterGeneralSubcategory(
                      GeneralSubcategory.screenShare,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.cloud_upload_outlined,
                    title: l10n.imageHostTitle,
                    onTap: () => showImageHostSettings(context),
                  ),
                  SettingsTile(
                    icon: Icons.update_rounded,
                    title: l10n.settingsAutoCheckUpdate,
                    trailing: Switch(
                      value: preferences.autoCheckUpdate,
                      onChanged: ref
                          .read(preferencesProvider.notifier)
                          .setAutoCheckUpdate,
                    ),
                    onTap: () => ref
                        .read(preferencesProvider.notifier)
                        .setAutoCheckUpdate(!preferences.autoCheckUpdate),
                  ),
                  SettingsOptionsTile<AppLogLevel>(
                    icon: Icons.bug_report_outlined,
                    title: l10n.settingsLogLevel,
                    options: AppLogLevel.values,
                    value: preferences.logLevel,
                    textBuilder: (level) => level.id,
                    onChanged: (level) {
                      if (!mounted) return;
                      ref.read(preferencesProvider.notifier).setLogLevel(level);
                    },
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
                      SettingsOptionsTile<ScreenShareResolutionPreset>(
                        icon: Icons.hd_rounded,
                        title: l10n.settingsScreenShareResolution,
                        options: ScreenShareResolutionPreset.values,
                        value: preferences.screenShareResolution,
                        textBuilder: (preset) =>
                            _screenShareResolutionLabel(l10n, preset),
                        onChanged: (preset) {
                          if (!mounted) return;
                          ref
                              .read(preferencesProvider.notifier)
                              .setScreenShareResolution(preset);
                        },
                      ),
                      SettingsOptionsTile<ScreenShareFrameRatePreset>(
                        icon: Icons.speed_rounded,
                        title: l10n.settingsScreenShareFrameRate,
                        options: ScreenShareFrameRatePreset.values,
                        value: preferences.screenShareFrameRate,
                        textBuilder: (preset) =>
                            _screenShareFrameRateLabel(l10n, preset),
                        onChanged: (preset) {
                          if (!mounted) return;
                          ref
                              .read(preferencesProvider.notifier)
                              .setScreenShareFrameRate(preset);
                        },
                      ),
                    ],
                  ),
                  generateSection(
                    title: l10n.settingsScreenShareEncoding,
                    items: [
                      SettingsOptionsTile<ScreenShareCodecPreference>(
                        icon: Icons.memory_rounded,
                        title: l10n.settingsScreenShareCodec,
                        options: ScreenShareCodecPreference.values,
                        value: preferences.screenShareCodec,
                        textBuilder: (codec) =>
                            _screenShareCodecLabel(l10n, codec),
                        onChanged: (codec) {
                          if (!mounted) return;
                          ref
                              .read(preferencesProvider.notifier)
                              .setScreenShareCodec(codec);
                        },
                      ),
                      SettingsOptionsTile<ScreenShareDegradationPreference>(
                        icon: Icons.network_check_rounded,
                        title: l10n.settingsScreenShareDegradation,
                        options: ScreenShareDegradationPreference.values,
                        value: preferences.screenShareDegradation,
                        textBuilder: (degradation) =>
                            _screenShareDegradationLabel(l10n, degradation),
                        onChanged: (degradation) {
                          if (!mounted) return;
                          ref
                              .read(preferencesProvider.notifier)
                              .setScreenShareDegradation(degradation);
                        },
                      ),
                    ],
                  ),
                ],
              );
          }
        }
      case SettingsCategory.about:
        subPageContent = const AboutCard();
      case null:
        subPageContent = const SizedBox.shrink();
    }

    final ValueKey<String> pageKey = switch ((
      _activeCategory,
      _activeGeneralSubcategory,
    )) {
      (null, _) => const ValueKey<String>('overview'),
      (SettingsCategory.appearance, _) => const ValueKey<String>('appearance'),
      (SettingsCategory.general, null) => const ValueKey<String>('general'),
      (SettingsCategory.general, GeneralSubcategory.voice) =>
        const ValueKey<String>('general/voice'),
      (SettingsCategory.general, GeneralSubcategory.screenShare) =>
        const ValueKey<String>('general/screenShare'),
      (SettingsCategory.about, _) => const ValueKey<String>('about'),
    };
    final Color pageColor = context.pageColor;
    final double rtlSign = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;

    final Widget activePage = KeyedSubtree(
      key: pageKey,
      child: Material(
        color: pageColor,
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
    );

    final rightContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsTopBar(title: pageTitle, onBack: _back),
        Expanded(
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: _settingsTransitionDuration,
              switchInCurve: _settingsPushCurve,
              switchOutCurve: _settingsPushCurve.flipped,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: _navDirection >= 0
                    ? [...previousChildren, ?currentChild]
                    : [?currentChild, ...previousChildren],
              ),
              transitionBuilder: (child, animation) {
                final isIncoming = child.key == pageKey;
                final bool isCoverLayer =
                    (_navDirection >= 0 && !isIncoming) ||
                    (_navDirection < 0 && isIncoming);
                final Offset beginOffset = isCoverLayer
                    ? Offset(-_coveredSlideFactor * rtlSign, 0)
                    : Offset(rtlSign, 0);
                Widget animated = SlideTransition(
                  position: Tween<Offset>(
                    begin: beginOffset,
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                );
                if (isCoverLayer) {
                  animated = AnimatedBuilder(
                    animation: animation,
                    builder: (context, inner) {
                      final dim =
                          _coveredDimAlpha *
                          (1.0 - animation.value).clamp(0.0, 1.0);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          inner!,
                          if (dim > 0)
                            IgnorePointer(
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: dim),
                              ),
                            ),
                        ],
                      );
                    },
                    child: animated,
                  );
                }
                if (!isIncoming) {
                  animated = IgnorePointer(child: animated);
                }
                return animated;
              },
              child: activePage,
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
              body: SurfaceScope(
                level: SurfaceLevel.page,
                child: SafeArea(
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
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.header),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.isCompact ? 8 : 12,
                8,
                16,
                8,
              ),
              child: Row(
                children: [
                  ElasticButton(
                    child: IconButton(
                      onPressed: onBack,
                      iconSize: IconSizes.toolbar,
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        semanticLabel: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                      ),
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
                          style: AppTextStyle.pageTitle.of(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
              child: ActivityIndicator(size: 16),
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
