// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目，
// 原始许可证为 GPL-3.0，来源提交：be84736605527034689c95bf27828ff27d912c5e。
// 对应 lib/manager/theme_manager.dart 中的 _AppMediaQuery 与系统栏 AnnotatedRegion 配置。

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' hide AlertDialog;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart' show UpdateStateView;

import 'core/global_hotkey.dart';
import 'core/hotkey_codes.dart';
import 'core/logging/logger.dart';
import 'core/notices.dart';
import 'core/preferences.dart';
import 'core/providers.dart';
import 'core/update_check.dart';
import 'core/window_chrome.dart';
import 'core/window_metrics.dart';
import 'l10n/app_localizations.dart';
import 'localization.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'widgets/prism.dart';
import 'widgets/update_dialog.dart';
import 'widgets/window_header.dart';

class TsClientApp extends ConsumerStatefulWidget {
  const TsClientApp({super.key});

  @override
  ConsumerState<TsClientApp> createState() => _TsClientAppState();
}

class _TsClientAppState extends ConsumerState<TsClientApp>
    with WidgetsBindingObserver {
  static const _hotkey = GlobalHotkey();

  /// 按住水位：原生全局事件与应用内兜底会对同一次按键各报一次，靠它去重。
  bool _pttDown = false;

  /// 原生全局热键已注册。生效期间切走窗口也要继续说话，所以生命周期收尾
  /// 只在「只有应用内兜底」的模式下执行——那种模式失焦后收不到 keyup，
  /// 不收尾会一直卡在发送状态。
  bool _nativeRegistered = false;
  int _registrationRevision = 0;
  bool _startupRegistrationDone = false;
  bool _lastPttMode = false;
  bool _pendingPermissionPrompt = false;
  SessionController? _pttOwner;
  PttHotkeyStatusController? _hotkeyStatusController;
  (int, GlobalHotkeyReason)? _lastNotifiedHotkeyFailure;
  String? _notifiedUpdateVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleInAppKey);
    _hotkeyStatusController = ref.read(pttHotkeyStatusProvider.notifier);
    _hotkeyStatusController!.attachRetryHandler(_retryRegistrationIfNeeded);
    _hotkey.setHandler(
      onKeyDown: () => _setPtt(true),
      onKeyUp: () => _setPtt(false),
    );
    ref.listenManual(
      activePttHotkeyProvider,
      (previous, keyId) => unawaited(_syncRegistration(keyId)),
      fireImmediately: true,
    );
    ref.listenManual<bool>(pttHotkeyRecordingProvider, (previous, recording) {
      if (recording) {
        _setPtt(false);
      }
    });
    ref.listenManual<(bool, bool)>(
      sessionViewProvider.select((v) => (v.connected, v.pttMode)),
      (previous, next) {
        if (!next.$1 || !next.$2) {
          _setPtt(false);
        }
        if (!next.$2) {
          _lastPttMode = false;
          _pendingPermissionPrompt = false;
          _lastNotifiedHotkeyFailure = null;
        } else if (previous != null && !previous.$2) {
          _pendingPermissionPrompt = true;
        }
      },
    );
    if (ref.read(startupUpdateCheckEnabledProvider) &&
        ref.read(preferencesProvider).autoCheckUpdate) {
      unawaited(_checkUpdatesOnStartup());
    }
  }

  Future<void> _checkUpdatesOnStartup() async {
    final state = await ref.read(updateProvider.notifier).refresh();
    if (!mounted ||
        state == null ||
        !state.available ||
        !ref.read(preferencesProvider).autoCheckUpdate) {
      return;
    }
    final version = state.latestVersion;
    if (version == null || version == _notifiedUpdateVersion) {
      return;
    }
    _notifiedUpdateVersion = version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_presentStartupUpdateDialog(state));
    });
  }

  Future<void> _presentStartupUpdateDialog(UpdateStateView state) async {
    final version = state.latestVersion;
    if (version == null || !ref.read(preferencesProvider).autoCheckUpdate) {
      return;
    }
    final navContext = ref.read(rootNavigatorKeyProvider).currentContext;
    if (navContext == null || !navContext.mounted) {
      return;
    }
    final result = await showUpdateAvailableDialog(
      navContext,
      version: version,
      releaseNotes: state.releaseNotes,
      showDoNotRemind: true,
    );
    if (!mounted) return;
    if (result == true) {
      final releaseUrl = state.releaseUrl;
      if (releaseUrl != null) {
        unawaited(ref.read(externalUrlOpenerProvider)(releaseUrl));
      }
    } else if (result == false) {
      ref.read(preferencesProvider.notifier).setAutoCheckUpdate(false);
    }
  }

  @override
  void dispose() {
    _registrationRevision++;
    _hotkeyStatusController?.detachRetryHandler(_retryRegistrationIfNeeded);
    _hotkeyStatusController = null;
    _setPtt(false);
    unawaited(_hotkey.unregister());
    HardwareKeyboard.instance.removeHandler(_handleInAppKey);
    WidgetsBinding.instance.removeObserver(this);
    _hotkey.setHandler();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await shutdownLoggingPipeline();
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _setPtt(false);
      unawaited(shutdownLoggingPipeline());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _retryRegistrationIfNeeded();
      return;
    }
    if (_nativeRegistered) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _setPtt(false);
    }
  }

  /// 应用内兜底：原生全局热键不可用（Android / Wayland / 注册失败）时，
  /// 应用在前台仍能用快捷键说话。
  bool _handleInAppKey(KeyEvent event) {
    final keyId = ref.read(activePttHotkeyProvider);
    if (keyId == null || event.logicalKey.keyId != keyId) {
      return false;
    }
    switch (event) {
      case KeyDownEvent() when event is! KeyRepeatEvent:
        _setPtt(true);
      case KeyUpEvent():
        _setPtt(false);
    }
    // 不拦截：快捷键同时也该能正常输入，与 Windows 端钩子的只观察语义一致。
    return false;
  }

  void _setPtt(bool active) {
    if (!active) {
      _pttDown = false;
      final owner = _pttOwner;
      _pttOwner = null;
      if (owner != null) unawaited(owner.setPttActive(false));
      return;
    }
    if (_pttDown) {
      return;
    }
    if (ref.read(pttHotkeyRecordingProvider)) return;
    final view = ref.read(sessionViewProvider);
    // 未连接或没开按住说话时不发命令，避免弹出无关的错误提示条。
    if (!view.connected || !view.pttMode) {
      return;
    }
    _pttDown = true;
    final owner = ref.read(sessionViewProvider.notifier);
    _pttOwner = owner;
    unawaited(owner.setPttActive(true));
  }

  void _retryRegistrationIfNeeded({bool manual = false}) {
    if (!mounted) return;
    final keyId = ref.read(activePttHotkeyProvider);
    if (keyId == null) return;
    final status = ref.read(pttHotkeyStatusProvider);
    final allow = manual
        ? status.shouldRetry
        : status.shouldAutoRetry(defaultTargetPlatform);
    if (!allow) return;
    if (manual) {
      _lastNotifiedHotkeyFailure = null;
    }
    unawaited(_syncRegistration(keyId));
  }

  Future<void> _syncRegistration(int? keyId) async {
    _setPtt(false);
    _nativeRegistered = false;
    final isStartup = !_startupRegistrationDone;
    _startupRegistrationDone = true;
    final currentPttMode = ref.read(sessionViewProvider).pttMode;
    if (!isStartup && currentPttMode && !_lastPttMode) {
      _pendingPermissionPrompt = true;
    }
    _lastPttMode = currentPttMode;
    final revision = ++_registrationRevision;
    if (keyId == null) {
      await _hotkey.unregister();
      if (!mounted || revision != _registrationRevision) return;
      final configuredKeyId = ref.read(preferencesProvider).pttHotkey;
      ref
          .read(pttHotkeyStatusProvider.notifier)
          .setStatus(PttHotkeyStatus.inactive(keyId: configuredKeyId));
      return;
    }
    final shouldPromptPermission = _pendingPermissionPrompt;
    _pendingPermissionPrompt = false;
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    final nativeCode = key == null ? null : nativePttKeyCode(key);
    final result = await _hotkey.registerByKeyId(keyId);
    if (!mounted || revision != _registrationRevision) return;
    _nativeRegistered = result.ok;
    ref
        .read(pttHotkeyStatusProvider.notifier)
        .setStatus(
          PttHotkeyStatus.fromResult(
            result,
            keyId: keyId,
            nativeCode: nativeCode,
          ),
        );
    if (result.ok) {
      _lastNotifiedHotkeyFailure = null;
      return;
    }
    if (result.reason == GlobalHotkeyReason.permissionDenied &&
        shouldPromptPermission) {
      unawaited(_hotkey.requestPermission());
    }
    _logRegistrationFailure(
      keyId: keyId,
      nativeCode: nativeCode,
      result: result,
    );
    _notifyRegistrationFailure(keyId: keyId, result: result);
  }

  void _logRegistrationFailure({
    required int keyId,
    required int? nativeCode,
    required GlobalHotkeyResult result,
  }) {
    final fields = <String, dynamic>{
      'keyId': keyId,
      'nativeCode': nativeCode,
      'platform': defaultTargetPlatform.name,
      'reason': result.reason.name,
      'code': result.code,
    };
    switch (result.reason) {
      case GlobalHotkeyReason.conflict:
      case GlobalHotkeyReason.permissionDenied:
      case GlobalHotkeyReason.failed:
        logWarn(
          'global hotkey registration failed; push-to-talk falls back to the in-app key',
          target: 'hotkey',
          fields: fields,
        );
      case GlobalHotkeyReason.unsupportedPlatform:
      case GlobalHotkeyReason.unsupportedKey:
        logInfo(
          'global hotkey unsupported on current platform or key; using in-app push-to-talk',
          target: 'hotkey',
          fields: fields,
        );
      case GlobalHotkeyReason.registered:
        break;
    }
  }

  void _notifyRegistrationFailure({
    required int keyId,
    required GlobalHotkeyResult result,
  }) {
    final failure = (keyId, result.reason);
    if (_lastNotifiedHotkeyFailure == failure) {
      return;
    }
    _lastNotifiedHotkeyFailure = failure;
    final l10n = ref.read(appLocalizationsProvider);
    final message = switch (result.reason) {
      GlobalHotkeyReason.permissionDenied =>
        defaultTargetPlatform == TargetPlatform.macOS
            ? l10n.noticePttHotkeyPermissionDenied
            : l10n.noticePttHotkeyPortalPermissionDenied,
      GlobalHotkeyReason.conflict ||
      GlobalHotkeyReason.failed ||
      GlobalHotkeyReason.unsupportedPlatform ||
      GlobalHotkeyReason.unsupportedKey => l10n.noticePttHotkeyInAppOnly,
      GlobalHotkeyReason.registered => null,
    };
    if (message != null) {
      ref
          .read(noticeCenterProvider.notifier)
          .show(message, tone: NoticeTone.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final (
      :locale,
      :themeMode,
      :liquidGlass,
      :pureBlack,
      :primaryColor,
      :colorStyle,
      :fontFamily,
      :textScaleEnabled,
      :textScale,
    ) = ref.watch(
      preferencesProvider.select(
        (prefs) => (
          locale: prefs.locale,
          themeMode: prefs.theme,
          liquidGlass: prefs.liquidGlass,
          pureBlack: prefs.pureBlack,
          primaryColor: prefs.primaryColor,
          colorStyle: prefs.colorStyle,
          fontFamily: prefs.fontFamily,
          textScaleEnabled: prefs.textScaleEnabled,
          textScale: prefs.textScale,
        ),
      ),
    );
    final glassQuality = switch (liquidGlass) {
      LiquidGlassMode.none => null,
      LiquidGlassMode.standard => LiquidGlassQuality.standard,
      LiquidGlassMode.ultra => LiquidGlassQuality.ultra,
    };

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale == null ? null : Locale(locale),
      themeMode: switch (themeMode) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      },
      theme: buildAppTheme(
        Brightness.light,
        primaryColor: primaryColor,
        colorStyle: colorStyle,
        pureBlack: pureBlack,
        fontFamily: fontFamily,
      ),
      darkTheme: buildAppTheme(
        Brightness.dark,
        primaryColor: primaryColor,
        colorStyle: colorStyle,
        pureBlack: pureBlack,
        fontFamily: fontFamily,
      ),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        final theme = Theme.of(context);
        return _AppMediaQuery(
          child: PrismRootScope(
            brightness: theme.brightness,
            platform: theme.platform,
            primaryColor: primaryColor,
            colorStyle: colorStyle,
            pureBlack: pureBlack,
            fontFamily: fontFamily,
            textScale: textScaleEnabled ? textScale : null,
            liquidGlass: glassQuality,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: appSystemUiOverlayStyle(theme),
              sized: false,
              child: _WindowBackgroundSync(
                child: _StartupLoggingNotice(
                  child: _WindowFrame(child: child ?? const SizedBox.shrink()),
                ),
              ),
            ),
          ),
        );
      },
      routerConfig: router,
    );
  }
}

