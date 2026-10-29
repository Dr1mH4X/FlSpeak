import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
    Object? pttHotkey = _unset,
    Object? channelPanelWidth = _unset,
    VoiceMeterSource? voiceMeterSource,
    Map<String, ServerIcon>? serverIcons,
  }) => SessionPreferences(
    nickname: nickname ?? this.nickname,
    lastConnected: lastConnected ?? this.lastConnected,
    locale: identical(locale, _unset) ? this.locale : locale as String?,
    theme: theme ?? this.theme,
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
    'schema': 2,
    'nickname': nickname,
    'lastConnected': {
      for (final entry in lastConnected.entries)
        entry.key: entry.value.millisecondsSinceEpoch,
    },
    'locale': locale,
    'theme': theme.id,
    'pttHotkey': pttHotkey,
    'channelPanelWidth': channelPanelWidth,
    'voiceMeterSource': voiceMeterSource.id,
    'serverIcons': serverIcons.map((id, icon) => MapEntry(id, icon.id)),
  };

  static SessionPreferences fromJson(Map<String, Object?> json) {
    final rawLastConnected = json['lastConnected'];
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
    final rawIcons = json['serverIcons'];
    final serverIcons = <String, ServerIcon>{};
    if (rawIcons is Map) {
      for (final entry in rawIcons.entries) {
        if (entry.key is String && entry.value is String) {
          serverIcons[entry.key as String] = ServerIcon.fromId(entry.value);
        }
      }
    }
    final rawNickname = json['nickname'];
    final nickname = rawNickname is String ? rawNickname.trim() : '';
    final rawLocale = json['locale'];
    final rawPttHotkey = json['pttHotkey'];
    final rawPanelWidth = json['channelPanelWidth'];
    return SessionPreferences(
      nickname: nickname.isEmpty || nickname == _legacyFallbackNickname
          ? fallbackNickname
          : nickname,
      lastConnected: lastConnected,
      locale: rawLocale is String && rawLocale.isNotEmpty ? rawLocale : null,
      theme: AppThemePreference.fromId(json['theme']),
      pttHotkey: rawPttHotkey is int ? rawPttHotkey : null,
      // 文件可能被手改或跨版本：不是有限数就当未设置，尺寸交给渲染时的夹取。
      channelPanelWidth: rawPanelWidth is num && rawPanelWidth.isFinite
          ? rawPanelWidth.toDouble()
          : null,
      voiceMeterSource: VoiceMeterSource.fromId(json['voiceMeterSource']),
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

  /// 和 `servers.json` 放在同一目录，便于一起备份/搬迁。
  static String pathFor(String storePath) =>
      p.join(p.dirname(storePath), 'preferences.json');

  final String? path;
  SessionPreferences _preferences;
  Future<void> _writeCompleted = Future.value();

  SessionPreferences get current => _preferences;

  static Future<PreferencesStore> load(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return PreferencesStore._(
          path,
          const SessionPreferences(
            nickname: SessionPreferences.fallbackNickname,
          ),
        );
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return PreferencesStore._(
          path,
          SessionPreferences.fromJson(decoded.cast<String, Object?>()),
        );
      }
    } on Object catch (error) {
      debugPrint('读取 preferences 失败：$error');
    }
    return PreferencesStore._(
      path,
      const SessionPreferences(nickname: SessionPreferences.fallbackNickname),
    );
  }

  Future<void> save(SessionPreferences preferences) async {
    _preferences = preferences;
    final target = path;
    if (target == null) {
      return;
    }

    final previous = _writeCompleted;
    final completed = Completer<void>();
    _writeCompleted = completed.future;
    try {
      await previous;
      final file = File(target);
      await file.parent.create(recursive: true);
      final temporary = File('$target.tmp');
      await temporary.writeAsString(
        jsonEncode(preferences.toJson()),
        flush: true,
      );
      await temporary.rename(target);
    } finally {
      // 队尾只表示写入结束；失败仍返回原调用者，后续保存可以重试。
      completed.complete();
    }
  }
}
