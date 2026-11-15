import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        Card,
        Divider,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;

import '../../../core/preferences.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart';

class AppearancePicker extends StatelessWidget {
  const AppearancePicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final AppThemePreference value;
  final ValueChanged<AppThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final cardColor = surfaceColorFor(SurfaceLevel.card, scheme);
    final previewBorderRadius = AppRadius.all(Radii.inner(AppCorner.lg, 4));
    final previewBorder = ShapeDecoration(
      shape: RoundedSuperellipseBorder(
        borderRadius: previewBorderRadius,
        side: BorderSide(color: dividerColorOf(context)),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.appearancePreview,
          style: AppTextStyle.headline.of(context, emphasized: true),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final mode in [
              AppThemePreference.dark,
              AppThemePreference.light,
              AppThemePreference.system,
            ]) ...[
              if (mode != AppThemePreference.dark) const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  selected: value == mode,
                  button: true,
                  child: PressSurface(
                    fill: cardColor,
                    shape: AppShape.lg,
                    side: value == mode
                        ? BorderSide(color: scheme.primary, width: 2)
                        : BorderSide.none,
                    look: PressLook.tint,
                    onPressed: () => onChanged(mode),
                    selected: value == mode,
                    childFills: true,
                    clipsChild: true,
                    child: SurfaceScope(
                      level: SurfaceLevel.card,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DecoratedBox(
                              position: DecorationPosition.foreground,
                              decoration: previewBorder,
                              child: ClipRSuperellipse(
                                borderRadius: previewBorderRadius,
                                child: SizedBox(
                                  height: 88,
                                  child: mode == AppThemePreference.system
                                      ? _SplitPreview(
                                          light: _preview(Brightness.light),
                                          dark: _preview(Brightness.dark),
                                        )
                                      : _preview(
                                          mode == AppThemePreference.dark
                                              ? Brightness.dark
                                              : Brightness.light,
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              switch (mode) {
                                AppThemePreference.dark =>
                                  l10n.settingsThemeDark,
                                AppThemePreference.light =>
                                  l10n.settingsThemeLight,
                                AppThemePreference.system =>
                                  l10n.settingsThemeSystem,
                              },
                              textAlign: TextAlign.center,
                              style: AppTextStyle.footnote
                                  .of(context, emphasized: value == mode)
                                  .copyWith(
                                    color: value == mode
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _preview(Brightness brightness) {
    final scheme = buildAppTheme(brightness).colorScheme;
    final pageColor = surfaceColorFor(SurfaceLevel.page, scheme);
    final cardColor = surfaceColorFor(SurfaceLevel.card, scheme);
    final lineStrong = scheme.onSurface.withValues(alpha: 0.72);
    final lineSoft = scheme.onSurfaceVariant.withValues(alpha: 0.4);
    final lineFaint = scheme.onSurfaceVariant.withValues(alpha: 0.16);
    return ExcludeSemantics(
      child: ColoredBox(
        color: pageColor,
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: ColoredBox(
                color: scheme.surfaceContainerLowest,
                child: const SizedBox.expand(),
              ),
            ),
            Expanded(
              flex: 2,
              child: ColoredBox(
                color: scheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 4,
                        decoration: ShapeDecoration(
                          color: lineSoft,
                          shape: AppShape.full,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 4,
                        decoration: ShapeDecoration(
                          color: lineFaint,
                          shape: AppShape.full,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 7,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 6,
                      decoration: ShapeDecoration(
                        color: scheme.primary,
                        shape: AppShape.full,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 4,
                      decoration: ShapeDecoration(
                        color: lineStrong,
                        shape: AppShape.full,
                      ),
                    ),
                    const SizedBox(height: 5),
                    FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: 0.72,
                      child: Container(
                        height: 4,
                        decoration: ShapeDecoration(
                          color: lineSoft,
                          shape: AppShape.full,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 12,
                      decoration: ShapeDecoration(
                        color: cardColor,
                        shape: AppShape.sm.copyWith(
                          side: BorderSide(
                            color: scheme.onSurface.withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitPreview extends StatelessWidget {
  const _SplitPreview({required this.light, required this.dark});

  final Widget light;
  final Widget dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        light,
        ClipPath(clipper: _DiagonalClipper(), child: dark),
      ],
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.3, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_DiagonalClipper oldClipper) => false;
}
