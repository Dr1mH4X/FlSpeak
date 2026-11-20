import 'dart:async';

import 'package:flutter/foundation.dart'
    show SynchronousFuture, defaultTargetPlatform;
import 'package:flutter/material.dart'
    hide
        AlertDialog,
        ButtonStyle,
        Card,
        Divider,
        FilledButton,
        IconButton,
        InputBorder,
        InputDecoration,
        InputDecorationTheme,
        InputDecorationThemeData,
        NavigationBar,
        NavigationDestination,
        OutlinedButton,
        Slider,
        Switch,
        TextButton,
        TextField,
        TextFormField;
import 'package:prism_ui/icons/icons.dart' show GlyphIcon, Glyphs;
import 'package:prism_ui/prism_ui.dart' as prism;

import '../core/preferences.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

export 'package:prism_ui/prism_ui.dart'
    show
        ActivityIndicator,
        AlertDialog,
        AnimatedVisibility,
        AppBarClearance,
        AppCorner,
        AppRadius,
        AppShape,
        AppTextStyle,
        BannerHost,
        BannerHostState,
        BannerLevel,
        BarItemGlyph,
        BarItemPresence,
        BuildContextExtension,
        ButtonStyle,
        Card,
        CardPageRoute,
        CardSurface,
        Checkbox,
        Chip,
        ColorExtension,
        ColorSchemeExtension,
        ColorStyle,
        ContextMenuRegion,
        DecorationListItem,
        Divider,
        ElasticButton,
        ElasticHover,
        ElasticPress,
        ElevatedSurfaceExt,
        ExtendProps,
        FilledInputTheme,
        FloatingBarScope,
        FloatingHeader,
        FloatingHeaderBody,
        FocusRing,
        FormSheetRoute,
        GooPane,
        GooSurface,
        IconButtonData,
        Illustration,
        InputBorder,
        InputDecoration,
        InputDecorationTheme,
        InputDecorationThemeData,
        ItemPosition,
        ItemPositionProvider,
        LinearProgressIndicator,
        LiquidGlass,
        LiquidGlassGlow,
        LiquidGlassGroup,
        LiquidGlassHost,
        LiquidGlassQuality,
        LiquidGlassRim,
        LiquidGlassScope,
        LiquidGlassStyle,
        ListController,
        ListFooter,
        ListHeader,
        ListRow,
        ListRowAlignment,
        ListSectionGap,
        Measure,
        MeasureScope,
        MemoBuilder,
        MetaChip,
        NavigationBar,
        NavigationDestination,
        NavigationDock,
        NavigationDockDestination,
        NoInputBorder,
        NullStatus,
        NullStatusSwitcher,
        OpenContainer,
        OpenContainerTransition,
        PopupAnchor,
        PopupMenu,
        PopupMenuItem,
        PopupMenuSection,
        PopupOpen,
        PopupPlacement,
        PopupValueText,
        PressLook,
        PressSurface,
        PrismListView,
        PrismScaffold,
        ScaffoldBar,
        ScaffoldSurface,
        SearchField,
        SegmentedControl,
        SelectionBadge,
        SelectionCheck,
        SheetDragHandle,
        SheetProps,
        SheetProvider,
        SheetType,
        Slider,
        SliderShape,
        SliverPrismList,
        SnapSheetRoute,
        SpringCurve,
        Surface,
        SurfaceLevel,
        SurfaceScope,
        Switch,
        TextField,
        TextFormField,
        TextSelectionMenu,
        ThemeCrossFade,
        TonalButton,
        TonalButtonGroup,
        TonalButtonSize,
        TonalButtonTheme,
        TonalChip,
        ViewScope,
        WidthBuilder,
        dockShadows,
        dropletSpring,
        fadeTabCurve,
        fadeTabDuration,
        focusRingSide,
        formSheetShape,
        generateGroup,
        isRouteMoving,
        kTabScrollDuration,
        listHeaderPaddingOf,
        listRowMinHeight,
        listRowVerticalPadding,
        menuShadows,
        pageToolbarHeight,
        riseAndFall,
        seededColorScheme,
        sheetAppBarHeight,
        sheetNavigatorOf,
        sheetScrollController,
        sheetToolbarHeight,
        showExtend,
        showFloatingDialog,
        showSheet,
        snapSheetDetents;

export 'package:prism_ui/hct/hct.dart' show Hct;

export 'package:prism_ui/icons/icons.dart'
    show
        AnimatedGlyph,
        Glyph,
        GlyphArc,
        GlyphBox,
        GlyphCircle,
        GlyphIcon,
        GlyphLink,
        GlyphOval,
        GlyphPath,
        GlyphPolyline,
        GlyphRole,
        GlyphShape,
        GlyphVertex,
        Glyphs;

