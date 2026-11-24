import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pttHotkeyRecordingProvider = NotifierProvider<PttHotkeyRecording, bool>(
  PttHotkeyRecording.new,
);

class PttHotkeyRecording extends Notifier<bool> {
  @override
  bool build() => false;

  void setRecording(bool recording) {
    if (ref.mounted) state = recording;
  }
}

/// 原生全局热键注册结果原因。
enum GlobalHotkeyReason {
  registered,
  unsupportedPlatform,
  unsupportedKey,
  conflict,
  permissionDenied,
  failed,
}

/// `flspeak/global_hotkey` 注册调用的结构化结果。
@immutable
class GlobalHotkeyResult {
  const GlobalHotkeyResult({required this.ok, required this.reason, this.code});

  factory GlobalHotkeyResult.fromChannel(Object? raw) {
    if (raw is bool) {
      return GlobalHotkeyResult(
        ok: raw,
        reason: raw ? GlobalHotkeyReason.registered : GlobalHotkeyReason.failed,
      );
    }
    if (raw is Map) {
      final rawOk = raw['ok'];
      final rawReason = raw['reason'];
      final rawCode = raw['code'];
      if (rawOk is bool) {
        final reason = _parseReason(rawReason, ok: rawOk);
        final code = rawCode is int ? rawCode : null;
        return GlobalHotkeyResult(ok: rawOk, reason: reason, code: code);
      }
    }
    return const GlobalHotkeyResult(
      ok: false,
      reason: GlobalHotkeyReason.failed,
    );
  }

  final bool ok;
  final GlobalHotkeyReason reason;
  final int? code;

  bool get shouldRetry => switch (reason) {
    GlobalHotkeyReason.conflict ||
    GlobalHotkeyReason.permissionDenied ||
    GlobalHotkeyReason.failed => true,
    GlobalHotkeyReason.registered ||
    GlobalHotkeyReason.unsupportedPlatform ||
    GlobalHotkeyReason.unsupportedKey => false,
  };

  static GlobalHotkeyReason _parseReason(Object? raw, {required bool ok}) {
    if (raw is String) {
      for (final value in GlobalHotkeyReason.values) {
        if (value.name == raw) return value;
      }
    }
    return ok ? GlobalHotkeyReason.registered : GlobalHotkeyReason.failed;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlobalHotkeyResult &&
          other.ok == ok &&
          other.reason == reason &&
          other.code == code;

  @override
  int get hashCode => Object.hash(ok, reason, code);

  @override
  String toString() =>
      'GlobalHotkeyResult(ok: $ok, reason: ${reason.name}, code: $code)';
}

/// Dart 侧全局按住说话监听状态。
enum PttHotkeyState {
  inactive,
  registered,
  unsupportedPlatform,
  unsupportedKey,
  conflict,
  permissionDenied,
  failed,
}

/// 全局按住说话热键的当前绑定与错误上下文。
@immutable
class PttHotkeyStatus {
  const PttHotkeyStatus({
    required this.state,
    this.keyId,
    this.nativeCode,
    this.errorCode,
  });

  const PttHotkeyStatus.inactive({this.keyId})
    : state = PttHotkeyState.inactive,
      nativeCode = null,
      errorCode = null;

  factory PttHotkeyStatus.fromResult(
    GlobalHotkeyResult result, {
    int? keyId,
    int? nativeCode,
  }) => PttHotkeyStatus(
    state: switch (result.reason) {
      GlobalHotkeyReason.registered => PttHotkeyState.registered,
      GlobalHotkeyReason.unsupportedPlatform =>
        PttHotkeyState.unsupportedPlatform,
      GlobalHotkeyReason.unsupportedKey => PttHotkeyState.unsupportedKey,
      GlobalHotkeyReason.conflict => PttHotkeyState.conflict,
      GlobalHotkeyReason.permissionDenied => PttHotkeyState.permissionDenied,
      GlobalHotkeyReason.failed => PttHotkeyState.failed,
    },
    keyId: keyId,
    nativeCode: nativeCode,
    errorCode: result.code,
  );

  final PttHotkeyState state;
  final int? keyId;
  final int? nativeCode;
  final int? errorCode;

  bool get isRegistered => state == PttHotkeyState.registered;

  bool get shouldRetry => switch (state) {
    PttHotkeyState.conflict ||
    PttHotkeyState.permissionDenied ||
    PttHotkeyState.failed => true,
    PttHotkeyState.inactive ||
    PttHotkeyState.registered ||
    PttHotkeyState.unsupportedPlatform ||
    PttHotkeyState.unsupportedKey => false,
  };

