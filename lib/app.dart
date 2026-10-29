import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/global_hotkey.dart';
import 'core/preferences.dart';
import 'core/providers.dart';
import 'core/window_chrome.dart';
import 'core/window_metrics.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'widgets/notice_host.dart';
import 'widgets/view_scope.dart';
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
  SessionController? _pttOwner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleInAppKey);
    _hotkey.setHandler(
      onKeyDown: () => _setPtt(true),
      onKeyUp: () => _setPtt(false),
    );
    ref.listenManual(
      activePttHotkeyProvider,
      (previous, keyId) => unawaited(_syncRegistration(keyId)),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _registrationRevision++;
    _setPtt(false);
    unawaited(_hotkey.unregister());
    HardwareKeyboard.instance.removeHandler(_handleInAppKey);
    WidgetsBinding.instance.removeObserver(this);
    _hotkey.setHandler();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    if (_pttDown == active) {
      return;
    }
    if (ref.read(pttHotkeyRecordingProvider)) return;
    _pttDown = active;
    final view = ref.read(sessionViewProvider);
    // 未连接或没开按住说话时不发命令，避免弹出无关的错误提示条。
    if (!view.connected || !view.pttMode) {
      return;
    }
    final owner = ref.read(sessionViewProvider.notifier);
    _pttOwner = owner;
    unawaited(owner.setPttActive(true));
  }

  Future<void> _syncRegistration(int? keyId) async {
    _setPtt(false);
    _nativeRegistered = false;
    final revision = ++_registrationRevision;
    final registered = await _hotkey.registerByKeyId(keyId);
    if (!mounted || revision != _registrationRevision) return;
    _nativeRegistered = registered;
    if (keyId != null && !_nativeRegistered) {
      debugPrint('全局热键注册失败，按住说话退回应用内按键');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final preferences = ref.watch(preferencesProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: preferences.locale == null ? null : Locale(preferences.locale!),
      themeMode: switch (preferences.theme) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      },
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      builder: (context, child) {
        final systemDisableAnimations = MediaQuery.disableAnimationsOf(context);
        final disableAnimations = switch (preferences.motion) {
          AppMotionPreference.system => systemDisableAnimations,
          AppMotionPreference.on => false,
          AppMotionPreference.off => true,
        };
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: appSystemUiOverlayStyle(Theme.of(context)),
            child: _WindowBackgroundSync(
              child: _WindowFrame(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
      routerConfig: router,
    );
  }
}

/// 状态栏与系统导航栏的图标亮度跟随主题。Android 没有 AppBar 时不会自动
/// 推断，深色主题需要明确要求浅色图标，浅色主题反之。
SystemUiOverlayStyle appSystemUiOverlayStyle(ThemeData theme) {
  final dark = theme.brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: theme.colorScheme.surface,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  );
}

/// 把当前主题的 surface 色报给原生窗口：macOS 的标题栏与圆角边缘底色
/// 跟随主题切换，其余平台没有原生实现，调用被静默忽略。
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
    final color = Theme.of(context).colorScheme.surface;
    if (color == _reported) {
      return;
    }
    _reported = color;
    // 平台通道不在 build 里发；首帧与主题切换各报一次就够。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_chrome.setBackground(color.toARGB32()));
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
    final size = MediaQuery.sizeOf(context);
    final isMobileView = size.width < Breakpoints.compact;
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
        child: WindowHeaderContainer(
          isMacOS: isMacOS,
          isMobileView: isMobileView,
          child: Stack(
            children: [
              child,
              const Positioned(top: 0, right: 0, child: NoticeHost()),
            ],
          ),
        ),
      ),
    );
  }
}
