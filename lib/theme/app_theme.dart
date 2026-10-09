import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 语义状态色：界面里只有这两种状态允许使用饱和色。
///
/// 一个语音客户端最贵的像素是「谁在线、谁在说话」，所以调色板只把饱和槽位留给
/// 连接态与拒绝态，其余全部走中性面阶。
///
/// 两者的对比度由 `test/theme_contrast_test.dart` 守住：连接态会当正文用，
/// 必须满足 4.5:1；拒绝态只出现在提示与校验结果里，同样按正文要求。
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.live, required this.deny});

  /// 已连接。
  final Color live;

  /// 合规策略拒绝。
  final Color deny;

  @override
  StatusColors copyWith({Color? live, Color? deny}) =>
      StatusColors(live: live ?? this.live, deny: deny ?? this.deny);

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) {
      return this;
    }
    return StatusColors(
      live: Color.lerp(live, other.live, t)!,
      deny: Color.lerp(deny, other.deny, t)!,
    );
  }
}

extension StatusColorsOf on BuildContext {
  StatusColors get status =>
      Theme.of(this).extension<StatusColors>() ??
      const StatusColors(live: Color(0xFF3FBF87), deny: Color(0xFFE0574F));
}

/// 圆角只有三档，层级越高的容器用越大的档。
abstract final class Radii {
  static const small = 10.0;
  static const medium = 14.0;
  static const large = 20.0;

  static BorderRadius get smallAll => BorderRadius.circular(small);
  static BorderRadius get mediumAll => BorderRadius.circular(medium);
  static BorderRadius get largeAll => BorderRadius.circular(large);

  static RoundedRectangleBorder get smallShape =>
      RoundedRectangleBorder(borderRadius: smallAll);
}

/// 布局断点。三栏工作区在 [wide] 以上展开，以下收成图标栏 + 单栏切换。
abstract final class Breakpoints {
  static const compact = 720.0;
  static const wide = 1080.0;
}

/// 服务器磁贴的配色：色相由档案 id 稳定散列而来，亮度则被归一到固定区间。
///
/// HSL 的 lightness 不是感知亮度——同一个 L 下黄色比蓝色亮得多。所以散列出颜色后
/// 再把相对亮度压进 `_minLuminance`–`_maxLuminance`：一排磁贴看起来一样重，
/// 白色标记的对比度也始终在 4.5:1 以上。
abstract final class ServerPalette {
  static const _hues = <double>[
    232,
    262,
    292,
    322,
    8,
    36,
    158,
    186,
    206,
    130,
    250,
    300,
  ];

  static const _minLuminance = 0.09;
  static const _maxLuminance = 0.17;

  static final _cache = <String, Color>{};

  static Color of(String id, Brightness brightness) => _cache.putIfAbsent(
    '${brightness.name}:$id',
    () => _clampLuminance(
      HSLColor.fromAHSL(
        1,
        _hues[_hash(id) % _hues.length],
        0.62,
        0.5,
      ).toColor(),
    ),
  );

  static int _hash(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  static Color _clampLuminance(Color color) {
    var result = color;
    for (var step = 0; step < 32; step++) {
      final luminance = result.computeLuminance();
      if (luminance > _maxLuminance) {
        result = Color.lerp(result, Colors.black, 0.06)!;
      } else if (luminance < _minLuminance) {
        result = Color.lerp(result, Colors.white, 0.05)!;
      } else {
        return result;
      }
    }
    assert(false, '磁贴亮度没有收敛到 $_minLuminance–$_maxLuminance');
    return result;
  }
}

/// 在给定底色上取可读的前景色：比较黑白两色的对比度，取更高的那个。
Color readableOn(Color background) {
  const dark = Color(0xFF14171D);
  return _contrast(Colors.white, background) >= _contrast(dark, background)
      ? Colors.white
      : dark;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 取名字的前两个字符做标记，短名字不补位。
String initialsOf(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  final runes = trimmed.runes.toList();
  final take = runes.length >= 2 ? 2 : 1;
  return String.fromCharCodes(runes.take(take)).toUpperCase();
}

/// 数字用等宽字形，列表里的计数与时间戳才不会随内容跳动。
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

TextTheme _textTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;
  return base.copyWith(
    displaySmall: base.displaySmall?.copyWith(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.1,
      fontFeatures: tabularFigures,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      height: 1.2,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 19,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 15.5,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
    bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.45),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
    ),
  );
}