  /// 前台恢复或打开设置页时的无弹窗自动重试判定：
  /// Linux 下的 `permissionDenied` 会弹出 Portal 确认框，因此仅允许用户手动触发。
  bool shouldAutoRetry(TargetPlatform platform) => switch (state) {
    PttHotkeyState.conflict || PttHotkeyState.failed => true,
    PttHotkeyState.permissionDenied => platform != TargetPlatform.linux,
    PttHotkeyState.inactive ||
    PttHotkeyState.registered ||
    PttHotkeyState.unsupportedPlatform ||
    PttHotkeyState.unsupportedKey => false,
  };

  bool get isInAppOnly => switch (state) {
    PttHotkeyState.unsupportedPlatform ||
    PttHotkeyState.unsupportedKey ||
    PttHotkeyState.conflict ||
    PttHotkeyState.failed => true,
    PttHotkeyState.inactive ||
    PttHotkeyState.registered ||
    PttHotkeyState.permissionDenied => false,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PttHotkeyStatus &&
          other.state == state &&
          other.keyId == keyId &&
          other.nativeCode == nativeCode &&
          other.errorCode == errorCode;

  @override
  int get hashCode => Object.hash(state, keyId, nativeCode, errorCode);

  @override
  String toString() =>
      'PttHotkeyStatus(state: ${state.name}, keyId: $keyId, '
      'nativeCode: $nativeCode, errorCode: $errorCode)';
}

final pttHotkeyStatusProvider =
    NotifierProvider<PttHotkeyStatusController, PttHotkeyStatus>(
      PttHotkeyStatusController.new,
    );

class PttHotkeyStatusController extends Notifier<PttHotkeyStatus> {
  void Function({bool manual})? _onRetryRequested;

  @override
  PttHotkeyStatus build() {
    ref.onDispose(() => _onRetryRequested = null);
    return const PttHotkeyStatus.inactive();
  }

  void setStatus(PttHotkeyStatus next) {
    if (ref.mounted && state != next) {
      state = next;
    }
  }

  void attachRetryHandler(void Function({bool manual}) handler) {
    _onRetryRequested = handler;
  }

  void detachRetryHandler(void Function({bool manual}) handler) {
    if (identical(_onRetryRequested, handler)) {
      _onRetryRequested = null;
    }
  }

  void requestRetry({bool manual = false}) {
    _onRetryRequested?.call(manual: manual);
  }
}

/// `flspeak/global_hotkey` 通道的 Dart 侧封装。
///
/// 原生实现只存在于桌面 runner（macOS Listen-Only `CGEventTap`、Windows 低级
/// 键盘钩子、Linux X11 XInput2 / Wayland Portal）；没有实现的平台 `register` 返回
/// `unsupportedPlatform`，调用方退到应用内按键兜底。按键事件由原生推到
/// [setHandler] 注册的回调。
class GlobalHotkey {
  const GlobalHotkey();

  static const MethodChannel _channel = MethodChannel('flspeak/global_hotkey');

  /// 设置原生事件的接收端；不传参即清除。
  void setHandler({void Function()? onKeyDown, void Function()? onKeyUp}) {
    if (onKeyDown == null && onKeyUp == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onKeyDown':
          onKeyDown?.call();
        case 'onKeyUp':
          onKeyUp?.call();
      }
      return null;
    });
  }

  /// 注册全局热键。`code` 的含义由平台决定（macOS `CGKeyCode` / Windows VK /
  /// X11 键码），返回结构化注册结果。
  Future<GlobalHotkeyResult> register(int code) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('register', code);
      if (raw == null) {
        return const GlobalHotkeyResult(
          ok: false,
          reason: GlobalHotkeyReason.unsupportedPlatform,
        );
      }
      return GlobalHotkeyResult.fromChannel(raw);
    } on PlatformException {
      return const GlobalHotkeyResult(
        ok: false,
        reason: GlobalHotkeyReason.failed,
      );
    } on MissingPluginException {
      return const GlobalHotkeyResult(
        ok: false,
        reason: GlobalHotkeyReason.unsupportedPlatform,
      );
    }
  }

  /// 注销全局热键；没注册过或平台不支持时静默成功。
  Future<void> unregister() async {
    try {
      await _channel.invokeMethod<void>('unregister');
    } on PlatformException {
      // 平台不支持或未注册。
    } on MissingPluginException {
      // 同上。
    }
  }

  /// 按需向系统申请全局按键监听权限（目前仅 macOS Input Monitoring 实现）。
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 打开系统设置中对应的全局按键监听权限页（macOS 输入监控）。
  Future<bool> openPermissionSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openPermissionSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 便捷方法：按持久化的 `LogicalKeyboardKey.keyId` 注册到当前平台。
  /// `null`、不支持的平台或不支持的键都会先注销再返回对应结构化结果。
  Future<GlobalHotkeyResult> registerByKeyId(
    int? keyId, {
    String? operatingSystem,
  }) async {
    if (keyId == null) {
      await unregister();
      return const GlobalHotkeyResult(
        ok: false,
        reason: GlobalHotkeyReason.unsupportedKey,
      );
    }
    if (!isGlobalHotkeyPlatformSupported(operatingSystem)) {
      await unregister();
      return const GlobalHotkeyResult(
        ok: false,
        reason: GlobalHotkeyReason.unsupportedPlatform,
      );
    }
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    final code = key == null
        ? null
        : nativePttKeyCode(key, operatingSystem: operatingSystem);
    if (code == null) {
      await unregister();
      return const GlobalHotkeyResult(
        ok: false,
        reason: GlobalHotkeyReason.unsupportedKey,
      );
    }
    return register(code);
  }
}

