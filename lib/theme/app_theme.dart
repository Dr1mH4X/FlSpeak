import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 连接与错误使用独立语义色，避免与导航的蓝紫强调色混淆。
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

  /// 卡片使用 surfaceContainerLow，与内容底板形成柔和面阶。
  Color get cardColor => scheme.surfaceContainerLow;

  /// 主内容底板。
  Color get pageColor => scheme.surface;

  /// 描边与分隔线。
  Color get hairline => scheme.outlineVariant;

  bool get isCompact => MediaQuery.sizeOf(this).width < Breakpoints.compact;
}

/// M3 圆角层级：频道行、控件、卡片与对话框。
abstract final class Radii {
  static const small = 10.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const xl = 16.0;
  static const xxl = 24.0;
  static const xxxl = 28.0;

  /// 胶囊形：频道行、标签页、头像、状态点都用它。
  static const pill = 999.0;

  /// 同心圆角减法公式（Apple Concentric Corners）：嵌套元素与外层圆弧共用
  /// 圆心时，内半径 = 外半径 − 内边距。新增嵌套圆角一律走这里，不要手写死值。
  static double inner(double outer, double inset) =>
      (outer - inset).clamp(0.0, outer);

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
  /// 手机布局上限。M3 的 compact 是 600；这里沿用设计稿的 768：600–767
  /// 之间工作区三栏会把主区域压到 400 以内，抽屉布局更稳。
  static const compact = 768.0;

  /// M3 expanded 的起点：连接页从单列变成「身份卡 + 服务器列表」两列。
  static const wide = 840.0;
}

/// 桌面三栏布局与触控尺寸。
abstract final class Sizes {
  /// 顶栏高度 `h-16`。
  static const header = 64.0;

  /// 服务器栏宽度 `w-20`。
  static const rail = 80.0;

  /// 频道栏宽度 `w-72`。也是拖动分隔条后双击恢复的默认值。
  static const channelPanel = 288.0;

  /// 频道栏可拖动的宽度范围。上限之外还要按窗口宽度再收一次，
  /// 保证主区域不小于 [mainPaneMin]。
  static const channelPanelMin = 200.0;
  static const channelPanelMax = 480.0;

  /// 主区域的最小宽度：拖频道栏时不能把聊天区挤到没法用。
  static const mainPaneMin = 320.0;

  /// 连接页内容最大宽度 `max-w-5xl`。
  static const connectContent = 1024.0;

  /// 连接页身份卡宽度。
  static const identityColumn = 264.0;

  /// 聊天内容最大宽度 `max-w-3xl`。
  static const chatContent = 768.0;

  /// 最小可点区域：48×48。M3 的 Android 触控下限；桌面沿用同一尺寸，
  /// 让同一套控件跨端保持一致的命中面积。
  static const touch = 48.0;

  /// 服务器栏磁贴 `size-12`。
  static const railTile = 48.0;
}