/// 状态栏与系统导航栏的图标亮度跟随主题。页面在底层穿过透明系统导航栏，
/// 三键导航由系统绘制半透明遮罩，手势条保持通透。
SystemUiOverlayStyle appSystemUiOverlayStyle(ThemeData theme) {
  final dark = theme.brightness == Brightness.dark;
  final iconBrightness = dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: iconBrightness,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: true,
  );
}

/// 防止部分 Android 机型或引擎启动/旋转瞬间上报异常巨大的顶部系统边距。
class _AppMediaQuery extends StatelessWidget {
  const _AppMediaQuery({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final padding = data.padding;
    return MediaQuery(
      data: data.copyWith(
        padding: padding.copyWith(
          top: padding.top > data.size.height * 0.3 ? 20.0 : padding.top,
        ),
      ),
      child: child,
    );
  }
}

/// 把当前主题的 surface 色同步给原生窗口：macOS 的标题栏与圆角边缘跟随主题切换，
/// 其余平台没有原生实现，调用被静默忽略。
class _WindowBackgroundSync extends StatefulWidget {
  const _WindowBackgroundSync({required this.child});

  final Widget child;

  @override
  State<_WindowBackgroundSync> createState() => _WindowBackgroundSyncState();
}

class _WindowBackgroundSyncState extends State<_WindowBackgroundSync> {
  static const _chrome = WindowChrome();

