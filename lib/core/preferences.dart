import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart' as ffi;
import 'package:path/path.dart' as p;
import 'package:talker/talker.dart' show LogLevel;

import 'logging/logger.dart';
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
    return AppThemePreference.system;
  }
}

/// 主题种子色默认值与预设色板，首项为应用品牌色。
const int defaultPrimaryColor = 0xFFC44D78;

const List<int> defaultPrimaryColors = [
  defaultPrimaryColor,
  0xFF007AFF,
  0xFFCB30E0,
  0xFFFF2D55,
  0xFFFF383C,
  0xFFFF8D28,
  0xFFFFCC00,
  0xFF34C759,
  0xFF8E8E93,
];

const double minTextScale = 0.8;
const double maxTextScale = 1.4;

/// 主题色彩生成风格。
enum AppColorStyle {
  vivid('vivid'),
  tinted('tinted'),
  soft('soft'),
  monochrome('monochrome');

  const AppColorStyle(this.id);

  final String id;

  static AppColorStyle fromId(Object? value) {
    for (final style in values) {
      if (style.id == value) {
        return style;
      }
    }
    return AppColorStyle.vivid;
  }
}

/// 液态玻璃质感档位。默认关闭以减轻低性能设备的离屏捕获与着色器负担。
enum LiquidGlassMode {
  none('none'),
  standard('standard'),
  ultra('ultra');

  const LiquidGlassMode(this.id);

  final String id;

  static LiquidGlassMode fromId(Object? value) {
    for (final mode in values) {
      if (mode.id == value) {
        return mode;
      }
    }
    return LiquidGlassMode.none;
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

/// 屏幕共享默认分辨率与码率档位。
enum ScreenShareResolutionPreset {
  p720('720p', width: 1280, height: 720, bitrateKbps: 5000),
  p1080('1080p', width: 1920, height: 1080, bitrateKbps: 8000);

  const ScreenShareResolutionPreset(
    this.id, {
    required this.width,
    required this.height,
    required this.bitrateKbps,
  });

  final String id;
  final int width;
  final int height;
  final int bitrateKbps;

  int get maxBitrateBps => bitrateKbps * 1000;

  static ScreenShareResolutionPreset fromId(Object? value) {
    for (final preset in values) {
      if (preset.id == value) {
        return preset;
      }
    }
    return ScreenShareResolutionPreset.p720;
  }
}

/// 屏幕共享默认帧率档位。
enum ScreenShareFrameRatePreset {
  fps30(30),
  fps60(60);

  const ScreenShareFrameRatePreset(this.fps);

  final int fps;

  static ScreenShareFrameRatePreset fromFps(Object? value) {
    if (value is num) {
      final intVal = value.toInt();
      for (final preset in values) {
        if (preset.fps == intVal) {
          return preset;
        }
      }
    } else if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return fromFps(parsed);
      }
    }
    return ScreenShareFrameRatePreset.fps30;
  }
}

/// 屏幕共享视频编码器与硬件加速偏好。
enum ScreenShareCodecPreference {
  /// VP8 优先（TS6 官方桌面端兼容性最佳）。
  vp8('vp8'),

  /// H.264 优先（优先调用显卡硬件编码与解码加速）。
  h264('h264');

  const ScreenShareCodecPreference(this.id);

  final String id;

  static ScreenShareCodecPreference fromId(Object? value) {
    for (final codec in values) {
      if (codec.id == value) {
        return codec;
      }
    }
    return ScreenShareCodecPreference.h264;
  }
}

/// 屏幕共享在带宽受限时的降级策略。
enum ScreenShareDegradationPreference {
  maintainResolution('maintainResolution'),
  maintainFramerate('maintainFramerate');

  const ScreenShareDegradationPreference(this.id);

  final String id;

  static ScreenShareDegradationPreference fromId(Object? value) {
    for (final pref in values) {
      if (pref.id == value) {
        return pref;
      }
    }
    return ScreenShareDegradationPreference.maintainFramerate;
  }
}

/// 应用日志等级，前后端文件日志共用同一阈值。
enum AppLogLevel {
  debug('debug'),
  info('info'),
  warning('warning'),
  error('error');

  const AppLogLevel(this.id);

  final String id;

  /// Debug 模式默认 `debug`，Release 模式默认 `info`。
  static const AppLogLevel defaultForBuild = kDebugMode
      ? AppLogLevel.debug
      : AppLogLevel.info;

