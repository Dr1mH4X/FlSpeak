import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 语义状态色：界面里只有这两种状态允许使用饱和色。
///
/// 一个语音客户端最贵的像素是「谁在线、谁在说话」，所以调色板只把饱和槽位留给
/// 连接态与拒绝态，其余全部走中性面阶。
///
/// 两者都按正文对比度要求保持至少 4.5:1：连接态会当正文用，拒绝态只出现在
/// 提示与校验结果里。
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

extension AppSchemeOf on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// 卡片面：浅色下是纯白，深色下比页面上浮一级。
  Color get cardColor => isDark ? scheme.surfaceContainerLow : scheme.surface;

  /// 页面底板：浅色是带一点青的米白，深色接近黑。
  Color get pageColor => scheme.surface;

  /// 浅色下页面与卡片需要靠描边分开，深色下靠面阶本身就够了。
  Color get hairline => scheme.outlineVariant;

  bool get isCompact => MediaQuery.sizeOf(this).width < Breakpoints.compact;
}

/// 圆角只有这几档，和设计稿的 Tailwind 半径一一对应。
///
/// `xl` 给按钮与输入框，`xxl` 给列表与非主导航卡片，`xxxl` 给页面级卡片与对话框。
abstract final class Radii {
  static const small = 10.0;
  static const medium = 13.0;
  static const large = 16.0;
  static const xl = 22.0;
  static const xxl = 29.0;
  static const xxxl = 35.0;

  /// 胶囊形：频道行、标签页、头像、状态点都用它。
  static const pill = 999.0;

  static BorderRadius get smallAll => BorderRadius.circular(small);
  static BorderRadius get mediumAll => BorderRadius.circular(medium);
  static BorderRadius get largeAll => BorderRadius.circular(large);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get xxlAll => BorderRadius.circular(xxl);
  static BorderRadius get xxxlAll => BorderRadius.circular(xxxl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);

  static RoundedRectangleBorder get smallShape =>
      RoundedRectangleBorder(borderRadius: smallAll);
  static RoundedRectangleBorder get xlShape =>
      RoundedRectangleBorder(borderRadius: xlAll);
  static RoundedRectangleBorder get xxlShape =>
      RoundedRectangleBorder(borderRadius: xxlAll);
  static RoundedRectangleBorder get xxxlShape =>
      RoundedRectangleBorder(borderRadius: xxxlAll);
}

/// 布局断点。和设计稿的 `md` / `lg` 对齐。
abstract final class Breakpoints {
  /// `md`：以下是手机布局，抽屉取代常驻侧栏。
  static const compact = 768.0;

  /// `lg`：连接页从单列变成「身份卡 + 服务器列表」两列。
  static const wide = 1024.0;
}

/// 固定尺寸。全部取自设计稿的 Tailwind 标尺（1 单位 = 4px）。
abstract final class Sizes {
  /// 顶栏高度 `h-16`。
  static const header = 64.0;

  /// 服务器栏宽度 `w-20`。
  static const rail = 80.0;

  /// 频道栏宽度 `w-72`。
  static const channelPanel = 288.0;

  /// 连接页内容最大宽度 `max-w-5xl`。
  static const connectContent = 1024.0;

  /// 身份栏宽度 `340px`。
  static const identityColumn = 340.0;

  /// 聊天内容最大宽度 `max-w-3xl`。
  static const chatContent = 768.0;

  /// 最小可点区域：44×44。
  static const touch = 44.0;

  /// 服务器栏磁贴 `size-12`。
  static const railTile = 48.0;
}

/// 页面级容器的描边：浅色下一根很淡的线，深色下几乎不画。
BorderSide hairlineSide(BuildContext context) {
  final scheme = context.scheme;
  return BorderSide(
    color: context.isDark
        ? scheme.outlineVariant.withValues(alpha: 0.5)
        : scheme.outlineVariant.withValues(alpha: 0.7),
  );
}

