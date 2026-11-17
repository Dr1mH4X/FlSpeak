import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'prism.dart';

@immutable
class GlyphSegment<T> {
  const GlyphSegment({
    required this.value,
    required this.glyph,
    required this.label,
  });

  final T value;
  final Glyph glyph;
  final String label;
}

/// 图标分段控件：沿用 [SegmentedControl] 的胶囊底与滑动指示器，
/// 分段内容改为 `prism_ui` 的 [AnimatedGlyph]，选中时填充并轻微弹起。
class GlyphSegmentedControl<T> extends StatelessWidget {
  const GlyphSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<GlyphSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  static const _height = 44.0;
  static const _inset = 4.0;
  static const _indicatorDuration = Duration(milliseconds: 250);
  static const _glyphDuration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final count = segments.length;
    final index = segments.indexWhere((segment) => segment.value == value);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      height: _height,
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.full,
      ),
      child: Stack(
        children: [
          if (index >= 0)
            AnimatedAlign(
              duration: reduceMotion ? Duration.zero : _indicatorDuration,
              curve: Curves.easeOutCubic,
              alignment: AlignmentDirectional(
                count == 1 ? 0 : index * 2 / (count - 1) - 1,
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colorScheme.primary,
                    shape: AppShape.full,
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final segment in segments)
                Expanded(
                  child: PressSurface(
                    fill: const Color(0x00000000),
                    shape: AppShape.full,
                    look: segment.value == value
                        ? PressLook.none
                        : PressLook.ink,
                    ringStandsOff: segment.value == value,
                    selected: segment.value == value,
                    childFills: true,
                    onPressed: segment.value == value
                        ? () {}
                        : () => onChanged(segment.value),
                    child: Center(
                      child: Semantics(
                        label: segment.label,
                        child: IconTheme(
                          data: IconThemeData(
                            size: IconSizes.medium,
                            color: segment.value == value
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                          ),
                          child: AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : _glyphDuration,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.85,
                                      end: 1,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: reduceMotion
                                ? GlyphIcon(segment.glyph)
                                : AnimatedGlyph(
                                    key: ValueKey(segment.glyph),
                                    glyph: segment.glyph,
                                    filled: segment.value == value,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
