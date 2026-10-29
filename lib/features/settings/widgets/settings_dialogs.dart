import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/press_feedback.dart';

/// 单选选项对话框：点一条就关闭并返回该值；用户直接关掉对话框时返回 null。
///
/// 语言、外观这类枚举选项都走这里，避免每处都写一遍同样的弹层结构。
Future<T?> showSettingsOptions<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T current,
  required String Function(BuildContext context, T value) labelBuilder,
}) => showAppModal<T>(
  context,
  title: title,
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final option in options)
        SettingsOptionRow(
          label: labelBuilder(context, option),
          selected: option == current,
          onTap: () => Navigator.of(context).pop(option),
        ),
    ],
  ),
);

/// 弹层里的一行选项。音频设备列表也复用这套行样式。
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
      // 同心圆角：面板 35 − 横向内边距 20 ≈ 16（Radii.large），取整到现有档位。
      borderRadius: Radii.largeAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyLarge?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 12),
                Icon(Icons.check_rounded, size: 20, color: scheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