export 'app_glyphs.dart' show AppGlyphs;

typedef PrismTheme = prism.Theme;
typedef PrismThemeData = prism.ThemeData;
typedef PrismColorScheme = prism.ColorScheme;
typedef PrismButtonTheme = prism.ButtonTheme;
typedef PrismButtonThemeData = prism.ButtonThemeData;

/// 将 `AppLocalizations` 映射到 `prism_ui` 内置组件所需的文案。
class PrismUiLocalizationsDelegate
    extends LocalizationsDelegate<prism.UiLocalizations> {
  const PrismUiLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<prism.UiLocalizations> load(Locale locale) {
    final app = lookupAppLocalizations(
      locale.languageCode == 'zh' ? const Locale('zh') : const Locale('en'),
    );
    return SynchronousFuture<_AppPrismUiLocalizations>(
      _AppPrismUiLocalizations(app: app, isZh: locale.languageCode == 'zh'),
    );
  }

  @override
  bool shouldReload(PrismUiLocalizationsDelegate old) => false;
}

class _AppPrismUiLocalizations extends prism.UiLocalizations {
  _AppPrismUiLocalizations({required this.app, required this.isZh});

  final AppLocalizations app;
  final bool isZh;

  @override
  String get back => isZh ? '返回' : 'Back';

  @override
  String get cancel => app.commonCancel;

  @override
  String get clearSearch => isZh ? '清空搜索' : 'Clear search';

  @override
  String get close => app.commonClose;

  @override
  String get copy => app.commonCopy;

  @override
  String get cut => isZh ? '剪切' : 'Cut';

  @override
  String get dialog => isZh ? '对话框' : 'Dialog';

  @override
  String get hidePassword => isZh ? '隐藏密码' : 'Hide password';

  @override
  String get more => isZh ? '更多' : 'More';

  @override
  String get noSearchResults => isZh ? '无搜索结果' : 'No search results';

  @override
  String get paste => isZh ? '粘贴' : 'Paste';

  @override
  String get reset => isZh ? '重置' : 'Reset';

  @override
  String get select => isZh ? '选择' : 'Select';

  @override
  String get search => isZh ? '搜索' : 'Search';

  @override
  String get selectAll => isZh ? '全选' : 'Select all';

  @override
  String get showLess => isZh ? '收起' : 'Show less';

  @override
  String get showMore => isZh ? '展开' : 'Show more';

  @override
  String get showPassword => isZh ? '显示密码' : 'Show password';

  @override
  String get sort => isZh ? '排序' : 'Sort';

  @override
  String get submit => app.commonDone;
}

/// 在 `MaterialApp` 子树内部挂载 `prism_ui` 所需的主题、文本度量、玻璃容器与表面上下文。
class PrismRootScope extends StatelessWidget {
  const PrismRootScope({
    super.key,
    required this.brightness,
    this.platform,
    this.primaryColor = defaultPrimaryColor,
    this.colorStyle = AppColorStyle.vivid,
    this.pureBlack = false,
    this.fontFamily,
    this.textScale,
    this.liquidGlass,
    this.crossFadeTheme = true,
    required this.child,
  });

  final Brightness brightness;
  final TargetPlatform? platform;
  final int primaryColor;
  final AppColorStyle colorStyle;
  final bool pureBlack;
  final String? fontFamily;
  final double? textScale;
  final prism.LiquidGlassQuality? liquidGlass;
  final bool crossFadeTheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final baseMediaQuery = MediaQuery.of(context);
    final customScale = textScale?.clamp(minTextScale, maxTextScale).toDouble();
    final effectiveTextScaler = customScale != null
        ? TextScaler.linear(customScale)
        : baseMediaQuery.textScaler;
    final textFactor = customScale ?? effectiveTextScaler.scale(1.0);
    final effectivePlatform = platform ?? defaultTargetPlatform;
    final prismTheme = buildPrismTheme(
      brightness,
      platform: effectivePlatform,
      primaryColor: primaryColor,
      colorStyle: colorStyle,
      pureBlack: pureBlack,
      fontFamily: fontFamily,
    );

    final size = baseMediaQuery.size;
    final prismScheme = prismTheme.colorScheme;
    final inputShape = prism.AppShape.input;
    Widget content = prism.InputDecorationTheme(
      data: prism.InputDecorationThemeData(
        filled: true,
        fillColor: prismScheme.surfaceContainer,
        hoverColor: prismScheme.onSurface.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: inputShape.copyWith(
          borderSide: BorderSide(color: prismScheme.outline),
        ),
        enabledBorder: inputShape.copyWith(
          borderSide: BorderSide(color: prismScheme.outline),
        ),
        focusedBorder: inputShape.copyWith(
          borderSide: BorderSide(color: prismScheme.primary, width: 2),
        ),
        errorBorder: inputShape.copyWith(
          borderSide: BorderSide(color: prismScheme.error),
        ),
        focusedErrorBorder: inputShape.copyWith(
          borderSide: BorderSide(color: prismScheme.error, width: 2),
        ),
      ),
      child: prism.SurfaceScope(level: prism.SurfaceLevel.page, child: child),
    );
    if (context.getInheritedWidgetOfExactType<prism.ViewScope>() == null) {
      content = prism.ViewScope(
        size: size,
        isMobile: size.width < Breakpoints.compact,
        child: content,
      );
    }