/// 页面级容器的描边：浅色下一根很淡的线，深色按 M3 divider 规范用
/// outlineVariant 全色——暗色下再压透明度就真的看不见了。
BorderSide hairlineSide(BuildContext context) {
  final scheme = context.scheme;
  return BorderSide(
    color: context.isDark
        ? scheme.outlineVariant
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
        0.35,
        0.45,
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
  return base
      .copyWith(
        displaySmall: base.displaySmall?.copyWith(
          fontSize: 36,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.0,
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
      )
      .apply(
        fontFamilyFallback: const [
          'PingFang SC',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
        ],
      );
}

ColorScheme _scheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: const Color(0xFF5556C9),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );

  if (dark) {
    return seeded.copyWith(
      primary: const Color(0xFFC2C1FF),
      onPrimary: const Color(0xFF29277D),
      primaryContainer: const Color(0xFF383765),
      onPrimaryContainer: const Color(0xFFE5E1FF),
      secondaryContainer: const Color(0xFF30313C),
      onSecondaryContainer: const Color(0xFFE2E1EC),
      surface: const Color(0xFF16171F),
      surfaceDim: const Color(0xFF111218),
      surfaceBright: const Color(0xFF393A45),
      surfaceContainerLowest: const Color(0xFF111218),
      surfaceContainerLow: const Color(0xFF1E1F29),
      surfaceContainer: const Color(0xFF252631),
      surfaceContainerHigh: const Color(0xFF2E2F3C),
      surfaceContainerHighest: const Color(0xFF393A49),
      onSurface: const Color(0xFFEEEFF7),
      onSurfaceVariant: const Color(0xFFB9BACB),
      outline: const Color(0xFF8D8E9F),
      outlineVariant: const Color(0xFF3B3C4B),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      inverseSurface: const Color(0xFFEEEFF7),
      onInverseSurface: const Color(0xFF30313C),
      // 面板底色已由 surfaceContainer 家族分层，M3 的 elevation tint 一律关掉。
      surfaceTint: Colors.transparent,
      shadow: Colors.black,
      scrim: Colors.black,
    );
  }

  return seeded.copyWith(
    primary: const Color(0xFF5556C9),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE4DFFF),
    onPrimaryContainer: const Color(0xFF1D1857),
    secondaryContainer: const Color(0xFFE5E5EF),
    onSecondaryContainer: const Color(0xFF252531),
    surface: const Color(0xFFF7F7FC),
    surfaceDim: const Color(0xFFDADAE5),
    surfaceBright: const Color(0xFFF7F7FC),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFF1F1F9),
    surfaceContainer: const Color(0xFFEEEEF6),
    surfaceContainerHigh: const Color(0xFFE7E7F1),
    surfaceContainerHighest: const Color(0xFFE1E1ED),
    onSurface: const Color(0xFF1C1D29),
    onSurfaceVariant: const Color(0xFF5B5C70),
    outline: const Color(0xFF77788C),
    outlineVariant: const Color(0xFFDCDCE8),
    error: const Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410002),
    inverseSurface: const Color(0xFF30313C),
    onInverseSurface: const Color(0xFFF2F1FA),
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
    scrim: Colors.black,
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
      // M3 filled field 的容器色是 surfaceContainerHighest；暗色下再往下取
      // 面阶（旧值 lowest）会在面板上沉积成一整块死黑。
      fillColor: scheme.surfaceContainer,
      hoverColor: scheme.onSurface.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: Radii.xlAll,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Radii.xlAll,
        borderSide: BorderSide(color: scheme.outlineVariant),
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
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      errorStyle: text.bodySmall?.copyWith(color: scheme.error),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, Sizes.touch)),
        // h48 + r22 接近胶囊：光学对齐要求左右内边距 ≥ 半径（22）。
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 22),
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
    // M3 primary tabs：指示器取 primary、标签取 titleSmall；选中态文字
    // onSurface、未选中 onSurfaceVariant。应用把它放在频道头里当视图切换，
    // 底部分隔线交给外层容器画，这里关掉。
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: text.titleSmall,
      unselectedLabelStyle: text.titleSmall,
      indicatorColor: scheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      overlayColor: WidgetStatePropertyAll(
        scheme.onSurface.withValues(alpha: 0.08),
      ),
    ),
    dialogTheme: DialogThemeData(
      // M3 dialog 的容器色是 surfaceContainerHigh，比旧的 Low 在暗色下多
      // 一级分离。
      backgroundColor: scheme.surfaceContainerHigh,
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
    // 面板样式归 MenuTheme；条目的 hover/按压高亮形状归 MenuButtonTheme 的
    // shape（M3 默认是直角，这里给 10 才和应用圆角一致）。
    // 面板不留内边距：条目高亮贴满面板，圆角由面板形状统一裁出来，
    // 和原生桌面菜单一致；M3 默认的 8dp 上下留白会让高亮悬在面板中间。
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        // M3 menu 的档位是 3（level 2），8 是旧 M2 值。
        elevation: const WidgetStatePropertyAll(3.0),
        shape: WidgetStatePropertyAll(Radii.xxlShape),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(Radii.smallShape),
        textStyle: WidgetStatePropertyAll(text.bodyMedium),
      ),
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
