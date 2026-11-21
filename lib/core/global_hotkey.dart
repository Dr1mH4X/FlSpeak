import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hotkey_codes.dart';

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
  VoidCallback? _onRetryRequested;

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

  void attachRetryHandler(VoidCallback handler) {
    _onRetryRequested = handler;
  }

  void detachRetryHandler(VoidCallback handler) {
    if (identical(_onRetryRequested, handler)) {
      _onRetryRequested = null;
    }
  }

  void requestRetry() {
    _onRetryRequested?.call();
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
