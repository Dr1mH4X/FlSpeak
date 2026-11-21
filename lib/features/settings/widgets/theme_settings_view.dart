// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目，
// 原始许可证为 GPL-3.0，来源提交 be84736605527034689c95bf27828ff27d912c5e。
// 对应 lib/views/theme.dart 中的主题模式、纯黑模式、主题色/配色风格/自定义调色板、
// 底部导航栏、液态玻璃、字体与文字缩放设置项。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        PopupMenuItem,
        Slider,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/prism.dart';
import '../../../widgets/window_header.dart';
import 'font_family_view.dart';
import 'palette.dart';
import 'settings_section.dart';
import 'theme_preview.dart';

String _colorStyleLabel(AppLocalizations l10n, AppColorStyle style) {
  return switch (style) {
    AppColorStyle.vivid => l10n.settingsColorStyleVivid,
    AppColorStyle.tinted => l10n.settingsColorStyleTinted,
    AppColorStyle.soft => l10n.settingsColorStyleSoft,
    AppColorStyle.monochrome => l10n.settingsColorStyleMonochrome,
  };
}

String _liquidGlassLabel(AppLocalizations l10n, LiquidGlassMode mode) {
  return switch (mode) {
    LiquidGlassMode.none => l10n.settingsLiquidGlassNone,
    LiquidGlassMode.standard => l10n.settingsLiquidGlassStandard,
    LiquidGlassMode.ultra => l10n.settingsLiquidGlassUltra,
  };
}

/// 「外观与主题」终末页内容：顶部放唯一交互式实时预览，下方使用分组列表展示全套主题开关。
class ThemeSettingsView extends ConsumerWidget {
  const ThemeSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThemeLivePreview(),
        SizedBox(height: 20),
        _ThemeModeSection(),
        _PureBlackSection(),
        _ThemeColorSection(),
        _BottomBarSection(),
        _LiquidGlassSection(),
        _FontFamilySection(),
        _TextScaleSection(),
      ],
    );
  }
}

class _SelectionOption<T> {
  const _SelectionOption(this.value, this.label);

  final T value;
  final String label;
}

class _ThemeChoiceSection<T> extends StatelessWidget {
  const _ThemeChoiceSection({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final T value;
  final List<_SelectionOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return generateSection(
      title: title,
      items: [
        for (final option in options)
          DecorationListItem(
            title: Text(option.label),
            isSelected: option.value == value,
            trailing: option.value == value ? const SelectionCheck() : null,
            onPressed: () => onChanged(option.value),
          ),
      ],
    );
  }
}

class _ThemeModeSection extends ConsumerWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = ref.watch(preferencesProvider.select((prefs) => prefs.theme));
    return _ThemeChoiceSection<AppThemePreference>(
      title: l10n.settingsThemeMode,
      value: theme,
      options: [
        _SelectionOption(AppThemePreference.system, l10n.settingsThemeSystem),
        _SelectionOption(AppThemePreference.light, l10n.settingsThemeLight),
        _SelectionOption(AppThemePreference.dark, l10n.settingsThemeDark),
      ],
      onChanged: ref.read(preferencesProvider.notifier).setTheme,
    );
  }
}

class _PureBlackSection extends ConsumerWidget {
  const _PureBlackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pureBlack = ref.watch(
      preferencesProvider.select((prefs) => prefs.pureBlack),
    );
    return _ThemeChoiceSection<bool>(
      title: l10n.settingsPureBlackMode,
      value: pureBlack,
      options: [
        _SelectionOption(false, l10n.settingsPureBlackStandard),
        _SelectionOption(true, l10n.settingsPureBlackOn),
      ],
      onChanged: ref.read(preferencesProvider.notifier).setPureBlack,
    );
  }
}

class _ThemeColorSection extends ConsumerWidget {
  const _ThemeColorSection();

