import 'package:flutter/material.dart';

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
                  child: Surface(
                    color: Colors.transparent,
                    shape: AppShape.lg,
                    clipBehavior: Clip.antiAlias,
                    child: FocusRing(
                      shape: AppShape.lg,
                      child: PressSurface(
                        fill: Colors.transparent,
                        shape: AppShape.lg,
                        look: PressLook.tint,
                        onPressed: () => onChanged(mode),
                        selected: value == mode,
                        childFills: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: ShapeDecoration(
                                shape: RoundedSuperellipseBorder(
                                  borderRadius: AppRadius.lg,
                                  side: BorderSide(
                                    color: value == mode
                                        ? scheme.primary
                                        : dividerColorOf(context),
                                    width: value == mode ? 2 : 1,
                                  ),
                                ),
                              ),
                              child: ClipRSuperellipse(
                                borderRadius: AppRadius.md,
                                child: SizedBox(
                                  height: 88,
                                  child: mode == AppThemePreference.system
                                      ? Row(
                                          children: [
                                            Expanded(
                                              child: _preview(Brightness.dark),
                                            ),
                                            Expanded(
                                              child: _preview(Brightness.light),
                                            ),
                                          ],
                                        )
                                      : _preview(
                                          mode == AppThemePreference.dark
                                              ? Brightness.dark
                                              : Brightness.light,
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
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
                child: const SizedBox.expand(),
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
                    Container(height: 4, color: scheme.outlineVariant),
                    const SizedBox(height: 5),
                    Container(height: 4, color: scheme.outlineVariant),
                    const Spacer(),
                    Container(
                      height: 12,
                      decoration: ShapeDecoration(
                        color: cardColor,
                        shape: AppShape.sm,
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
