// 本文件包含的代码片段来源于 FlClash（https://github.com/chen08209/FlClash）项目，
// 原始许可证为 GPL-3.0，来源提交 be84736605527034689c95bf27828ff27d912c5e。
// 对应 lib/views/theme_preview.dart 中的 ThemeLivePreview、MiniScreen 与玻璃底栏绘制逻辑。

import 'dart:math' as math;

import 'package:flutter/material.dart' hide kTabScrollDuration;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences.dart';
import '../../../core/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart';

class _ColorSchemeTween extends Tween<ColorScheme> {
  _ColorSchemeTween({super.end});

  @override
  ColorScheme lerp(double t) => ColorScheme.lerp(begin!, end!, t);
}

/// 外观设置页顶部唯一的交互式实时预览卡片，反映明暗、纯黑、主题色、底栏、液态玻璃、
/// 字体与字号缩放效果；点击预览底部导航目的可实时演练标签页切换动画。
class ThemeLivePreview extends ConsumerStatefulWidget {
  const ThemeLivePreview({super.key});

  @override
  ConsumerState<ThemeLivePreview> createState() => _ThemeLivePreviewState();
}

class _ThemeLivePreviewState extends ConsumerState<ThemeLivePreview>
    with SingleTickerProviderStateMixin {
  static const double _phoneWidth = 172;
  static const _duration = Duration(milliseconds: 300);

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: kTabScrollDuration,
  );
  late final CurvedAnimation _slideCurve = CurvedAnimation(
    parent: _slide,
    curve: Curves.easeOut,
  );
  int _selected = 0;
  int? _previous;

  @override
  void initState() {
    super.initState();
    ref.listenManual<TabAnimation>(
      preferencesProvider.select((prefs) => prefs.tabAnimation),
      (_, _) => _select((_selected + 1) % MiniScreen.destinationCount),
    );
  }

  Future<void> _select(int index) async {
    if (index == _selected) {
      return;
    }
    final tabAnimation = ref.read(preferencesProvider).tabAnimation;
    final fade = tabAnimation == TabAnimation.fade;
    _slide.duration = fade ? fadeTabDuration : kTabScrollDuration;
    _slideCurve.curve = fade ? fadeTabCurve : Curves.easeOut;
    setState(() {
      _previous = _selected;
      _selected = index;
    });
    await _slide.forward(from: 0).orCancel.catchError((_) {});
    if (mounted && _selected == index) {
      setState(() => _previous = null);
    }
  }

  @override
  void dispose() {
    _slideCurve.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (
      :themeMode,
      :pureBlack,
      :primaryColor,
      :colorStyle,
      :floatingBar,
      :tabAnimation,
      :liquidGlass,
      :fontFamily,
      :textScaleEnabled,
      :textScale,
    ) = ref.watch(
      preferencesProvider.select(
        (prefs) => (
          themeMode: prefs.theme,
          pureBlack: prefs.pureBlack,
          primaryColor: prefs.primaryColor,
          colorStyle: prefs.colorStyle,
          floatingBar: prefs.floatingNavigationBar,
          tabAnimation: prefs.tabAnimation,
          liquidGlass: prefs.liquidGlass != LiquidGlassMode.none,
          fontFamily: prefs.fontFamily,
          textScaleEnabled: prefs.textScaleEnabled,
          textScale: prefs.textScale,
        ),
      ),
    );
    final brightness = switch (themeMode) {
      AppThemePreference.light => Brightness.light,
      AppThemePreference.dark => Brightness.dark,
      AppThemePreference.system => MediaQuery.platformBrightnessOf(context),
    };
    final previewScheme = buildAppColorScheme(
      brightness: brightness,
      primaryColor: primaryColor,
      colorStyle: colorStyle,
      pureBlack: pureBlack,
    );
    final previewScale = textScaleEnabled
        ? textScale
        : MediaQuery.textScalerOf(context)
              .scale(1.0)
              .clamp(minTextScale, maxTextScale);
    final scheme = context.scheme;
    final corner = AppCorner.fit(_phoneWidth);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: context.raisedSurfaceColor,
        shape: AppShape.xxl,
      ),
      child: SizedBox(
        width: _phoneWidth,
        child: AspectRatio(
          aspectRatio: 9 / 17,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: AppShape.all(corner).copyWith(
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
            ),
            child: ClipRSuperellipse(
              borderRadius: AppRadius.all(corner),
              child: TweenAnimationBuilder<ColorScheme>(
                tween: _ColorSchemeTween(end: previewScheme),
                duration: _duration,
                builder: (_, animatedScheme, _) => AnimatedSwitcher(
                  duration: _duration,
                  child: AnimatedBuilder(
                    key: ValueKey((floatingBar, liquidGlass)),
                    animation: _slideCurve,
                    builder: (_, _) => MiniScreen(
                      colorScheme: animatedScheme,
                      floatingBar: floatingBar,
                      liquidGlass: liquidGlass,
                      fontFamily: fontFamily,
                      textScale: previewScale,
                      selected: _selected,
                      previous: _previous,
                      progress: _previous == null ? 1 : _slideCurve.value,
                      tabAnimation: tabAnimation,
                      onSelect: _select,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _MiniPage { connect, workspace, settings }

/// 缩略预览设备草图，按传入 [colorScheme] 与底部栏模式渲染首页、工作区与设置三个页签。
class MiniScreen extends StatelessWidget {
  const MiniScreen({
    super.key,
    required this.colorScheme,
    required this.floatingBar,
    this.liquidGlass = false,
    this.fontFamily,
    this.textScale = 1.0,
    this.selected = 0,
    this.previous,
    this.progress = 1,
    this.tabAnimation = TabAnimation.slide,
    this.onSelect,
  });

  static const int destinationCount = 3;

  final ColorScheme colorScheme;
  final bool floatingBar;
  final bool liquidGlass;
  final String? fontFamily;
  final double textScale;
  final int selected;
  final int? previous;
  final double progress;
  final TabAnimation tabAnimation;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final sketch = SizedBox.expand(
      child: CustomPaint(
        painter: _MiniScreenPainter(
          colorScheme: colorScheme,
          floatingBar: floatingBar,
          liquidGlass: liquidGlass,
          fontFamily: fontFamily,
          textScale: textScale,
          selected: selected,
          previous: previous,
          progress: progress,
          tabAnimation: tabAnimation,
        ),
      ),
    );
    final onSelect = this.onSelect;
    if (onSelect == null) {
      return ExcludeSemantics(child: sketch);
    }
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (_, constraints) {
          final geometry = _MiniGeometry(
            constraints.biggest,
            floatingBar: floatingBar,
          );
          return Stack(
            children: [
              sketch,
              Positioned.fromRect(
                rect: geometry.bar,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < destinationCount; i++)
                      Expanded(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onSelect(i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MiniGeometry {
  _MiniGeometry(this.size, {required bool floatingBar})
    : unit = size.width / 20 {
    margin = unit * 1.5;
    final barHeight = floatingBar ? unit * 3.2 : unit * 3.6;
    pageBottom = floatingBar ? 0 : barHeight;
    bar = floatingBar
        ? Rect.fromLTWH(
            margin,
            size.height - margin - barHeight,
            size.width - margin * 2,
            barHeight,
          )
        : Rect.fromLTWH(0, size.height - barHeight, size.width, barHeight);
  }

  final Size size;
  final double unit;
  late final double margin;
  late final double pageBottom;
  late final Rect bar;
}

class _MiniScreenPainter extends CustomPainter {
  const _MiniScreenPainter({
    required this.colorScheme,
    required this.floatingBar,
    required this.liquidGlass,
    required this.fontFamily,
    required this.textScale,
    required this.selected,
    required this.previous,
    required this.progress,
    required this.tabAnimation,
  });

  final ColorScheme colorScheme;
  final bool floatingBar;
  final bool liquidGlass;
  final String? fontFamily;
  final double textScale;
  final int selected;
  final int? previous;
  final double progress;
  final TabAnimation tabAnimation;

  bool get _glass => floatingBar && liquidGlass;

  static _MiniPage _pageOf(int index) =>
      _MiniPage.values[index % _MiniPage.values.length];

  static void _fill(
    Canvas canvas,
    Rect rect,
    Color color,
    ShapeBorder shape, {
    List<BoxShadow>? shadows,
    MaskFilter? blur,
  }) {
    if (blur != null) {
      shape.paintInterior(
        canvas,
        rect,
        Paint()
          ..color = color
          ..maskFilter = blur,
      );
      return;
    }
    ShapeDecoration(color: color, shape: shape, shadows: shadows)
        .createBoxPainter(() {})
        .paint(canvas, rect.topLeft, ImageConfiguration(size: rect.size));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _MiniGeometry(size, floatingBar: floatingBar);
    _paintPages(canvas, geometry);
    final unit = geometry.unit;
    final dock = surfaceColorFor(
      floatingSurfaceLevelFor(colorScheme),
      colorScheme,
    );
    final shadow = BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.12),
      blurRadius: unit,
      offset: Offset(0, unit * 0.3),
    );
    if (_glass) {
      _paintGlassBar(canvas, geometry, shadow);
    } else if (floatingBar) {
      _fill(canvas, geometry.bar, dock, AppShape.full, shadows: [shadow]);
    } else {
      canvas.drawRect(geometry.bar, Paint()..color = dock);
    }
    _paintDestinations(canvas, geometry.bar, unit);
  }

  void _paintPages(Canvas canvas, _MiniGeometry geometry, {MaskFilter? blur}) {
    final size = geometry.size;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = surfaceColorFor(SurfaceLevel.page, colorScheme),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size, doAntiAlias: false);
    final previous = this.previous;
    if (previous == null) {
      _paintPage(canvas, geometry, selected, 0, blur: blur);
    } else if (tabAnimation == TabAnimation.fade) {
      _paintPage(
        canvas,
        geometry,
        previous,
        0,
        opacity: 1 - progress,
        blur: blur,
      );
      _paintPage(canvas, geometry, selected, 0, opacity: progress, blur: blur);
    } else {
      final direction = previous > selected ? -1 : 1;
      _paintPage(
        canvas,
        geometry,
        previous,
        -direction * size.width * progress,
        blur: blur,
      );
      _paintPage(
        canvas,
        geometry,
        selected,
        direction * size.width * (1 - progress),
        blur: blur,
      );
    }
    canvas.restore();
  }

  void _paintGlassBar(Canvas canvas, _MiniGeometry geometry, BoxShadow shadow) {
    final bar = geometry.bar;
    final unit = geometry.unit;
    final path = AppShape.full.getOuterPath(bar);
    final style = LiquidGlassStyle.pill(toPrismColorScheme(colorScheme));
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(bar.inflate(unit * 3))
          ..addPath(path, Offset.zero),
      );
    AppShape.full.paintInterior(
      canvas,
      bar.shift(shadow.offset),
      shadow.toPaint(),
    );
    canvas
      ..restore()
      ..save()
      ..clipPath(path);
    _paintPages(
      canvas,
      geometry,
      blur: MaskFilter.blur(BlurStyle.normal, unit * 0.4),
    );
    final rimWidth = unit * 0.15;
    canvas
      ..drawPath(path, Paint()..color = style.tint)
      ..drawPath(
        AppShape.full.getOuterPath(bar.deflate(rimWidth / 2)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rimWidth
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: style.rim),
              Colors.white.withValues(alpha: style.rim * 0.15),
              Colors.white.withValues(alpha: style.rim * 0.5),
            ],
          ).createShader(bar),
      )
      ..restore();
  }

  void _paintPage(
    Canvas canvas,
    _MiniGeometry geometry,
    int index,
    double offset, {
    double opacity = 1,
    MaskFilter? blur,
  }) {
    final alpha = Color.getAlphaFromOpacity(opacity);
    if (alpha == 0) {
      return;
    }
    final size = geometry.size;
    final margin = geometry.margin;
    final content = Rect.fromLTRB(
      offset + margin,
      margin,
      offset + size.width - margin,
      size.height - geometry.pageBottom,
    );
    if (alpha < 255) {
      canvas.saveLayer(null, Paint()..color = Color.fromARGB(alpha, 0, 0, 0));
    } else {
      canvas.save();
    }
    canvas.clipRect(content, doAntiAlias: false);
    _PageSketch(
      canvas,
      colorScheme,
      geometry.unit,
      content,
      fontFamily: fontFamily,
      textScale: textScale,
      blur: blur,
    ).paint(_pageOf(index));
    canvas.restore();
  }

  void _paintDestinations(Canvas canvas, Rect bar, double unit) {
    final cell = bar.width / MiniScreen.destinationCount;
    final dark = colorScheme.brightness == Brightness.dark;
    final indicator = _glass
        ? colorScheme.onSurface.withValues(alpha: dark ? 0.14 : 0.08)
        : surfaceColorFor(
            floatingSurfaceLevelFor(colorScheme).next,
            colorScheme,
          );
    for (var i = 0; i < MiniScreen.destinationCount; i++) {
      final center = Offset(bar.left + cell * i + cell / 2, bar.center.dy);
      final icon = center.translate(0, -unit * 0.4);
      final isSelected = i == selected % MiniScreen.destinationCount;
      if (isSelected) {
        _fill(
          canvas,
          floatingBar
              ? Rect.fromCenter(
                  center: center,
                  width: math.max(unit * 2.5, cell - unit * 0.8),
                  height: bar.height - unit * 0.5,
                )
              : Rect.fromCenter(
                  center: icon,
                  width: unit * 2.8,
                  height: unit * 1.5,
                ),
          indicator,
          AppShape.full,
        );
      }
      final ink = isSelected
          ? colorScheme.primary
          : colorScheme.onSurfaceVariant;
      _fill(
        canvas,
        Rect.fromCircle(center: icon, radius: unit * 0.45),
        ink,
        AppShape.circle,
      );
      _fill(
        canvas,
        Rect.fromCenter(
          center: center.translate(0, unit * 0.8),
          width: unit * 2.0,
          height: unit * 0.35,
        ),
        isSelected ? ink : ink.withValues(alpha: 0.6),
        AppShape.full,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniScreenPainter oldDelegate) {
    return oldDelegate.colorScheme != colorScheme ||
        oldDelegate.floatingBar != floatingBar ||
        oldDelegate.liquidGlass != liquidGlass ||
        oldDelegate.fontFamily != fontFamily ||
        oldDelegate.textScale != textScale ||
        oldDelegate.selected != selected ||
        oldDelegate.previous != previous ||
        oldDelegate.progress != progress ||
        oldDelegate.tabAnimation != tabAnimation;
  }
}

class _PageSketch {
  _PageSketch(
    this.canvas,
    this.colorScheme,
    this.unit,
    this.content, {
    this.fontFamily,
    this.textScale = 1.0,
    this.blur,
  }) : width = content.width / unit,
       card = surfaceColorFor(SurfaceLevel.card, colorScheme),
       inset = surfaceColorFor(SurfaceLevel.inset, colorScheme),
       text = colorScheme.onSurface.withValues(alpha: 0.72),
       line = colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
       faint = colorScheme.onSurfaceVariant.withValues(alpha: 0.16);

  static const double _gap = 0.6;

  final Canvas canvas;
  final ColorScheme colorScheme;
  final double unit;
  final Rect content;
  final String? fontFamily;
  final double textScale;
  final MaskFilter? blur;
  final double width;
  final Color card;
  final Color inset;
  final Color text;
  final Color line;
  final Color faint;

  void paint(_MiniPage page) {
    switch (page) {
      case _MiniPage.connect:
        _connect(_header(actions: 1));
      case _MiniPage.workspace:
        _workspace(_header(actions: 3));
      case _MiniPage.settings:
        _settings(_header(actions: 0));
    }
  }

  Rect _rect(double x, double y, double w, double h) => Rect.fromLTWH(
    content.left + x * unit,
    content.top + y * unit,
    w * unit,
    h * unit,
  );

  ShapeBorder _shape(double extent) =>
      AppShape.all(AppCorner.fit(unit * extent));

  void _block(Rect rect, Color color, {double extent = 5}) {
    _MiniScreenPainter._fill(canvas, rect, color, _shape(extent), blur: blur);
  }

  void _pill(double x, double y, double w, double h, Color color) {
    _MiniScreenPainter._fill(
      canvas,
      _rect(x, y, w, h),
      color,
      AppShape.full,
      blur: blur,
    );
  }

  void _dot(double x, double y, double radius, Color color) {
    _MiniScreenPainter._fill(
      canvas,
      _rect(x - radius, y - radius, radius * 2, radius * 2),
      color,
      AppShape.circle,
      blur: blur,
    );
  }

  double _header({required int actions}) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Aa',
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: unit * 1.45 * textScale.clamp(0.85, 1.25),
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    try {
      painter.paint(canvas, Offset(content.left, content.top + unit * 0.1));
    } finally {
      painter.dispose();
    }
    _pill(3.4, 0.55, 4.6, 0.9, line);
    for (var i = 0; i < actions; i++) {
      final x = width - 1 - i * 2.4;
      _dot(x, 1, 1, card);
      _dot(x, 1, 0.3, line);
    }
    return 2.9;
  }

  void _connect(double top) {
    var y = top;
    // 在线频道状态概览卡
    final hero = _rect(0, y, width, 6.2);
    final buttonX = width - 2.9;
    final buttonY = y + 3.1;
    _block(hero, card);
    canvas
      ..save()
      ..clipPath(_shape(5).getOuterPath(hero))
      ..drawCircle(
        _rect(buttonX, buttonY, 0, 0).topLeft,
        unit * 4.4,
        Paint()
          ..color = colorScheme.primary.withValues(alpha: 0.1)
          ..maskFilter = blur,
      )
      ..restore();
    _dot(buttonX, buttonY, 1.7, colorScheme.primary);
    _pill(1, y + 0.95, 3.8, 0.75, line);
    _pill(1, y + 2.35, 6.4, 1.2, text);
    _pill(1, y + 4.3, 4.6, 0.65, colorScheme.primary.withValues(alpha: 0.75));

    y += 6.2 + _gap;
    // 服务器卡片列表
    for (var i = 0; i < 3; i++) {
      final row = _rect(0, y, width, 4.2);
      _block(row, card, extent: 4.2);
      _dot(2, y + 2.1, 1.0, i == 0 ? colorScheme.primary : inset);
      _pill(4, y + 1.25, i == 0 ? 6.4 : 5.2, 0.8, text);
      _pill(4, y + 2.55, 8.2, 0.55, faint);
      y += 4.2 + _gap;
    }

    // 对话输入条草图
    final composer = _rect(0, y + 0.4, width, 3.4);
    _block(composer, inset, extent: 3.4);
    _pill(1.1, y + 1.7, width - 5.2, 0.85, line);
    _dot(width - 1.7, y + 2.1, 0.95, colorScheme.primary);
  }

  void _workspace(double top) {
    var y = top;
    // 一级频道树列表草图（含选中频道与在线成员）
    for (var i = 0; i < 3; i++) {
      final active = i == 0;
      final row = _rect(0, y, width, active ? 5.6 : 3.8);
      _block(
        row,
        active ? colorScheme.primaryContainer.withValues(alpha: 0.7) : card,
        extent: 4.0,
      );
      _dot(1.6, y + 1.9, 0.75, active ? colorScheme.primary : line);
      _pill(
        3.2,
        y + 1.5,
        active ? 6.8 : 5.4,
        0.8,
        active ? colorScheme.onPrimaryContainer : text,
      );
      if (active) {
        _dot(2.4, y + 3.9, 0.65, colorScheme.primary);
        _pill(3.8, y + 3.6, 5.2, 0.65, colorScheme.onPrimaryContainer);
        _dot(width - 1.8, y + 3.9, 0.45, colorScheme.primary);
      }
      y += (active ? 5.6 : 3.8) + _gap;
    }

    final footer = _rect(0, y + 0.4, width, 4.4);
    _block(footer, card, extent: 4.4);
    _dot(1.8, y + 2.6, 0.9, colorScheme.primary);
    _pill(3.5, y + 2.1, 6.2, 0.9, text);
  }

  void _settings(double top) {
    var y = top;
    // 主题分组卡片与选中指示条
    final firstGroup = _rect(0, y, width, 9.6);
    _block(firstGroup, card);
    for (var i = 0; i < 3; i++) {
      final rowY = y + 1.4 + i * 3.0;
      _dot(1.8, rowY + 0.45, 0.65, i == 0 ? colorScheme.primary : line);
      _pill(3.4, rowY + 0.1, i == 0 ? 5.8 : 4.8, 0.75, text);
      if (i == 0) {
        _pill(width - 3.6, rowY - 0.1, 2.4, 1.15, colorScheme.primary);
      } else {
        _pill(width - 3.0, rowY + 0.1, 1.8, 0.7, faint);
      }
    }

    y += 9.6 + _gap * 2;
    // 字体/滑块与开关分组
    final secondGroup = _rect(0, y, width, 7.6);
    _block(secondGroup, card);
    _pill(1.2, y + 1.4, 5.2, 0.75, text);
    _pill(1.2, y + 3.0, width - 2.4, 0.5, faint);
    _pill(1.2, y + 3.0, (width - 2.4) * 0.62, 0.5, colorScheme.primary);
    _dot(1.2 + (width - 2.4) * 0.62, y + 3.25, 0.75, colorScheme.primary);
    _pill(1.2, y + 5.2, 6.2, 0.75, line);
    _pill(width - 3.8, y + 5.0, 2.6, 1.15, colorScheme.primaryContainer);
  }
}
