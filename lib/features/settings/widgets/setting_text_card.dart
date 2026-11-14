import 'package:flutter/material.dart' hide Card;

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

    return Card(
      isSelected: selected,
      fillsSelection: true,
      onPressed: onPressed,
      shape: AppShape.md,
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: AppTextStyle.subheadline
            .of(context)
            .copyWith(color: selected ? scheme.onPrimary : scheme.onSurface),
      ),
    );
  }
}
