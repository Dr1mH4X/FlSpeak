import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/global_hotkey.dart';
import 'core/preferences.dart';
import 'core/providers.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';

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
      preferencesProvider.select((preferences) => preferences.pttHotkey),
      (previous, keyId) => unawaited(_syncRegistration(keyId)),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
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
    final keyId = ref.read(preferencesProvider).pttHotkey;
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
    if (_pttDown == active) {
      return;
    }
    _pttDown = active;
    final view = ref.read(sessionViewProvider);
    // 未连接或没开按住说话时不发命令，避免弹出无关的错误提示条。
    if (!view.connected || !view.pttMode) {
      return;
    }
    unawaited(ref.read(sessionViewProvider.notifier).setPttActive(active));
  }

  Future<void> _syncRegistration(int? keyId) async {
    _nativeRegistered = await _hotkey.registerByKeyId(keyId);
    if (keyId != null && !_nativeRegistered) {
      debugPrint('全局热键注册失败，按住说话退回应用内按键');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final preferences = ref.watch(preferencesProvider);

    return MaterialApp.router(
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
      routerConfig: router,
    );
  }
}
