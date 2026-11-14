import 'dart:math' as math;
import 'dart:ui' show ClipOp, lerpDouble;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

Color dividerColorForScheme(ColorScheme scheme) =>
    scheme.onSurface.withValues(alpha: 0.14);

Color dividerColorOf(BuildContext context) =>
    dividerColorForScheme(Theme.of(context).colorScheme);

/// 深色模式下覆盖层将各级表面色整体上提一档，维持层次感。
ColorScheme elevatedColorScheme(ColorScheme scheme) {
  if (scheme.brightness != Brightness.dark) {
    return scheme;
  }
  return scheme.copyWith(
    surface: scheme.surfaceContainer,
    surfaceContainerLow: scheme.surfaceContainerHigh,
    surfaceContainer: scheme.surfaceContainerHigh,
    surfaceContainerHigh: scheme.surfaceContainerHighest,
  );
}

extension SurfaceContext on BuildContext {
  prism.SurfaceLevel get surfaceLevel => prism.SurfaceScope.of(this);
  prism.SurfaceLevel get raisedSurfaceLevel => surfaceLevel.next;
  Color get surfaceColor =>
      surfaceLevel.colorOf(_toPrismColorScheme(Theme.of(this).colorScheme));
  Color get raisedSurfaceColor => raisedSurfaceLevel.colorOf(
    _toPrismColorScheme(Theme.of(this).colorScheme),
  );
}

prism.ColorScheme _toPrismColorScheme(ColorScheme s) => prism.ColorScheme(
  brightness: s.brightness,
  primary: s.primary,
  onPrimary: s.onPrimary,
  primaryContainer: s.primaryContainer,
  onPrimaryContainer: s.onPrimaryContainer,
  primaryFixed: s.primaryFixed,
  primaryFixedDim: s.primaryFixedDim,
  onPrimaryFixed: s.onPrimaryFixed,
  onPrimaryFixedVariant: s.onPrimaryFixedVariant,
  secondary: s.secondary,
  onSecondary: s.onSecondary,
  secondaryContainer: s.secondaryContainer,
  onSecondaryContainer: s.onSecondaryContainer,
  secondaryFixed: s.secondaryFixed,
  secondaryFixedDim: s.secondaryFixedDim,
  onSecondaryFixed: s.onSecondaryFixed,
  onSecondaryFixedVariant: s.onSecondaryFixedVariant,
  tertiary: s.tertiary,
  onTertiary: s.onTertiary,
  tertiaryContainer: s.tertiaryContainer,
  onTertiaryContainer: s.onTertiaryContainer,
  tertiaryFixed: s.tertiaryFixed,
  tertiaryFixedDim: s.tertiaryFixedDim,
  onTertiaryFixed: s.onTertiaryFixed,
  onTertiaryFixedVariant: s.onTertiaryFixedVariant,
  error: s.error,
  onError: s.onError,
  errorContainer: s.errorContainer,
  onErrorContainer: s.onErrorContainer,
  surface: s.surface,
  onSurface: s.onSurface,
  surfaceDim: s.surfaceDim,
  surfaceBright: s.surfaceBright,
  surfaceContainerLowest: s.surfaceContainerLowest,
  surfaceContainerLow: s.surfaceContainerLow,
  surfaceContainer: s.surfaceContainer,
  surfaceContainerHigh: s.surfaceContainerHigh,
  surfaceContainerHighest: s.surfaceContainerHighest,
  onSurfaceVariant: s.onSurfaceVariant,
  outline: s.outline,
  outlineVariant: s.outlineVariant,
  shadow: s.shadow,
  scrim: s.scrim,
  inverseSurface: s.inverseSurface,
  onInverseSurface: s.onInverseSurface,
  inversePrimary: s.inversePrimary,
  surfaceTint: s.surfaceTint,
);

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

  /// 卡片表面按当前上下文或卡片层级取色，依靠明度台阶区分页面。
  Color get cardColor =>
      prism.SurfaceLevel.card.colorOf(_toPrismColorScheme(scheme));

  /// 主内容底板按页面表面层级取色。
  Color get pageColor =>
      prism.SurfaceLevel.page.colorOf(_toPrismColorScheme(scheme));

  /// 分隔线颜色取 `onSurface` 14% 不透明度。
  Color get hairline => dividerColorOf(this);

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

  static RoundedSuperellipseBorder get smallShape =>
      RoundedSuperellipseBorder(borderRadius: smallAll);
  static RoundedSuperellipseBorder get xlShape =>
      RoundedSuperellipseBorder(borderRadius: xlAll);
  static RoundedSuperellipseBorder get xxlShape =>
      RoundedSuperellipseBorder(borderRadius: xxlAll);
  static RoundedSuperellipseBorder get xxxlShape =>
      RoundedSuperellipseBorder(borderRadius: xxxlAll);
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
  /// 顶栏高度 `h-12`。收敛为 48 保持与红绿灯高度居中对齐及全平台紧凑统一。
  static const header = 48.0;

  /// 服务器导航栏基准紧凑宽度（对齐 FlClash 48px，macOS 红绿灯避让动态取 78px）。
  static const rail = 48.0;

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

  /// 服务器栏磁贴与导航项高度（对齐 FlClash 40px）。
  static const railTile = 40.0;
}

