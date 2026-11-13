import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart';

/// 可选中的文本设置卡片：未选中取提升表面底色，选中时填充主色并反白文字。
class SettingTextCard extends StatelessWidget {
  final String text;
  final bool? isSelected;
  final VoidCallback onPressed;

  const SettingTextCard(
    this.text, {
    super.key,
    this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = isSelected == true;
    final level = context.raisedSurfaceLevel;
    final fill = selected ? scheme.primary : surfaceColorFor(level, scheme);
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: fill,
        shape: AppShape.md,
        clipBehavior: Clip.antiAlias,
        child: AnimatedInkWell(
          onTap: onPressed,
          customBorder: AppShape.md,
          inkColor: foreground,
          child: SurfaceScope(
            level: level,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                text,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