    final glassContent = prism.LiquidGlassScope(
      enabled: liquidGlass != null,
      quality: liquidGlass ?? prism.LiquidGlassQuality.standard,
      child: prism.LiquidGlassHost(
        enabled: liquidGlass != null,
        child: content,
      ),
    );

    Widget scopeTree = Builder(
      builder: (scopeContext) => prism.MeasureScope(
        measure: prism.Measure.of(scopeContext, textFactor),
        child: glassContent,
      ),
    );
    if (customScale != null) {
      scopeTree = MediaQuery(
        data: baseMediaQuery.copyWith(textScaler: effectiveTextScaler),
        child: scopeTree,
      );
    }

    if (crossFadeTheme) {
      scopeTree = prism.ThemeCrossFade(child: scopeTree);
    }

    return prism.Theme(
      data: prismTheme,
      child: IconTheme(data: prismTheme.iconTheme, child: scopeTree),
    );
  }
}

prism.LiquidGlassStyle glassPillStyleOf(BuildContext context) =>
    prism.LiquidGlassStyle.pill(prism.Theme.of(context).colorScheme);

prism.LiquidGlassStyle glassRegularStyleOf(BuildContext context) =>
    prism.LiquidGlassStyle.regular(prism.Theme.of(context).colorScheme);

prism.LiquidGlassStyle glassMenuStyleOf(BuildContext context) =>
    prism.LiquidGlassStyle.menu(prism.Theme.of(context).colorScheme);

prism.LiquidGlassRim glassMenuRimOf(BuildContext context) =>
    prism.LiquidGlassRim.menu(prism.Theme.of(context).colorScheme);

List<BoxShadow> dockShadowsOf(BuildContext context) =>
    prism.dockShadows(prism.Theme.of(context).colorScheme);

List<BoxShadow> menuShadowsOf(BuildContext context) =>
    prism.menuShadows(prism.Theme.of(context).colorScheme);

/// 无边框超椭圆表面卡片：按上下文表面层级自动步进底色并向下传递作用域。
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.shape,
    this.color,
    this.clip = false,
  });

  final Widget child;
  final OutlinedBorder? shape;
  final Color? color;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = prism.SurfaceScope.of(context).next;
    final resolvedShape = shape ?? prism.AppShape.xl;
    final fill = color ?? surfaceColorFor(level, scheme);
    final Widget body = prism.SurfaceScope(level: level, child: child);
    return DecoratedBox(
      decoration: ShapeDecoration(color: fill, shape: resolvedShape),
      child: clip
          ? ClipRSuperellipse(
              borderRadius: switch (resolvedShape) {
                RoundedSuperellipseBorder(:final borderRadius) => borderRadius,
                RoundedRectangleBorder(:final borderRadius) => borderRadius,
                _ => prism.AppRadius.xl,
              },
              child: body,
            )
          : body,
    );
  }
}

/// 在浮层（对话框、弹出菜单等）同时将 `prism_ui` 与 Material 暗色表面层级上提一档。
class ElevatedSurfaceTheme extends StatelessWidget {
  const ElevatedSurfaceTheme({super.key, required this.child});

  final Widget child;

  static bool isIn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ElevatedMaterialScope>() != null;

  @override
  Widget build(BuildContext context) {
    final alreadyIn = isIn(context);
    final materialTheme = Theme.of(context);
    final prismChild = prism.ElevatedSurfaceTheme(child: child);
    final Widget scoped = _ElevatedMaterialScope(child: prismChild);
    if (alreadyIn || materialTheme.brightness != Brightness.dark) {
      return scoped;
    }
    return Theme(
      data: materialTheme.copyWith(
        colorScheme: elevatedColorScheme(materialTheme.colorScheme),
      ),
      child: scoped,
    );
  }
}

class _ElevatedMaterialScope extends InheritedWidget {
  const _ElevatedMaterialScope({required super.child});

  @override
  bool updateShouldNotify(_ElevatedMaterialScope oldWidget) => false;
}