  Color? _reported;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final color = context.pageColor;
    if (color == _reported) {
      return;
    }
    _reported = color;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_chrome.setBackground(color.toARGB32()));
    });
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    return widget.child;
  }
}

/// 日志初始化失败只提示一次；页面与日志写入继续以无文件模式运行。
class _StartupLoggingNotice extends ConsumerStatefulWidget {
  const _StartupLoggingNotice({required this.child});

  final Widget child;

  @override
  ConsumerState<_StartupLoggingNotice> createState() =>
      _StartupLoggingNoticeState();
}

class _StartupLoggingNoticeState extends ConsumerState<_StartupLoggingNotice> {
  @override
  void initState() {
    super.initState();
    if (ref.read(loggingFailureProvider) == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(noticeCenterProvider.notifier)
          .show(AppLocalizations.of(context).loggingUnavailable);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 窗口框架：macOS 窄屏画 28px 标题条，宽屏让页面铺到窗口上沿。
/// 红绿灯的让位通过 [ViewScope] 传给侧栏与通栏页面。
class _WindowFrame extends StatelessWidget {
  const _WindowFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMacOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final size = MediaQuery.sizeOf(context);
    final isMobileView = size.width < Breakpoints.compact;
    // 标题栏只存在于 macOS 窄屏与 Windows；它随断点出现/消失时不能重建
    // BannerHost，否则桥接状态会重放 NoticeCenter 里已经过期的提示。
    final headerHeight =
        showsWindowHeader(
          isMacOS: isMacOS,
          isWindows: isWindows,
          isMobileView: isMobileView,
        )
        ? getWindowHeaderHeight(isMacOS: isMacOS)
        : 0.0;
    return ValueListenableBuilder<bool>(
      valueListenable: WindowChrome.fullScreen,
      builder: (context, fullScreen, _) => ViewScope(
        size: size,
        isMobile: isMobileView,
        windowControls: windowControlsOverPage(
          isMacOS: isMacOS,
          isMobileView: isMobileView,
          isFullScreen: fullScreen,
        ),
        child: BannerHost(
          stacked: !isMobileView,
          // BannerHost 覆盖整个窗口；topInset 同时避让窗口标题栏与页面顶栏。
          topInset: headerHeight + Sizes.header + 8,
          child: _NoticeBannerBridge(
            child: WindowHeaderContainer(
              isMacOS: isMacOS,
              isWindows: isWindows,
              isMobileView: isMobileView,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 将 [NoticeCenter] 门面收到的提示映射为 `prism_ui` [BannerLevel] 并交给 [BannerHost]。
class _NoticeBannerBridge extends ConsumerStatefulWidget {
  const _NoticeBannerBridge({required this.child});

  final Widget child;

  @override
  ConsumerState<_NoticeBannerBridge> createState() =>
      _NoticeBannerBridgeState();
}

class _NoticeBannerBridgeState extends ConsumerState<_NoticeBannerBridge> {
  var _lastForwardedId = -1;

  @override
  void initState() {
    super.initState();
    final notices = ref.read(noticeCenterProvider);
    _lastForwardedId = ref.read(noticeCenterProvider.notifier).forwardedId;
    if (notices.any((notice) => notice.id > _lastForwardedId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _forwardNew(ref.read(noticeCenterProvider));
      });
    }
  }

  void _forwardNew(List<AppNotice> notices) {
    final host = BannerHost.maybeOf(context);
    if (host == null) {
      return;
    }
    final pending =
        notices.where((notice) => notice.id > _lastForwardedId).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    for (final notice in pending) {
      _lastForwardedId = notice.id;
      host.show(
        notice.message,
        level: switch (notice.tone) {
          NoticeTone.error => BannerLevel.error,
          NoticeTone.info => BannerLevel.info,
        },
      );
    }
    ref.read(noticeCenterProvider.notifier).markForwarded(_lastForwardedId);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<AppNotice>>(noticeCenterProvider, (previous, next) {
      _forwardNew(next);
    });
    return widget.child;
  }
}