/// 服务器磁贴的配色：色相由档案 id 稳定散列而来，亮度则被归一到固定区间。
///
/// 与 `refer/components/login/monogram.tsx` 共用同一组色相。HSL 的 lightness
/// 不是感知亮度——同一个 L 下黄色比蓝色亮得多，所以散列后再把相对亮度压进
/// `_minLuminance`–`_maxLuminance`：一排磁贴看起来一样重，白色单字的对比度也
/// 始终在 4.5:1 以上。
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

  /// 两种主题共用同一块颜色：磁贴是纯色块，深浅主题切换时保留识别度，
  /// 同时保证「同一台服务器在两种主题下是同一个色相」这条闸门成立。
  static Color of(String id, Brightness brightness) => _cache.putIfAbsent(
    id,
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
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
    bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.45),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
    ),
  );
}

ColorScheme _scheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: const Color(0xFF006A60),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );

  if (dark) {
    return seeded.copyWith(
      primary: const Color(0xFF6FDBD0),
      onPrimary: const Color(0xFF003733),
      primaryContainer: const Color(0xFF00504A),
      onPrimaryContainer: const Color(0xFF8DF7EB),
      secondaryContainer: const Color(0xFF2A3330),
      onSecondaryContainer: const Color(0xFFDCE5E1),
      surface: const Color(0xFF0E1513),
      surfaceContainerLowest: const Color(0xFF090F0E),
      surfaceContainerLow: const Color(0xFF151C1A),
      surfaceContainer: const Color(0xFF1A211F),
      surfaceContainerHigh: const Color(0xFF252C2A),
      surfaceContainerHighest: const Color(0xFF303836),
      onSurface: const Color(0xFFDEE4E1),
      onSurfaceVariant: const Color(0xFFB9C6C3),
      outline: const Color(0xFF84938F),
      outlineVariant: const Color(0xFF3F4947),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      inverseSurface: const Color(0xFFDEE4E1),
      onInverseSurface: const Color(0xFF2B3230),
    );
  }

  return seeded.copyWith(
    primary: const Color(0xFF006A60),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFF9EF2E4),
    onPrimaryContainer: const Color(0xFF00201C),
    secondaryContainer: const Color(0xFFDCE5E2),
    onSecondaryContainer: const Color(0xFF151D1B),
    surface: const Color(0xFFF4FBF8),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFFFFFFF),
    surfaceContainer: const Color(0xFFE9EFEC),
    surfaceContainerHigh: const Color(0xFFDDE4E1),
    surfaceContainerHighest: const Color(0xFFD2DCD9),
    onSurface: const Color(0xFF171D1B),
    onSurfaceVariant: const Color(0xFF5B6461),
    outline: const Color(0xFF6F7B78),
    outlineVariant: const Color(0xFFC9D1CE),
    error: const Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410002),
    inverseSurface: const Color(0xFF2B3230),
    onInverseSurface: const Color(0xFFEAF1EE),
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
      shape: RoundedRectangleBorder(borderRadius: Radii.xxlAll),
    ),
    listTileTheme: ListTileThemeData(
      shape: Radii.xlShape,
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
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: Radii.xlAll,
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Radii.xlAll,
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Radii.xlAll,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: Radii.xlAll,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: Radii.xlAll,
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
        minimumSize: const WidgetStatePropertyAll(Size(0, Sizes.touch)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(Radii.xl)),
          ),
        ),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        side: focusRing,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, Sizes.touch)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(Radii.xl)),
          ),
        ),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? scheme.primary
                : scheme.outlineVariant,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, Sizes.touch)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(Radii.xl)),
          ),
        ),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(CircleBorder()),
        side: focusRing,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(text.labelMedium),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        shape: WidgetStatePropertyAll(Radii.xlShape),
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
      shape: RoundedRectangleBorder(borderRadius: Radii.xxxlAll),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xxxl)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: Radii.mediumAll,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: Radii.xxlAll),
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
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: Radii.xxlAll),
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

/// 消息时间：会话内消息只显示当天的时钟，不随界面刷新而变化。
String clockTime(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';
