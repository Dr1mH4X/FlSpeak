import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart' as ffi;
import 'package:path/path.dart' as p;

import 'server_icon.dart';

/// 外观偏好的三档。存进 JSON 的是稳定字符串，改枚举名不会毁掉已有文件。
enum AppThemePreference {
  system('system'),
  light('light'),
  dark('dark');

  const AppThemePreference(this.id);

  final String id;

  static AppThemePreference fromId(Object? value) {
    for (final mode in values) {
      if (mode.id == value) {
        return mode;
      }
    }
    return AppThemePreference.dark;
  }
}

/// 动效偏好的三档。JSON 存稳定字符串。
enum AppMotionPreference {
  system('system'),
  on('on'),
  off('off');

  const AppMotionPreference(this.id);

  final String id;

  static AppMotionPreference fromId(Object? value) {
    for (final mode in values) {
      if (mode.id == value) {
        return mode;
      }
    }
    return AppMotionPreference.system;
  }
}

/// 用户卡电平条跟随的音频源。JSON 存稳定字符串，改枚举名不毁旧文件。
enum VoiceMeterSource {
  microphone('microphone'),
  received('received');

  const VoiceMeterSource(this.id);

  final String id;

  static VoiceMeterSource fromId(Object? value) {
    for (final source in values) {
      if (source.id == value) {
        return source;
      }
    }
    return VoiceMeterSource.microphone;
  }
}

/// 昵称、最近连接时间与界面偏好。
///
/// 这是界面元数据，不是身份私钥：私钥始终只由 Rust 读写。等后端把身份模型
/// 扩成多身份后，这里会一起迁到 Rust 的身份记录里。
@immutable
class SessionPreferences {
  const SessionPreferences({
    required this.nickname,
    this.lastConnected = const <String, DateTime>{},
    this.locale,
    this.theme = AppThemePreference.dark,
    this.motion = AppMotionPreference.system,
    this.pttHotkey,
    this.channelPanelWidth,
    this.voiceMeterSource = VoiceMeterSource.microphone,
    this.serverIcons = const {},
  });

  /// 没有设置过昵称时的默认值。
  static const fallbackNickname = 'FlSpeakUser';

  /// 旧版默认值；已持久化的文件里可能出现，读取时按未设置处理。
  static const _legacyFallbackNickname = 'ts-client';

  final String nickname;

  /// 服务器 id → 最近一次成功连接的时间，仅用于排序与「上次连接」。
  final Map<String, DateTime> lastConnected;

  /// `null` 表示跟随系统；否则是 `zh` / `en` 这样的语言码。
  final String? locale;

  final AppThemePreference theme;
  final AppMotionPreference motion;

  /// 按住说话快捷键：Flutter `LogicalKeyboardKey.keyId`，`null` 表示未设置。
  /// keyId 跨平台稳定，注册到系统时再按平台换算成原生键码。
  final int? pttHotkey;

  /// 频道栏宽度（逻辑像素）；`null` 表示用默认宽度。
  final double? channelPanelWidth;

  final VoiceMeterSource voiceMeterSource;
  final Map<String, ServerIcon> serverIcons;

  SessionPreferences copyWith({
    String? nickname,
    Map<String, DateTime>? lastConnected,
    Object? locale = _unset,
    AppThemePreference? theme,
    AppMotionPreference? motion,
    Object? pttHotkey = _unset,
    Object? channelPanelWidth = _unset,
    VoiceMeterSource? voiceMeterSource,
    Map<String, ServerIcon>? serverIcons,
  }) => SessionPreferences(
    nickname: nickname ?? this.nickname,
    lastConnected: lastConnected ?? this.lastConnected,
    locale: identical(locale, _unset) ? this.locale : locale as String?,
    theme: theme ?? this.theme,
    motion: motion ?? this.motion,
    pttHotkey: identical(pttHotkey, _unset)
        ? this.pttHotkey
        : pttHotkey as int?,
    channelPanelWidth: identical(channelPanelWidth, _unset)
        ? this.channelPanelWidth
        : channelPanelWidth as double?,
    voiceMeterSource: voiceMeterSource ?? this.voiceMeterSource,
    serverIcons: serverIcons ?? this.serverIcons,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': 4,
    'nickname': nickname,
    'lastConnected': {
      for (final entry in lastConnected.entries)
        entry.key: entry.value.millisecondsSinceEpoch,
    },
    'locale': locale,
    'theme': theme.id,
    'motion': motion.id,
    'pttHotkey': pttHotkey,
    'channelPanelWidth': channelPanelWidth,
    'voiceMeterSource': voiceMeterSource.id,
    'serverIcons': serverIcons.map((id, icon) => MapEntry(id, icon.id)),
  };