/// 图标语义尺寸规范（基于 Material 3 与紧凑桌面界面收敛）。
abstract final class IconSizes {
  /// 徽章与超微标记：12。例如头像选中态微型对勾。
  static const micro = 12.0;

  /// 状态角标与行内微标：14。例如频道成员静音/说话指示、错误条前缀。
  static const state = 14.0;

  /// 行内辅助图标与小操作：16。例如频道密码锁、通知横幅图标、次要刷新。
  static const small = 16.0;

  /// 树节点与导航标签：18。例如频道树音量节点、顶栏 Tab 图标、列表尾部箭头。
  static const medium = 18.0;

  /// 操作按钮与工具栏图标：20。所有 [IconButton]、输入框工具按钮、按钮内嵌图标。
  static const toolbar = 20.0;

  /// 独立导航图标与大操作：24。如主导航栏磁贴、菜单主图标。
  static const standard = 24.0;

  /// 空状态插图与大卡片图标：40。如 [EmptyState] 居中插图。
  static const display = 40.0;
}

/// 窗口结构边界线与发丝线：统一取 `onSurface` 14% 不透明度，亮暗表面维持同等对比。
BorderSide hairlineSide(BuildContext context) {
  return BorderSide(color: dividerColorOf(context));
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
  final prismSeeded = prism.seededColorScheme(
    seedColor: const Color(0xFF5556C9),
    brightness: brightness,
    style: prism.ColorStyle.soft,
  );

  if (dark) {
    return seeded.copyWith(
      primary: const Color(0xFFC2C1FF),
      onPrimary: const Color(0xFF29277D),
      primaryContainer: const Color(0xFF383765),
      onPrimaryContainer: const Color(0xFFE5E1FF),
      secondaryContainer: const Color(0xFF30313C),
      onSecondaryContainer: const Color(0xFFE2E1EC),
      surface: prismSeeded.surface,
      surfaceDim: prismSeeded.surfaceDim,
      surfaceBright: prismSeeded.surfaceBright,
      surfaceContainerLowest: prismSeeded.surfaceContainerLowest,
      surfaceContainerLow: prismSeeded.surfaceContainerLow,
      surfaceContainer: prismSeeded.surfaceContainer,
      surfaceContainerHigh: prismSeeded.surfaceContainerHigh,
      surfaceContainerHighest: prismSeeded.surfaceContainerHighest,
      onSurface: prismSeeded.onSurface,
      onSurfaceVariant: prismSeeded.onSurfaceVariant,
      outline: const Color(0xFF8D8E9F),
      outlineVariant: prismSeeded.outlineVariant,
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
    surface: prismSeeded.surface,
    surfaceDim: prismSeeded.surfaceDim,
    surfaceBright: prismSeeded.surfaceBright,
    surfaceContainerLowest: prismSeeded.surfaceContainerLowest,
    surfaceContainerLow: prismSeeded.surfaceContainerLow,
    surfaceContainer: prismSeeded.surfaceContainer,
    surfaceContainerHigh: prismSeeded.surfaceContainerHigh,
    surfaceContainerHighest: prismSeeded.surfaceContainerHighest,
    onSurface: prismSeeded.onSurface,
    onSurfaceVariant: prismSeeded.onSurfaceVariant,
    outline: const Color(0xFF77788C),
    outlineVariant: prismSeeded.outlineVariant,
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

final Map<(Brightness, TargetPlatform), ThemeData> _materialThemeCache = {};
final Map<(Brightness, TargetPlatform), prism.ThemeData> _prismThemeCache = {};

const List<String> _cjkFontFallback = [
  'PingFang SC',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
];

Color surfaceColorFor(prism.SurfaceLevel level, ColorScheme scheme) =>
    level.colorOf(_toPrismColorScheme(scheme));

prism.SurfaceLevel floatingSurfaceLevelFor(ColorScheme scheme) =>
    prism.SurfaceLevel.floatingOf(_toPrismColorScheme(scheme));

/// 按亮度与目标平台缓存 `prism_ui` 主题实例，避免非主题重建时触发 `ThemeCrossFade`。
prism.ThemeData buildPrismTheme(
  Brightness brightness, {
  TargetPlatform? platform,
}) {
  final effectivePlatform = platform ?? defaultTargetPlatform;
  return _prismThemeCache.putIfAbsent((brightness, effectivePlatform), () {
    final materialScheme = _scheme(brightness);
    final scheme = _toPrismColorScheme(materialScheme);
    final elevated = _toPrismColorScheme(elevatedColorScheme(materialScheme));
    return prism.ThemeData(
      colorScheme: scheme,
      platform: effectivePlatform,
      fontFamilyFallback: _cjkFontFallback,
      scaffoldBackgroundColor: prism.SurfaceLevel.page.colorOf(scheme),
      elevatedColorScheme: elevated,
    );
  });
}

/// 按亮度与目标平台缓存 Material 主题，保持与 `prism_ui` 一致的配色与形状规范。
ThemeData buildAppTheme(Brightness brightness, {TargetPlatform? platform}) {
  final effectivePlatform = platform ?? defaultTargetPlatform;
  return _materialThemeCache.putIfAbsent((brightness, effectivePlatform), () {
    final scheme = _scheme(brightness);
    final dark = brightness == Brightness.dark;
    final text = _textTheme(brightness);
    final floatingSurface = surfaceColorFor(
      floatingSurfaceLevelFor(scheme),
      scheme,
    );

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

    WidgetStateProperty<Color?> buttonOverlay({Color? hover}) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.transparent;
          }
          if (states.contains(WidgetState.hovered)) {
            return hover ?? scheme.onSurface.withValues(alpha: 0.04);
          }
          if (states.contains(WidgetState.focused)) {
            return scheme.onSurface.withValues(alpha: 0.08);
          }
          return null;
        });

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      platform: effectivePlatform,
      colorScheme: scheme,
      scaffoldBackgroundColor: surfaceColorFor(prism.SurfaceLevel.page, scheme),
      textTheme: text,
      extensions: [status],
      visualDensity: VisualDensity.standard,
      iconTheme: IconThemeData(
        size: IconSizes.toolbar,
        color: scheme.onSurface,
      ),
      splashFactory: NoSplash.splashFactory,
      dividerColor: dividerColorForScheme(scheme),
      dividerTheme: DividerThemeData(
        color: dividerColorForScheme(scheme),
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: surfaceColorFor(prism.SurfaceLevel.card, scheme),
        shape: prism.AppShape.md,
      ),
      listTileTheme: ListTileThemeData(
        shape: prism.AppShape.md,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        minVerticalPadding: 8,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        filled: true,
        // M3 filled field 的容器色；暗色下避免更低面阶在面板上沉积成死黑。
        fillColor: scheme.surfaceContainer,
        hoverColor: scheme.onSurface.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: AppInputBorder(
          borderRadius: prism.AppRadius.md,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: AppInputBorder(
          borderRadius: prism.AppRadius.md,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: AppInputBorder(
          borderRadius: prism.AppRadius.md,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: AppInputBorder(
          borderRadius: prism.AppRadius.md,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: AppInputBorder(
          borderRadius: prism.AppRadius.md,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          overlayColor: buttonOverlay(
            hover: scheme.onPrimary.withValues(alpha: 0.08),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, Sizes.touch)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 22),
          ),
          shape: const WidgetStatePropertyAll(prism.AppShape.full),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          side: focusRing,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          overlayColor: buttonOverlay(),
          minimumSize: const WidgetStatePropertyAll(Size(0, Sizes.touch)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16),
          ),
          shape: const WidgetStatePropertyAll(prism.AppShape.full),
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
          splashFactory: NoSplash.splashFactory,
          overlayColor: buttonOverlay(),
          minimumSize: const WidgetStatePropertyAll(Size(0, Sizes.touch)),
          shape: const WidgetStatePropertyAll(prism.AppShape.full),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          overlayColor: buttonOverlay(),
          iconSize: const WidgetStatePropertyAll(IconSizes.toolbar),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }
            return scheme.onSurfaceVariant;
          }),
          shape: const WidgetStatePropertyAll(prism.AppShape.full),
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
          scheme.onSurface.withValues(alpha: 0.04),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: floatingSurface,
        surfaceTintColor: Colors.transparent,
        shape: prism.AppShape.all(prism.AppCorner.alert),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColorFor(prism.SurfaceLevel.page, scheme),
        surfaceTintColor: Colors.transparent,
        shape: prism.AppShape.top(prism.AppCorner.xxl),
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
      // 面板样式归 MenuTheme；条目的 hover/按压高亮形状归 MenuButtonTheme。
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(floatingSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3.0),
          shape: const WidgetStatePropertyAll(prism.AppShape.md),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          overlayColor: buttonOverlay(),
          shape: WidgetStatePropertyAll(prism.AppShape.all(prism.AppCorner.md)),
          iconSize: const WidgetStatePropertyAll(IconSizes.toolbar),
          textStyle: WidgetStatePropertyAll(text.bodySmall),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Icon(Icons.check_rounded, size: IconSizes.small)
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
    ).withAppShapes;
  });
}