/// 全局「按住说话」快捷键的跨平台键码换算。
///
/// 持久化存 Flutter `LogicalKeyboardKey.keyId`（跨平台稳定），注册到系统时按
/// 平台取原生键码：macOS 是 `CGKeyCode` 物理键码，Windows 是虚拟键码，Linux 是
/// X11 键码（evdev + 8）。裸修饰键无法跨平台统一注册全局热键（Windows 钩子及
/// 键码映射仅收录非修饰键），所以不在支持范围里。
///
/// 同一个物理键在三种键盘布局下键码未必一致（如非 ANSI 布局的标点），这里
/// 按美式布局登记；这是全局热键的常规取舍，TeamSpeak 也如此。

/// 当前平台是否具备桌面全局热键能力。
bool isGlobalHotkeyPlatformSupported([String? operatingSystem]) {
  final os = operatingSystem ?? Platform.operatingSystem;
  return os == 'macos' || os == 'windows' || os == 'linux';
}

/// 当前平台下该逻辑键的原生键码；平台不支持或键不在支持列表里返回 `null`。
int? nativePttKeyCode(LogicalKeyboardKey key, {String? operatingSystem}) {
  final codes = _codes[key.keyId];
  if (codes == null) {
    return null;
  }
  final os = operatingSystem ?? Platform.operatingSystem;
  return switch (os) {
    'macos' => codes.$1,
    'windows' => codes.$2,
    'linux' => codes.$3,
    _ => null,
  };
}

/// 该逻辑键能否在当前平台注册为全局热键。
bool isSupportedPttHotkey(LogicalKeyboardKey key, {String? operatingSystem}) =>
    nativePttKeyCode(key, operatingSystem: operatingSystem) != null;

/// 展示用键名。`keyLabel` 对个别键不够友好，这里补一层人工命名。
String pttHotkeyDisplayName(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.space => 'Space',
  LogicalKeyboardKey.capsLock => 'Caps Lock',
  _ => key.keyLabel.isEmpty ? 'Unknown' : key.keyLabel,
};

/// (macOS CGKeyCode, Windows VK, X11 keycode) 三元组；某平台没有该键时为 null。
typedef _PlatformCodes = (int?, int, int);

final Map<int, _PlatformCodes> _codes = _buildCodes();