/// 基于 `prism_ui` `PressSurface` 的通用列表行/卡片交互区域。
class AnimatedInkWell extends StatelessWidget {
  const AnimatedInkWell({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.customBorder,
    this.hoverColor,
    this.inkColor,
    this.statesController,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;
  final Color? hoverColor;
  final Color? inkColor;
  final WidgetStatesController? statesController;

  @override
  Widget build(BuildContext context) {
    final OutlinedBorder shape = switch (customBorder) {
      final OutlinedBorder border => border,
      _ =>
        borderRadius != null
            ? prism.AppShape.of(borderRadius!)
            : prism.AppShape.none,
    };

    Widget body = child;
    if (onLongPress != null) {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: onLongPress,
        child: body,
      );
    }

    return prism.PressSurface(
      fill: Colors.transparent,
      shape: shape,
      look: prism.PressLook.tint,
      inkColor: inkColor,
      statesController: statesController,
      onPressed: onTap,
      childFills: true,
      child: body,
    );
  }
}

const double _optionsValueMaxWidth = 160.0;

class OptionsValueButton extends StatelessWidget {
  const OptionsValueButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return prism.TextButton(
      onPressed: onPressed,
      style: prism.ButtonStyle.from(
        foregroundColor: scheme.onSurfaceVariant,
        textStyle: prism.AppTextStyle.subheadline.of(context),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: prism.TapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _optionsValueMaxWidth),
            child: prism.PopupValueText(
              label,
              alignment: AlignmentDirectional.centerEnd,
            ),
          ),
          GlyphIcon(
            Glyphs.picker,
            size: IconSizes.medium,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// 隔离上游 `prism_ui` `_StyledButtonState.didUpdateWidget` 在启用/选中态切换时同步触发 `setState` 的问题。
class IconButton extends StatelessWidget {
  const IconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.selectedIcon,
    this.isSelected,
    this.iconSize,
    this.padding,
    this.style,
  }) : _filled = false;

  const IconButton.filled({
    super.key,
    required this.onPressed,
    required this.icon,
    this.iconSize,
    this.padding,
    this.style,
  }) : selectedIcon = null,
       isSelected = null,
       _filled = true;

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget? selectedIcon;
  final bool? isSelected;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final prism.ButtonStyle? style;
  final bool _filled;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey((onPressed != null, isSelected ?? false));
    if (_filled) {
      return prism.IconButton.filled(
        key: key,
        onPressed: onPressed,
        icon: icon,
        iconSize: iconSize,
        padding: padding,
        style: style,
      );
    }
    return prism.IconButton(
      key: key,
      onPressed: onPressed,
      icon: icon,
      selectedIcon: selectedIcon,
      isSelected: isSelected,
      iconSize: iconSize,
      padding: padding,
      style: style,
    );
  }
}

abstract class _PrismLabelButton extends StatelessWidget {
  const _PrismLabelButton({
    super.key,
    required this.onPressed,
    this.style,
    required this.child,
  }) : icon = null;

  const _PrismLabelButton.icon({
    super.key,
    required this.onPressed,
    this.style,
    required Widget this.icon,
    required Widget label,
  }) : child = label;

  final VoidCallback? onPressed;
  final prism.ButtonStyle? style;
  final Widget? icon;
  final Widget child;
}

class TextButton extends _PrismLabelButton {
  const TextButton({
    super.key,
    required super.onPressed,
    super.style,
    required super.child,
  });

  const TextButton.icon({
    super.key,
    required super.onPressed,
    super.style,
    required super.icon,
    required super.label,
  }) : super.icon();

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(onPressed != null);
    if (icon case final icon?) {
      return prism.TextButton.icon(
        key: key,
        onPressed: onPressed,
        style: style,
        icon: icon,
        label: child,
      );
    }
    return prism.TextButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

class FilledButton extends _PrismLabelButton {
  const FilledButton({
    super.key,
    required super.onPressed,
    super.style,
    required super.child,
  });

  const FilledButton.icon({
    super.key,
    required super.onPressed,
    super.style,
    required super.icon,
    required super.label,
  }) : super.icon();

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(onPressed != null);
    if (icon case final icon?) {
      return prism.FilledButton.icon(
        key: key,
        onPressed: onPressed,
        style: style,
        icon: icon,
        label: child,
      );
    }
    return prism.FilledButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

class OutlinedButton extends _PrismLabelButton {
  const OutlinedButton({
    super.key,
    required super.onPressed,
    super.style,
    required super.child,
  });

  const OutlinedButton.icon({
    super.key,
    required super.onPressed,
    super.style,
    required super.icon,
    required super.label,
  }) : super.icon();

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(onPressed != null);
    if (icon case final icon?) {
      return prism.OutlinedButton.icon(
        key: key,
        onPressed: onPressed,
        style: style,
        icon: icon,
        label: child,
      );
    }
    return prism.OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}