  static SessionPreferences fromJson(Map<String, Object?> json) {
    final ui = json['ui'] is Map
        ? (json['ui'] as Map).cast<String, Object?>()
        : json;
    final rawLastConnected = ui['lastConnected'];
    final lastConnected = <String, DateTime>{};
    if (rawLastConnected is Map) {
      for (final entry in rawLastConnected.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is int) {
          lastConnected[key] = DateTime.fromMillisecondsSinceEpoch(value);
        }
      }
    }
    final rawIcons = ui['serverIcons'];
    final serverIcons = <String, ServerIcon>{};
    if (rawIcons is Map) {
      for (final entry in rawIcons.entries) {
        if (entry.key is String && entry.value is String) {
          serverIcons[entry.key as String] = ServerIcon.fromId(entry.value);
        }
      }
    }
    final rawNickname = ui['nickname'];
    final nickname = rawNickname is String ? rawNickname.trim() : '';
    final rawLocale = ui['locale'];
    final rawPttHotkey = ui['pttHotkey'];
    final rawPanelWidth = ui['channelPanelWidth'];
    return SessionPreferences(
      nickname: nickname.isEmpty || nickname == _legacyFallbackNickname
          ? fallbackNickname
          : nickname,
      lastConnected: lastConnected,
      locale: rawLocale is String && rawLocale.isNotEmpty ? rawLocale : null,
      theme: AppThemePreference.fromId(ui['theme']),
      motion: AppMotionPreference.fromId(ui['motion']),
      pttHotkey: rawPttHotkey is int ? rawPttHotkey : null,
      // 文件可能被手改或跨版本：不是有限数就当未设置，尺寸交给渲染时的夹取。
      channelPanelWidth: rawPanelWidth is num && rawPanelWidth.isFinite
          ? rawPanelWidth.toDouble()
          : null,
      voiceMeterSource: VoiceMeterSource.fromId(ui['voiceMeterSource']),
      serverIcons: Map.unmodifiable(serverIcons),
    );
  }
}

const Object _unset = Object();

/// 读写 `<store>/preferences.json`。文件缺失或损坏时退回默认值，绝不阻塞启动。
class PreferencesStore {
  PreferencesStore._(this.path, this._preferences);

  PreferencesStore.inMemory({SessionPreferences? preferences})
    : path = null,
      _preferences =
          preferences ??
          const SessionPreferences(
            nickname: SessionPreferences.fallbackNickname,
          );

  /// 和 `identity.json` 等状态文件放在同一目录。若传入的本身就是 `preferences.json` 则直接使用。
  static String pathFor(String storePath) {
    if (p.basename(storePath) == 'preferences.json') {
      return storePath;
    }
    return p.join(p.dirname(storePath), 'preferences.json');
  }

  final String? path;
  SessionPreferences _preferences;
  Future<void> _writeCompleted = Future.value();

  SessionPreferences get current => _preferences;

  static Future<PreferencesStore> load(String path) async {
    try {
      ffi.initSettings(storePath: path);
      final jsonStr = ffi.getSettingsJson();
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        return PreferencesStore._(
          path,
          SessionPreferences.fromJson(decoded.cast<String, Object?>()),
        );
      }
    } on Object catch (error) {
      debugPrint('通过 FFI 读取设置失败，尝试回退磁盘读取：$error');
      try {
        final file = File(path);
        if (await file.exists()) {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map) {
            return PreferencesStore._(
              path,
              SessionPreferences.fromJson(decoded.cast<String, Object?>()),
            );
          }
        }
      } catch (_) {}
    }
    return PreferencesStore._(
      path,
      const SessionPreferences(nickname: SessionPreferences.fallbackNickname),
    );
  }

  Future<SessionPreferences> save(SessionPreferences preferences) async {
    _preferences = preferences;
    final target = path;
    if (target == null) {
      // 内存模式（测试）：对齐 Rust 核心行为，由抽象层统一收敛回退与 trim
      final trimmed = preferences.nickname.trim();
      final normalizedNickname = trimmed.isEmpty
          ? SessionPreferences.fallbackNickname
          : trimmed;
      _preferences = preferences.copyWith(nickname: normalizedNickname);
      return _preferences;
    }

    final previous = _writeCompleted;
    final completed = Completer<void>();
    _writeCompleted = completed.future;
    try {
      await previous;
      try {
        ffi.updateUiSettingsJson(json: jsonEncode(preferences.toJson()));
        final jsonStr = ffi.getSettingsJson();
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          _preferences = SessionPreferences.fromJson(
            decoded.cast<String, Object?>(),
          );
        }
      } on Object catch (e) {
        debugPrint('通过 FFI 保存设置失败，尝试直接落盘 fallback: $e');
        final file = File(target);
        await file.parent.create(recursive: true);

        Map<String, Object?> existing = {};
        if (await file.exists()) {
          try {
            final decoded = jsonDecode(await file.readAsString());
            if (decoded is Map) {
              existing = decoded.cast<String, Object?>();
            }
          } catch (_) {}
        }

        final trimmed = preferences.nickname.trim();
        final normalizedNickname = trimmed.isEmpty
            ? SessionPreferences.fallbackNickname
            : trimmed;
        final normalizedPreferences = preferences.copyWith(
          nickname: normalizedNickname,
        );

        final payload = Map<String, Object?>.from(existing);
        payload.addAll(normalizedPreferences.toJson());

        final temporary = File('$target.tmp');
        await temporary.writeAsString(jsonEncode(payload), flush: true);
        await temporary.rename(target);
        _preferences = normalizedPreferences;
      }
      return _preferences;
    } finally {
      completed.complete();
    }
  }
}