ColorScheme _scheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: const Color(0xFF5B6CF0),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );

  if (dark) {
    return seeded.copyWith(
      primary: const Color(0xFF9AA4FF),
      onPrimary: const Color(0xFF10142B),
      primaryContainer: const Color(0xFF2B3470),
      onPrimaryContainer: const Color(0xFFDFE2FF),
      secondaryContainer: const Color(0xFF272E3D),
      onSecondaryContainer: const Color(0xFFDCE0EC),
      surface: const Color(0xFF12151B),
      surfaceContainerLowest: const Color(0xFF0B0D11),
      surfaceContainerLow: const Color(0xFF161A21),
      surfaceContainer: const Color(0xFF1B202A),
      surfaceContainerHigh: const Color(0xFF222834),
      surfaceContainerHighest: const Color(0xFF2A313E),
      onSurface: const Color(0xFFE8EAF0),
      onSurfaceVariant: const Color(0xFFA6AEBE),
      outline: const Color(0xFF6B7590),
      outlineVariant: const Color(0xFF333B4A),
      error: const Color(0xFFE0574F),
      onError: const Color(0xFF2A0C0A),
      errorContainer: const Color(0xFF4A1D19),
      onErrorContainer: const Color(0xFFFFDAD6),
      inverseSurface: const Color(0xFFE8EAF0),
      onInverseSurface: const Color(0xFF12151B),
    );
  }

  return seeded.copyWith(
    primary: const Color(0xFF4A5AD8),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFDFE2FF),
    onPrimaryContainer: const Color(0xFF11144A),
    secondaryContainer: const Color(0xFFE4E7F2),
    onSecondaryContainer: const Color(0xFF1B2030),
    surface: const Color(0xFFFFFFFF),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFF6F7FA),
    surfaceContainer: const Color(0xFFF0F2F7),
    surfaceContainerHigh: const Color(0xFFE8EBF2),
    surfaceContainerHighest: const Color(0xFFDFE3EC),
    onSurface: const Color(0xFF171A20),
    onSurfaceVariant: const Color(0xFF5A6273),
    outline: const Color(0xFF7B8397),
    outlineVariant: const Color(0xFFCFD4E0),
    error: const Color(0xFFC0392F),
    onError: Colors.white,
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410E0B),
    inverseSurface: const Color(0xFF2A313E),
    onInverseSurface: const Color(0xFFF0F2F7),
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = _scheme(brightness);
  final dark = brightness == Brightness.dark;
  final text = _textTheme(brightness);

  final status = dark
      ? const StatusColors(live: Color(0xFF3FBF87), deny: Color(0xFFE0574F))
      : const StatusColors(live: Color(0xFF17724B), deny: Color(0xFFC0392F));

  final focusRing = WidgetStateProperty.resolveWith<BorderSide>(
    (states) => BorderSide(
      width: 2,
      color: states.contains(WidgetState.focused)
          ? scheme.primary
          : Colors.transparent,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    extensions: [status],
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.mediumAll,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: Radii.smallShape,
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      minVerticalPadding: 8,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: Radii.smallAll,
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Radii.smallAll,
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Radii.smallAll,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: Radii.smallAll,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: Radii.smallAll,
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      hintStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
      helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      errorStyle: text.bodySmall?.copyWith(color: scheme.error),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20),
        ),
        shape: WidgetStatePropertyAll(Radii.smallShape),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        side: focusRing,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20),
        ),
        shape: WidgetStatePropertyAll(Radii.smallShape),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? scheme.primary
                : scheme.outline,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        shape: WidgetStatePropertyAll(Radii.smallShape),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(Radii.smallShape),
        side: focusRing,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(text.labelMedium),
        // 竖向内边距要让每个分段自己就有 44 高：分段是独立落点，
        // 不能靠外层容器凑高度。
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        shape: WidgetStatePropertyAll(Radii.smallShape),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: Radii.largeAll),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.large)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: Radii.smallAll,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: Radii.mediumAll),
      insetPadding: const EdgeInsets.all(16),
      elevation: 4,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(4),
      thumbColor: WidgetStatePropertyAll(
        scheme.onSurfaceVariant.withValues(alpha: 0.35),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      strokeCap: StrokeCap.round,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: Radii.mediumAll),
      textStyle: text.bodyMedium,
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Icon(Icons.check_rounded, size: 16)
            : null,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// 服务器磁贴上的单字标记：取备注名首个可显示的字符，退化到地址首字母。
String serverMonogram(String label, String host) {
  for (final rune in label.trim().runes) {
    if (rune > 0x20) {
      return String.fromCharCode(rune).toUpperCase();
    }
  }
  final fallback = host.trim();
  if (fallback.isEmpty) {
    return '?';
  }
  return String.fromCharCode(fallback.runes.first).toUpperCase();
}

/// 相对时间：列表里只写「刚刚 / 12 分钟前」，超过一天回到时钟。
String relativeTime(DateTime at, DateTime now) {
  final delta = now.difference(at);
  if (delta.inSeconds < 45) {
    return 'now';
  }
  if (delta.inMinutes < 60) {
    return '${math.max(1, delta.inMinutes)}m';
  }
  if (delta.inHours < 24) {
    return '${delta.inHours}h';
  }
  return '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