  Future<bool> _confirmDestructive(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final confirmed = await showAppModal<bool>(
      context,
      title: title,
      builder: (modalContext) => Text(
        message,
        style: modalContext.texts.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
      footer: (modalContext) => Flexible(
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(modalContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              style: ButtonStyle.from(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(modalContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    return confirmed == true;
  }

  Future<void> _handleReset(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirmDestructive(
      context,
      title: l10n.settingsReset,
      message: l10n.settingsResetThemeColorsTip,
      confirmLabel: l10n.settingsReset,
    );
    if (!ok || !context.mounted) {
      return;
    }
    ref
        .read(preferencesProvider.notifier)
        .updateThemePalette(
          primaryColors: defaultPrimaryColors,
          primaryColor: defaultPrimaryColor,
          colorStyle: AppColorStyle.vivid,
        );
  }

  Future<void> _handleDelete(
    BuildContext context,
    WidgetRef ref,
    int color,
  ) async {
    final l10n = AppLocalizations.of(context);
    final currentColors = ref.read(preferencesProvider).primaryColors;
    if (currentColors.length <= 1) {
      return;
    }
    final hex = Color(color).hex;
    final ok = await _confirmDestructive(
      context,
      title: l10n.settingsColorDelete,
      message: l10n.settingsDeleteColorTip(hex),
      confirmLabel: l10n.settingsColorDelete,
    );
    if (!ok || !context.mounted) {
      return;
    }
    final prefs = ref.read(preferencesProvider);
    final nextColors = List<int>.from(prefs.primaryColors)..remove(color);
    if (nextColors.isEmpty) {
      nextColors.add(defaultPrimaryColor);
    }
    var nextPrimary = prefs.primaryColor;
    if (nextPrimary == color) {
      nextPrimary = nextColors.contains(defaultPrimaryColor)
          ? defaultPrimaryColor
          : nextColors.first;
    }
    ref
        .read(preferencesProvider.notifier)
        .updateThemePalette(
          primaryColors: nextColors,
          primaryColor: nextPrimary,
        );
  }

  void _showColorSheet(
    BuildContext context,
    Color initialColor,
    ValueChanged<int> onConfirmed,
  ) {
    showSheet<void>(
      context: context,
      props: const SheetProps(detents: [0.9]),
      builder: (_) => _CustomColorSheet(
        initialColor: initialColor,
        onConfirmed: (color) {
          if (context.mounted) {
            onConfirmed(color);
          }
        },
      ),
    );
  }

  void _handleAdd(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.read(preferencesProvider).primaryColor;
    _showColorSheet(context, Color(primaryColor), (color) {
      final prefs = ref.read(preferencesProvider);
      final nextColors = prefs.primaryColors.contains(color)
          ? prefs.primaryColors
          : [...prefs.primaryColors, color];
      ref
          .read(preferencesProvider.notifier)
          .updateThemePalette(primaryColors: nextColors, primaryColor: color);
    });
  }

  void _handleEdit(BuildContext context, WidgetRef ref, int color) {
    _showColorSheet(context, Color(color), (edited) {
      final prefs = ref.read(preferencesProvider);
      final index = prefs.primaryColors.indexOf(color);
      if (edited == color || index == -1) {
        return;
      }
      final nextColors = List<int>.from(prefs.primaryColors);
      if (nextColors.contains(edited)) {
        nextColors.removeAt(index);
      } else {
        nextColors[index] = edited;
      }
      ref
          .read(preferencesProvider.notifier)
          .updateThemePalette(
            primaryColors: nextColors,
            primaryColor: prefs.primaryColor == color
                ? edited
                : prefs.primaryColor,
          );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final (:primaryColor, :primaryColors, :colorStyle) = ref.watch(
      preferencesProvider.select(
        (prefs) => (
          primaryColor: prefs.primaryColor,
          primaryColors: prefs.primaryColors,
          colorStyle: prefs.colorStyle,
        ),
      ),
    );
    final isDefault =
        primaryColor == defaultPrimaryColor &&
        listEquals(primaryColors, defaultPrimaryColors) &&
        colorStyle == AppColorStyle.vivid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListHeader(
            title: l10n.settingsThemeColor,
            trailing: isDefault
                ? null
                : _ResetButton(
                    label: l10n.settingsReset,
                    onPressed: () => unawaited(_handleReset(context, ref)),
                  ),
          ),
          const SizedBox(height: 8),
          _ColorSwatches(
            colors: primaryColors,
            selected: primaryColor,
            canDelete: primaryColors.length > 1,
            onSelect: ref.read(preferencesProvider.notifier).setPrimaryColor,
            onEdit: (color) => _handleEdit(context, ref, color),
            onDelete: (color) => unawaited(_handleDelete(context, ref, color)),
            onAdd: () => _handleAdd(context, ref),
          ),
          const SizedBox(height: 8),
          generateGroup([
            ListItem<AppColorStyle>.options(
              title: Text(l10n.settingsColorStyle),
              options: AppColorStyle.values,
              value: colorStyle,
              textBuilder: (style) => _colorStyleLabel(l10n, style),
              onChanged: ref.read(preferencesProvider.notifier).setColorStyle,
            ),
          ]),
        ],
      ),
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({
    required this.colors,
    required this.selected,
    required this.canDelete,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
  });

  static const double _minGap = 6;
  static const double _inset = 16 - (_ColorSwatch.size - _ColorSwatch.dot) / 2;

  final List<int> colors;
  final int selected;
  final bool canDelete;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final level = context.raisedSurfaceLevel;
    return Container(
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceColor,
        shape: AppShape.xl,
      ),
      child: SurfaceScope(
        level: level,
        child: LayoutBuilder(
          builder: (_, constraints) {
            const cell = _ColorSwatch.size;
            final width = constraints.maxWidth;
            final columns = math.max(
              1,
              ((width + _minGap) / (cell + _minGap)).floor(),
            );
            final gap = columns > 1
                ? ((width - columns * cell) / (columns - 1)).floorToDouble()
                : 0.0;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final colorValue in colors)
                  _ColorSwatch(
                    color: Color(colorValue),
                    isSelected: colorValue == selected,
                    label: Color(colorValue).hex,
                    onPressed: () => onSelect(colorValue),
                    menuItems: [
                      PopupMenuItem(
                        glyph: AppGlyphs.edit,
                        label: l10n.settingsColorEdit,
                        onPressed: () => onEdit(colorValue),
                      ),
                      if (canDelete)
                        PopupMenuItem(
                          danger: true,
                          glyph: AppGlyphs.delete,
                          label: l10n.settingsColorDelete,
                          onPressed: () => onDelete(colorValue),
                        ),
                    ],
                  ),
                _AddColorButton(label: l10n.settingsAddColor, onPressed: onAdd),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.label,
    required this.onPressed,
    required this.menuItems,
  });

  static const double size = 44;
  static const double dot = 32;
  static const double _ring = 2.5;
  static const _duration = Duration(milliseconds: 200);

  final Color color;
  final bool isSelected;
  final String label;
  final VoidCallback onPressed;
  final List<PopupMenuItem> menuItems;

  @override
  Widget build(BuildContext context) {
    final check = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final swatch = SizedBox.square(
      dimension: size,
      child: PressSurface(
        fill: Colors.transparent,
        shape: AppShape.circle,
        ringStandsOff: isSelected,
        selected: isSelected,
        childFills: true,
        onPressed: onPressed,
        child: Semantics(
          button: true,
          selected: isSelected,
          label: label,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: isSelected ? 1 : 0,
                duration: _duration,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: AppShape.circle.copyWith(
                      side: BorderSide(color: color, width: _ring),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              SizedBox.square(
                dimension: dot,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: color,
                    shape: AppShape.circle,
                  ),
                ),
              ),
              AnimatedScale(
                scale: isSelected ? 1 : 0,
                duration: _duration,
                curve: Curves.easeOutBack,
                child: GlyphIcon(Glyphs.check, size: 18, fill: 1, color: check),
              ),
            ],
          ),
        ),
      ),
    );
    return ContextMenuRegion(menuItems: menuItems, child: swatch);
  }
}

class _AddColorButton extends StatelessWidget {
  const _AddColorButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: _ColorSwatch.size,
        child: PressSurface(
          fill: Colors.transparent,
          shape: AppShape.circle,
          childFills: true,
          onPressed: onPressed,
          child: Center(
            child: Container(
              width: _ColorSwatch.dot,
              height: _ColorSwatch.dot,
              decoration: ShapeDecoration(
                color: context.raisedSurfaceColor,
                shape: AppShape.circle,
              ),
              child: GlyphIcon(
                AppGlyphs.add,
                size: 20,
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBarSection extends ConsumerWidget {
  const _BottomBarSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final floating = ref.watch(
      preferencesProvider.select((prefs) => prefs.floatingNavigationBar),
    );
    return _ThemeChoiceSection<bool>(
      title: l10n.settingsBottomBar,
      value: floating,
      options: [
        _SelectionOption(true, l10n.settingsBottomBarFloating),
        _SelectionOption(false, l10n.settingsBottomBarDocked),
      ],
      onChanged: ref
          .read(preferencesProvider.notifier)
          .setFloatingNavigationBar,
    );
  }
}

class _LiquidGlassSection extends ConsumerWidget {
  const _LiquidGlassSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final liquidGlass = ref.watch(
      preferencesProvider.select((prefs) => prefs.liquidGlass),
    );
    return _ThemeChoiceSection<LiquidGlassMode>(
      title: l10n.settingsLiquidGlass,
      value: liquidGlass,
      options: [
        for (final mode in LiquidGlassMode.values)
          _SelectionOption(mode, _liquidGlassLabel(l10n, mode)),
      ],
      onChanged: ref.read(preferencesProvider.notifier).setLiquidGlass,
    );
  }
}

class _FontFamilySection extends ConsumerWidget {
  const _FontFamilySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final fontFamily = ref.watch(
      preferencesProvider.select((prefs) => prefs.fontFamily),
    );
    final preview = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        spacing: 12,
        children: [
          Text(
            'Aa',
            style: AppTextStyle.headline
                .of(context)
                .copyWith(fontFamily: fontFamily),
          ),
          Expanded(
            child: Text(
              fontFamily ?? l10n.settingsFontDefault,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(
                    fontFamily: fontFamily,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          GlyphIcon(
            Glyphs.chevronForward,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
    final cardColor = context.raisedSurfaceColor;
    Widget card(VoidCallback onTap) => PressSurface(
      fill: cardColor,
      shape: AppShape.lg,
      childFills: true,
      clipsChild: true,
      onPressed: onTap,
      child: preview,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListHeader(title: l10n.settingsFontFamily),
          const SizedBox(height: 8),
          context.isCompact
              ? OpenContainer<void>(
                  closedShape: AppShape.lg,
                  closedBuilder: (_, open) => card(open),
                  openBuilder: (_, _) => const FontFamilyView(),
                )
              : card(
                  () => showSheet<void>(
                    context: context,
                    builder: (_) => const FontFamilyView(),
                  ),
                ),
        ],
      ),
    );
  }
}

class _TextScaleSection extends ConsumerStatefulWidget {
  const _TextScaleSection();

  static const _step = 0.05;

  @override
  ConsumerState<_TextScaleSection> createState() => _TextScaleSectionState();
}

class _TextScaleSectionState extends ConsumerState<_TextScaleSection> {
  double? _draft;

  void _update({bool? enabled, double? scale}) {
    setState(() => _draft = null);
    ref
        .read(preferencesProvider.notifier)
        .setTextScale(enabled: enabled, scale: scale);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final (:enabled, :scaleValue) = ref.watch(
      preferencesProvider.select(
        (prefs) =>
            (enabled: prefs.textScaleEnabled, scaleValue: prefs.textScale),
      ),
    );
    final systemScale = WidgetsBinding
        .instance
        .platformDispatcher
        .textScaleFactor
        .clamp(minTextScale, maxTextScale)
        .toDouble();
    final scale = _draft ?? (enabled ? scaleValue : systemScale);
    final percent = '${(scale * 100).round()}%';
    final level = context.raisedSurfaceLevel;
    final divisions = ((maxTextScale - minTextScale) / _TextScaleSection._step)
        .round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListHeader(
            title: l10n.settingsTextScale,
            trailing: enabled && scaleValue != 1.0
                ? _ResetButton(
                    label: l10n.settingsReset,
                    onPressed: () => _update(scale: 1.0),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          SegmentedControl<bool>(
            segments: [
              (false, l10n.settingsTextScaleSystem),
              (true, l10n.settingsTextScaleCustom),
            ],
            value: enabled,
            onChanged: (value) => _update(enabled: value),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            decoration: ShapeDecoration(
              color: context.raisedSurfaceColor,
              shape: AppShape.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Expanded(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topLeft,
                        child: MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaler: TextScaler.linear(scale)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 4,
                            children: [
                              Text(
                                'Aa',
                                style: AppTextStyle.title3.of(context),
                              ),
                              Text(
                                l10n.settingsTextScalePreview,
                                style: AppTextStyle.subheadline
                                    .of(context)
                                    .copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: ShapeDecoration(
                        color: surfaceColorFor(level.next, scheme),
                        shape: AppShape.full,
                      ),
                      child: Text(
                        percent,
                        style: AppTextStyle.subheadline
                            .of(context, emphasized: true)
                            .copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MediaQuery.withNoTextScaling(
                  child: Row(
                    spacing: 12,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          'A',
                          style: AppTextStyle.footnote
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          min: minTextScale,
                          max: maxTextScale,
                          divisions: divisions,
                          value: scale,
                          label: percent,
                          onChanged: enabled
                              ? (value) => setState(() => _draft = value)
                              : null,
                          onChangeEnd: (value) => _update(scale: value),
                        ),
                      ),
                      ExcludeSemantics(
                        child: Text(
                          'A',
                          style: AppTextStyle.title2
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TonalButtonTheme(
      size: TonalButtonSize.section,
      child: ElasticPress(
        child: IconButton(
          onPressed: onPressed,
          icon: Semantics(
            label: label,
            child: const GlyphIcon(AppGlyphs.reset),
          ),
        ),
      ),
    );
  }
}

class _CustomColorSheet extends StatefulWidget {
  const _CustomColorSheet({
    required this.initialColor,
    required this.onConfirmed,
  });

  final Color initialColor;
  final ValueChanged<int> onConfirmed;

  @override
  State<_CustomColorSheet> createState() => _CustomColorSheetState();
}

class _CustomColorSheetState extends State<_CustomColorSheet> {
  late final _controller = ValueNotifier<Color>(widget.initialColor);
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = sheetScrollController(context);
  }

  void _confirm() {
    final color = _controller.value.toARGB32();
    final onConfirmed = widget.onConfirmed;
    final route = ModalRoute.of(context);
    if (route != null) {
      unawaited(route.completed.whenComplete(() => onConfirmed(color)));
    } else {
      onConfirmed(color);
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gestureInsets = MediaQuery.systemGestureInsetsOf(context);
    final hasDragHandle =
        SheetProvider.of(context)?.type == SheetType.bottomSheet;

    return Material(
      type: MaterialType.transparency,
      child: Surface(
        color: context.pageColor,
        child: SafeArea(
          child: Column(
            children: [
              if (hasDragHandle) const SheetDragHandle(),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.header),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      TonalButtonTheme(
                        glass: LiquidGlassScope.of(context),
                        child: ElasticPress(
                          child: IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            iconSize: IconSizes.toolbar,
                            icon: Semantics(
                              label: MaterialLocalizations.of(context)
                                  .closeButtonTooltip,
                              child: const GlyphIcon(Glyphs.close),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: WindowDragRegion(
                          child: Semantics(
                            header: true,
                            child: Text(
                              l10n.settingsCustomColor,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.pageTitle.of(context),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TonalButtonTheme(
                        glass: LiquidGlassScope.of(context),
                        child: ElasticPress(
                          child: IconButton.filled(
                            onPressed: _confirm,
                            icon: Semantics(
                              label: l10n.commonDone,
                              child: const GlyphIcon(Glyphs.check),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    math.max(16, gestureInsets.left),
                    8,
                    math.max(16, gestureInsets.right),
                    24,
                  ),
                  children: [
                    ValueListenableBuilder(
                      valueListenable: _controller,
                      builder: (_, color, _) => _CustomColorPreview(
                        color: color,
                        onChanged: (next) => _controller.value = next,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Palette(controller: _controller),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomColorPreview extends ConsumerWidget {
  const _CustomColorPreview({required this.color, required this.onChanged});

  static const Size _screenSize = Size(96, 128);
  static const double _scale = 0.75;

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:colorStyle, :pureBlack, :floatingBar, :liquidGlass) = ref.watch(
      preferencesProvider.select(
        (prefs) => (
          colorStyle: prefs.colorStyle,
          pureBlack: prefs.pureBlack,
          floatingBar: prefs.floatingNavigationBar,
          liquidGlass: prefs.liquidGlass != LiquidGlassMode.none,
        ),
      ),
    );
    final level = context.raisedSurfaceLevel;

    Widget screen(Brightness brightness) => ExcludeSemantics(
      child: SizedBox.fromSize(
        size: _screenSize * _scale,
        child: ClipRSuperellipse(
          borderRadius: AppRadius.md,
          child: FittedBox(
            child: SizedBox.fromSize(
              size: _screenSize,
              child: MiniScreen(
                colorScheme: buildAppColorScheme(
                  brightness: brightness,
                  primaryColor: color.toARGB32(),
                  colorStyle: colorStyle,
                  pureBlack: pureBlack,
                ),
                floatingBar: floatingBar,
                liquidGlass: liquidGlass,
              ),
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceColor,
        shape: AppShape.xl,
      ),
      child: SurfaceScope(
        level: level,
        child: Row(
          spacing: 12,
          children: [
            screen(Brightness.light),
            screen(Brightness.dark),
            Expanded(
              child: HexColorField(color: color, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