class AppInputBorder extends InputBorder {
  const AppInputBorder({
    super.borderSide = const BorderSide(),
    this.borderRadius = prism.AppRadius.md,
    this.gapPadding = 4.0,
  });

  final BorderRadius borderRadius;
  final double gapPadding;

  RoundedSuperellipseBorder get _shape =>
      RoundedSuperellipseBorder(borderRadius: borderRadius, side: borderSide);

  @override
  bool get isOutline => true;

  @override
  bool get preferPaintInterior => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  AppInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) {
    return AppInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
    );
  }

  @override
  AppInputBorder scale(double t) {
    return AppInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      gapPadding: gapPadding * t,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect, textDirection: textDirection);

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => _shape.paintInterior(canvas, rect, paint, textDirection: textDirection);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is AppInputBorder) {
      return AppInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: a.gapPadding,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is AppInputBorder) {
      return AppInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        gapPadding: b.gapPadding,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final outline = rect.deflate(borderSide.width / 2);
    if (gapStart == null || gapExtent <= 0.0 || gapPercentage == 0.0) {
      _shape.paint(canvas, rect, textDirection: textDirection);
      return;
    }
    final extent = lerpDouble(
      0.0,
      gapExtent + gapPadding * 2.0,
      gapPercentage,
    )!;
    final start = switch (textDirection ?? TextDirection.ltr) {
      TextDirection.rtl => gapStart + gapPadding - extent,
      TextDirection.ltr => gapStart - gapPadding,
    };
    final radii = borderRadius.resolve(textDirection);
    final left = outline.left + math.max(0.0, start);
    final depth =
        math.max(radii.topLeft.y, radii.topRight.y) + borderSide.width;
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTRB(
          left,
          outline.top - borderSide.width,
          left + extent,
          outline.top + depth,
        ),
        clipOp: ClipOp.difference,
      );
    _shape.paint(canvas, rect, textDirection: textDirection);
    canvas.restore();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppInputBorder &&
        other.borderSide == borderSide &&
        other.borderRadius == borderRadius &&
        other.gapPadding == gapPadding;
  }

  @override
  int get hashCode => Object.hash(borderSide, borderRadius, gapPadding);
}

