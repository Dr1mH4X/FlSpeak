import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
    return AppThemePreference.system;
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
    this.theme = AppThemePreference.system,
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

  SessionPreferences copyWith({
    String? nickname,
    Map<String, DateTime>? lastConnected,
    Object? locale = _unset,
    AppThemePreference? theme,
  }) => SessionPreferences(
    nickname: nickname ?? this.nickname,
    lastConnected: lastConnected ?? this.lastConnected,
    locale: identical(locale, _unset) ? this.locale : locale as String?,
    theme: theme ?? this.theme,
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
    final rawNickname = json['nickname'];
    final nickname = rawNickname is String ? rawNickname.trim() : '';
    final rawLocale = json['locale'];
    return SessionPreferences(
      nickname: nickname.isEmpty || nickname == _legacyFallbackNickname
          ? fallbackNickname
          : nickname,
      lastConnected: lastConnected,
      locale: rawLocale is String && rawLocale.isNotEmpty ? rawLocale : null,
      theme: AppThemePreference.fromId(json['theme']),
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

    final file = File(target);
    await file.parent.create(recursive: true);
    final temporary = File('$target.tmp');
    await temporary.writeAsString(
      jsonEncode(preferences.toJson()),
      flush: true,
    );
    try {
      await temporary.rename(target);
    } on FileSystemException {
      // Windows 上 rename 不覆盖已有文件，退化为先删后改。
      if (await file.exists()) {
        await file.delete();
      }
      await temporary.rename(target);
    }
  }
}
