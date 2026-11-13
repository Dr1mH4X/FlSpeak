import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart';

/// 弹层里的一行选项，用于音频设备选择器列表。
class SettingsOptionRow extends StatelessWidget {
  const SettingsOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return AnimatedInkWell(
      onTap: onTap,
      customBorder: AppShape.md,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(color: scheme.onSurface),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 12),
                Icon(
                  Icons.check_rounded,
                  size: IconSizes.toolbar,
                  color: scheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