extension AppShapeThemeExt on ThemeData {
  ThemeData get withAppShapes => copyWith(
    cardTheme: cardTheme.copyWith(shape: prism.AppShape.md),
    dialogTheme: dialogTheme.copyWith(
      shape: prism.AppShape.all(prism.AppCorner.alert),
    ),
    bottomSheetTheme: bottomSheetTheme.copyWith(
      shape: prism.AppShape.top(prism.AppCorner.xxl),
    ),
    snackBarTheme: snackBarTheme.copyWith(shape: prism.AppShape.xs),
    chipTheme: chipTheme.copyWith(shape: prism.AppShape.sm),
    popupMenuTheme: popupMenuTheme.copyWith(shape: prism.AppShape.md),
    menuTheme: MenuThemeData(
      style: (menuTheme.style ?? const MenuStyle()).copyWith(
        shape: const WidgetStatePropertyAll(prism.AppShape.md),
      ),
    ),
    inputDecorationTheme: inputDecorationTheme.copyWith(
      border: const AppInputBorder(),
    ),
    floatingActionButtonTheme: floatingActionButtonTheme.copyWith(
      shape: prism.AppShape.md,
    ),
    navigationBarTheme: navigationBarTheme.copyWith(
      indicatorShape: prism.AppShape.full,
    ),
    navigationRailTheme: navigationRailTheme.copyWith(
      indicatorShape: prism.AppShape.full,
    ),
    progressIndicatorTheme: progressIndicatorTheme.copyWith(
      borderRadius: prism.AppRadius.full,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: filledButtonTheme.style?.merge(_pillButton) ?? _pillButton,
    ),
    textButtonTheme: TextButtonThemeData(
      style: textButtonTheme.style?.merge(_pillButton) ?? _pillButton,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: outlinedButtonTheme.style?.merge(_pillButton) ?? _pillButton,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: elevatedButtonTheme.style?.merge(_pillButton) ?? _pillButton,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: iconButtonTheme.style?.merge(_pillButton) ?? _pillButton,
    ),
  );
}

const _pillButton = ButtonStyle(
  shape: WidgetStatePropertyAll(prism.AppShape.full),
);

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
