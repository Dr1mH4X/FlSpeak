import 'package:flutter/material.dart' hide Checkbox, Switch;

import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart';
import 'list_item.dart';

export '../../../widgets/prism.dart'
    show
        DecorationListItem,
        ItemPosition,
        ItemPositionProvider,
        ListFooter,
        ListHeader,
        ListRow,
        ListRowAlignment,
        generateGroup;
export 'list_item.dart';

Widget generateSection({
  String? title,
  required Iterable<Widget> items,
  List<Widget> actions = const [],
  String? footer,
}) {
  final list = items.toList(growable: false);
  if (list.isEmpty) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || actions.isNotEmpty)
          ListHeader(
            title: title ?? '',
            trailing: actions.isNotEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: actions,
                  )
                : null,
          ),
        generateGroup(list),
        if (footer != null) ListFooter(text: footer),
      ],
    ),
  );
}

/// 标准设置行组件，基于 [DecorationListItem] 对齐行高、裸图标与 Ink+Hover 交互。
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.icon,
    this.leading,
    this.trailing,
    this.badge,
    this.onTap,
    this.destructive = false,
    this.selected = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final Widget? badge;
  final VoidCallback? onTap;
  final bool destructive;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = destructive
        ? scheme.error
        : (selected ? scheme.primary : scheme.onSurface);

    final Widget? leadingWidget =
        leading ??
        (icon != null
            ? Icon(
                icon,
                size: IconSizes.standard,
                color: destructive
                    ? scheme.error
                    : (selected ? scheme.primary : scheme.onSurfaceVariant),
              )
            : null);

    final Widget? resolvedTrailing =
        trailing ??
        (onTap != null
            ? Icon(
                Icons.chevron_right_rounded,
                size: IconSizes.medium,
                color: scheme.onSurfaceVariant,
              )
            : null);

    final bool hasCompactTrailing = trailing is Switch || trailing is Checkbox;

    return DecorationListItem(
      leading: leadingWidget,
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: foreground),
            ),
          ),
          if (badge != null) ...[const SizedBox(width: 8), badge!],
        ],
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: subtitleColor ?? scheme.onSurfaceVariant),
            ),
      trailing: resolvedTrailing,
      contentPadding: hasCompactTrailing
          ? const EdgeInsets.only(left: 16, right: 8)
          : const EdgeInsets.symmetric(horizontal: 16),
      isSelected: selected,
      onPressed: onTap,
    );
  }
}

/// 在列表行右侧用当前值按钮呼出弹出菜单的选择设置项，复用 [ListItem.options]。
class SettingsOptionsTile<T> extends StatelessWidget {
  const SettingsOptionsTile({
    required this.title,
    this.icon,
    this.leading,
    required this.options,
    required this.value,
    required this.textBuilder,
    required this.onChanged,
    super.key,
  });

  final String title;
  final IconData? icon;
  final Widget? leading;
  final List<T> options;
  final T value;
  final String Function(T value) textBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedLeading =
        leading ??
        (icon != null
            ? Icon(
                icon,
                size: IconSizes.standard,
                color: scheme.onSurfaceVariant,
              )
            : null);

    return ListItem<T>.options(
      leading: resolvedLeading,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      options: options,
      value: value,
      textBuilder: textBuilder,
      onChanged: onChanged,
    );
  }
}