  LogLevel get talkerLevel => switch (this) {
    AppLogLevel.debug => LogLevel.debug,
    AppLogLevel.info => LogLevel.info,
    AppLogLevel.warning => LogLevel.warning,
    AppLogLevel.error => LogLevel.error,
  };

  static AppLogLevel fromId(Object? value) {
    for (final level in values) {
      if (level.id == value) {
        return level;
      }
    }
    return defaultForBuild;
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
    this.pureBlack = false,
    this.primaryColor = defaultPrimaryColor,
    this.primaryColors = defaultPrimaryColors,
    this.colorStyle = AppColorStyle.vivid,
    this.floatingNavigationBar = true,
    this.liquidGlass = LiquidGlassMode.none,
    this.fontFamily,
    this.textScaleEnabled = false,
    this.textScale = 1.0,
    this.pttHotkey,
    this.channelPanelWidth,
    this.streamViewerHeight,
    this.voiceMeterSource = VoiceMeterSource.microphone,
    this.serverIcons = const {},
    this.screenShareResolution = ScreenShareResolutionPreset.p720,
    this.screenShareFrameRate = ScreenShareFrameRatePreset.fps30,
    this.screenShareCodec = ScreenShareCodecPreference.h264,
    this.screenShareDegradation =
        ScreenShareDegradationPreference.maintainFramerate,
    this.noiseSuppression = true,
    this.autoCheckUpdate = true,
    this.logLevel = AppLogLevel.defaultForBuild,
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
  final bool pureBlack;
  final int primaryColor;
  final List<int> primaryColors;
  final AppColorStyle colorStyle;
  final bool floatingNavigationBar;
  final LiquidGlassMode liquidGlass;
  final String? fontFamily;
  final bool textScaleEnabled;
  final double textScale;

  /// 按住说话快捷键：Flutter `LogicalKeyboardKey.keyId`，`null` 表示未设置。
  /// keyId 跨平台稳定，注册到系统时再按平台换算成原生键码。
  final int? pttHotkey;

  /// 频道栏宽度（逻辑像素）；`null` 表示用默认宽度。
  final double? channelPanelWidth;

  /// 屏幕共享展示区域高度（逻辑像素）；`null` 表示用默认自适应高度。
  final double? streamViewerHeight;

  final VoiceMeterSource voiceMeterSource;
  final Map<String, ServerIconChoice> serverIcons;
  final ScreenShareResolutionPreset screenShareResolution;
  final ScreenShareFrameRatePreset screenShareFrameRate;
  final ScreenShareCodecPreference screenShareCodec;
  final ScreenShareDegradationPreference screenShareDegradation;
  final bool noiseSuppression;
  final bool autoCheckUpdate;
  final AppLogLevel logLevel;

  SessionPreferences copyWith({
    String? nickname,
    Map<String, DateTime>? lastConnected,
    Object? locale = _unset,
    AppThemePreference? theme,
    bool? pureBlack,
    int? primaryColor,
    List<int>? primaryColors,
    AppColorStyle? colorStyle,
    bool? floatingNavigationBar,
    LiquidGlassMode? liquidGlass,
    Object? fontFamily = _unset,
    bool? textScaleEnabled,
    double? textScale,
    Object? pttHotkey = _unset,
    Object? channelPanelWidth = _unset,
    Object? streamViewerHeight = _unset,
    VoiceMeterSource? voiceMeterSource,
    Map<String, ServerIconChoice>? serverIcons,
    ScreenShareResolutionPreset? screenShareResolution,
    ScreenShareFrameRatePreset? screenShareFrameRate,
    ScreenShareCodecPreference? screenShareCodec,
    ScreenShareDegradationPreference? screenShareDegradation,
    bool? noiseSuppression,
    bool? autoCheckUpdate,
    AppLogLevel? logLevel,
  }) => SessionPreferences(
    nickname: nickname ?? this.nickname,
    lastConnected: lastConnected ?? this.lastConnected,
    locale: identical(locale, _unset) ? this.locale : locale as String?,
    theme: theme ?? this.theme,
    pureBlack: pureBlack ?? this.pureBlack,
    primaryColor: primaryColor ?? this.primaryColor,
    primaryColors: primaryColors ?? this.primaryColors,
    colorStyle: colorStyle ?? this.colorStyle,
    floatingNavigationBar: floatingNavigationBar ?? this.floatingNavigationBar,
    liquidGlass: liquidGlass ?? this.liquidGlass,
    fontFamily: identical(fontFamily, _unset)
        ? this.fontFamily
        : fontFamily as String?,
    textScaleEnabled: textScaleEnabled ?? this.textScaleEnabled,
    textScale: textScale ?? this.textScale,
    pttHotkey: identical(pttHotkey, _unset)
        ? this.pttHotkey
        : pttHotkey as int?,
    channelPanelWidth: identical(channelPanelWidth, _unset)
        ? this.channelPanelWidth
        : channelPanelWidth as double?,
    streamViewerHeight: identical(streamViewerHeight, _unset)
        ? this.streamViewerHeight
        : streamViewerHeight as double?,
    voiceMeterSource: voiceMeterSource ?? this.voiceMeterSource,
    serverIcons: serverIcons ?? this.serverIcons,
    screenShareResolution: screenShareResolution ?? this.screenShareResolution,
    screenShareFrameRate: screenShareFrameRate ?? this.screenShareFrameRate,
    screenShareCodec: screenShareCodec ?? this.screenShareCodec,
    screenShareDegradation:
        screenShareDegradation ?? this.screenShareDegradation,
    noiseSuppression: noiseSuppression ?? this.noiseSuppression,
    autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
    logLevel: logLevel ?? this.logLevel,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': 5,
    'nickname': nickname,
    'lastConnected': {
      for (final entry in lastConnected.entries)
        entry.key: entry.value.millisecondsSinceEpoch,
    },
    'locale': locale,
    'theme': theme.id,
    'pureBlack': pureBlack,
    'primaryColor': primaryColor,
    'primaryColors': primaryColors,
    'colorStyle': colorStyle.id,
    'floatingNavigationBar': floatingNavigationBar,
    'liquidGlass': liquidGlass.id,
    'fontFamily': fontFamily,
    'textScaleEnabled': textScaleEnabled,
    'textScale': textScale,
    'pttHotkey': pttHotkey,
    'channelPanelWidth': channelPanelWidth,
    'streamViewerHeight': streamViewerHeight,
    'voiceMeterSource': voiceMeterSource.id,
    'serverIcons': serverIcons.map((id, icon) => MapEntry(id, icon.id)),
    'screenShareResolution': screenShareResolution.id,
    'screenShareFrameRate': screenShareFrameRate.fps,
    'screenShareCodec': screenShareCodec.id,
    'screenShareDegradation': screenShareDegradation.id,
    'noiseSuppression': noiseSuppression,
    'autoCheckUpdate': autoCheckUpdate,
    'logLevel': logLevel.id,
  };

  static int? _parseOpaqueColor(Object? raw) {
    if (raw is int) {
      return 0xFF000000 | (raw & 0x00FFFFFF);
    }
    return null;
  }

  static List<int> _parsePrimaryColors(Object? raw) {
    if (raw is! List) {
      return defaultPrimaryColors;
    }
    final seen = <int>{};
    final result = <int>[];
    for (final entry in raw) {
      final parsed = _parseOpaqueColor(entry);
      if (parsed != null && seen.add(parsed)) {
        result.add(parsed);
      }
    }
    return result.isEmpty ? defaultPrimaryColors : List.unmodifiable(result);
  }

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
    final serverIcons = <String, ServerIconChoice>{};
    if (rawIcons is Map) {
      for (final entry in rawIcons.entries) {
        if (entry.key is String && entry.value is String) {
          serverIcons[entry.key as String] = ServerIconChoice.fromId(
            entry.value,
          );
        }
      }
    }
    final rawNickname = ui['nickname'];
    final nickname = rawNickname is String ? rawNickname.trim() : '';
    final rawLocale = ui['locale'];
    final rawFontFamily = ui['fontFamily'];
    final trimmedFontFamily = rawFontFamily is String
        ? rawFontFamily.trim()
        : '';
    final rawTextScale = ui['textScale'];
    final rawPttHotkey = ui['pttHotkey'];
    final rawPanelWidth = ui['channelPanelWidth'];
    final rawStreamViewerHeight = ui['streamViewerHeight'];
    final audio = json['audio'] is Map
        ? (json['audio'] as Map).cast<String, Object?>()
        : null;
    final rawNoiseSuppression =
        audio != null && audio.containsKey('noiseSuppression')
        ? audio['noiseSuppression']
        : ui.containsKey('noiseSuppression')
        ? ui['noiseSuppression']
        : json['noiseSuppression'];
    final rawAutoCheckUpdate = ui['autoCheckUpdate'];
    return SessionPreferences(
      nickname: nickname.isEmpty || nickname == _legacyFallbackNickname
          ? fallbackNickname
          : nickname,
      lastConnected: lastConnected,
      locale: rawLocale is String && rawLocale.isNotEmpty ? rawLocale : null,
      theme: AppThemePreference.fromId(ui['theme']),
      pureBlack: ui['pureBlack'] is bool ? ui['pureBlack'] as bool : false,
      primaryColor:
          _parseOpaqueColor(ui['primaryColor']) ?? defaultPrimaryColor,
      primaryColors: _parsePrimaryColors(ui['primaryColors']),
      colorStyle: AppColorStyle.fromId(ui['colorStyle']),
      floatingNavigationBar: ui['floatingNavigationBar'] is bool
          ? ui['floatingNavigationBar'] as bool
          : true,
      liquidGlass: LiquidGlassMode.fromId(ui['liquidGlass']),
      fontFamily: trimmedFontFamily.isNotEmpty ? trimmedFontFamily : null,
      textScaleEnabled: ui['textScaleEnabled'] is bool
          ? ui['textScaleEnabled'] as bool
          : false,
      textScale: rawTextScale is num && rawTextScale.isFinite
          ? rawTextScale.toDouble().clamp(minTextScale, maxTextScale).toDouble()
          : 1.0,
      pttHotkey: rawPttHotkey is int ? rawPttHotkey : null,
      // 文件可能被手改或跨版本：不是有限数就当未设置，尺寸交给渲染时的夹取。
      channelPanelWidth: rawPanelWidth is num && rawPanelWidth.isFinite
          ? rawPanelWidth.toDouble()
          : null,
      streamViewerHeight:
          rawStreamViewerHeight is num && rawStreamViewerHeight.isFinite
          ? rawStreamViewerHeight.toDouble()
          : null,
      voiceMeterSource: VoiceMeterSource.fromId(ui['voiceMeterSource']),
      serverIcons: Map.unmodifiable(serverIcons),
      screenShareResolution: ScreenShareResolutionPreset.fromId(
        ui['screenShareResolution'],
      ),
      screenShareFrameRate: ScreenShareFrameRatePreset.fromFps(
        ui['screenShareFrameRate'],
      ),
      screenShareCodec: ScreenShareCodecPreference.fromId(
        ui['screenShareCodec'],
      ),
      screenShareDegradation: ScreenShareDegradationPreference.fromId(
        ui['screenShareDegradation'],
      ),
      noiseSuppression: rawNoiseSuppression is bool
          ? rawNoiseSuppression
          : true,
      autoCheckUpdate: rawAutoCheckUpdate is bool ? rawAutoCheckUpdate : true,
      logLevel: AppLogLevel.fromId(ui['logLevel']),
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
    if (ffi.isRustLibInitialized) {
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
        logWarn('通过 FFI 读取设置失败，尝试回退磁盘读取', error: error);
      }
    }
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
      if (ffi.isRustLibInitialized) {
        try {
          ffi.updateUiSettingsJson(json: jsonEncode(preferences.toJson()));
          final currentDecoded = jsonDecode(ffi.getSettingsJson());
          final audioMap =
              currentDecoded is Map && currentDecoded['audio'] is Map
              ? Map<String, Object?>.from(
                  (currentDecoded['audio'] as Map).cast<String, Object?>(),
                )
              : <String, Object?>{};
          audioMap['noiseSuppression'] = preferences.noiseSuppression;
          ffi.updateAudioSettingsJson(json: jsonEncode(audioMap));
          final jsonStr = ffi.getSettingsJson();
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map) {
            _preferences = SessionPreferences.fromJson(
              decoded.cast<String, Object?>(),
            );
            return _preferences;
          }
        } on Object catch (e) {
          logWarn('通过 FFI 保存设置失败，尝试直接落盘 fallback', error: e);
        }
      }

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
      final audioPayload = payload['audio'] is Map
          ? Map<String, Object?>.from(
              (payload['audio'] as Map).cast<String, Object?>(),
            )
          : <String, Object?>{};
      audioPayload['noiseSuppression'] = normalizedPreferences.noiseSuppression;
      payload['audio'] = audioPayload;

      final temporary = File('$target.tmp');
      await temporary.writeAsString(jsonEncode(payload), flush: true);
      await temporary.rename(target);
      _preferences = normalizedPreferences;
      return _preferences;
    } finally {
      completed.complete();
    }
  }
}