Map<int, _PlatformCodes> _buildCodes() {
  final table = <LogicalKeyboardKey, _PlatformCodes>{
    // 字母。
    LogicalKeyboardKey.keyA: (0x00, 0x41, 38),
    LogicalKeyboardKey.keyB: (0x0B, 0x42, 56),
    LogicalKeyboardKey.keyC: (0x08, 0x43, 54),
    LogicalKeyboardKey.keyD: (0x02, 0x44, 40),
    LogicalKeyboardKey.keyE: (0x0E, 0x45, 26),
    LogicalKeyboardKey.keyF: (0x03, 0x46, 41),
    LogicalKeyboardKey.keyG: (0x05, 0x47, 42),
    LogicalKeyboardKey.keyH: (0x04, 0x48, 43),
    LogicalKeyboardKey.keyI: (0x22, 0x49, 31),
    LogicalKeyboardKey.keyJ: (0x26, 0x4A, 44),
    LogicalKeyboardKey.keyK: (0x28, 0x4B, 45),
    LogicalKeyboardKey.keyL: (0x25, 0x4C, 46),
    LogicalKeyboardKey.keyM: (0x2E, 0x4D, 58),
    LogicalKeyboardKey.keyN: (0x2D, 0x4E, 57),
    LogicalKeyboardKey.keyO: (0x1F, 0x4F, 32),
    LogicalKeyboardKey.keyP: (0x23, 0x50, 33),
    LogicalKeyboardKey.keyQ: (0x0C, 0x51, 24),
    LogicalKeyboardKey.keyR: (0x0F, 0x52, 27),
    LogicalKeyboardKey.keyS: (0x01, 0x53, 39),
    LogicalKeyboardKey.keyT: (0x11, 0x54, 28),
    LogicalKeyboardKey.keyU: (0x20, 0x55, 30),
    LogicalKeyboardKey.keyV: (0x09, 0x56, 55),
    LogicalKeyboardKey.keyW: (0x0D, 0x57, 25),
    LogicalKeyboardKey.keyX: (0x07, 0x58, 53),
    LogicalKeyboardKey.keyY: (0x10, 0x59, 29),
    LogicalKeyboardKey.keyZ: (0x06, 0x5A, 52),
    // 数字。
    LogicalKeyboardKey.digit0: (0x1D, 0x30, 19),
    LogicalKeyboardKey.digit1: (0x12, 0x31, 10),
    LogicalKeyboardKey.digit2: (0x13, 0x32, 11),
    LogicalKeyboardKey.digit3: (0x14, 0x33, 12),
    LogicalKeyboardKey.digit4: (0x15, 0x34, 13),
    LogicalKeyboardKey.digit5: (0x17, 0x35, 14),
    LogicalKeyboardKey.digit6: (0x16, 0x36, 15),
    LogicalKeyboardKey.digit7: (0x1A, 0x37, 16),
    LogicalKeyboardKey.digit8: (0x1C, 0x38, 17),
    LogicalKeyboardKey.digit9: (0x19, 0x39, 18),
    // 功能键。
    LogicalKeyboardKey.f1: (0x7A, 0x70, 67),
    LogicalKeyboardKey.f2: (0x78, 0x71, 68),
    LogicalKeyboardKey.f3: (0x63, 0x72, 69),
    LogicalKeyboardKey.f4: (0x76, 0x73, 70),
    LogicalKeyboardKey.f5: (0x60, 0x74, 71),
    LogicalKeyboardKey.f6: (0x61, 0x75, 72),
    LogicalKeyboardKey.f7: (0x62, 0x76, 73),
    LogicalKeyboardKey.f8: (0x64, 0x77, 74),
    LogicalKeyboardKey.f9: (0x65, 0x78, 75),
    LogicalKeyboardKey.f10: (0x6D, 0x79, 76),
    LogicalKeyboardKey.f11: (0x67, 0x7A, 95),
    LogicalKeyboardKey.f12: (0x6F, 0x7B, 96),
    // 导航与杂项。macOS 没有 Insert 键（旧键盘的 Help 不是同一个概念）。
    LogicalKeyboardKey.space: (0x31, 0x20, 65),
    LogicalKeyboardKey.capsLock: (0x39, 0x14, 66),
    LogicalKeyboardKey.insert: (null, 0x2D, 118),
    LogicalKeyboardKey.delete: (0x75, 0x2E, 127),
    LogicalKeyboardKey.home: (0x73, 0x24, 110),
    LogicalKeyboardKey.end: (0x77, 0x23, 115),
    LogicalKeyboardKey.pageUp: (0x74, 0x21, 112),
    LogicalKeyboardKey.pageDown: (0x79, 0x22, 117),
    // 标点（美式布局）。
    LogicalKeyboardKey.backquote: (0x32, 0xC0, 49),
    LogicalKeyboardKey.minus: (0x1B, 0xBD, 20),
    LogicalKeyboardKey.equal: (0x18, 0xBB, 21),
    LogicalKeyboardKey.bracketLeft: (0x21, 0xDB, 34),
    LogicalKeyboardKey.bracketRight: (0x1E, 0xDD, 35),
    LogicalKeyboardKey.backslash: (0x2A, 0xDC, 51),
    LogicalKeyboardKey.semicolon: (0x29, 0xBA, 47),
    LogicalKeyboardKey.quote: (0x27, 0xDE, 48),
    LogicalKeyboardKey.comma: (0x2B, 0xBC, 59),
    LogicalKeyboardKey.period: (0x2F, 0xBE, 60),
    LogicalKeyboardKey.slash: (0x2C, 0xBF, 61),
  };
  return {for (final entry in table.entries) entry.key.keyId: entry.value};
}
