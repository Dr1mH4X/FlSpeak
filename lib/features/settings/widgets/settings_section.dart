import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/popup.dart';

enum ItemPosition {
  start,
  middle,
  end,
  single;

  static ItemPosition get(int index, int length) {
    if (length <= 1) return ItemPosition.single;
    if (index == 0) return ItemPosition.start;
    if (index == length - 1) return ItemPosition.end;
    return ItemPosition.middle;
  }
}

class ItemPositionScope extends InheritedWidget {
  const ItemPositionScope({
    required this.position,
    required super.child,
    super.key,
  });

  final ItemPosition position;

  static ItemPositionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ItemPositionScope>();

  @override
  bool updateShouldNotify(ItemPositionScope oldWidget) =>
      position != oldWidget.position;
}

Widget generateGroup(Iterable<Widget> items) {
  final list = items.toList(growable: false);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < list.length; index++) ...[
        if (index > 0) const _ListRowDivider(),
        ItemPositionScope(
          position: ItemPosition.get(index, list.length),
          child: list[index],
        ),
      ],
    ],
  );
}

Widget generateSection({
  String? title,
  required Iterable<Widget> items,
  List<Widget> actions = const [],
  String? footer,
}) {
  final list = items.toList(growable: false);
  if (list.isEmpty) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                if (title != null)
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                if (actions.isNotEmpty) ...actions,
              ],
            ),
          ),
        Material(
          color: Colors.transparent,
          child: HairlineCard(clip: true, child: generateGroup(list)),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(footer, style: const TextStyle(fontSize: 12)),
          ),
      ],
    ),
  );
}

class _ListRowDivider extends StatelessWidget {
  const _ListRowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 64,
      endIndent: 16,
      color: hairlineSide(context).color,
    );
  }
}

/// 标准设置行组件，支持在卡片组内自动感知 [ItemPosition]。
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.icon,
    this.leading,
    this.trailing,
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
  final VoidCallback? onTap;
  final bool destructive;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final texts = context.texts;
    final foreground = destructive
        ? scheme.error
        : (selected ? scheme.primary : scheme.onSurface);
    final secondary = scheme.onSurfaceVariant;

    final Widget? leadingWidget =
        leading ??
        (icon != null
            ? Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: destructive
                      ? scheme.errorContainer
                      : (selected
                            ? scheme.primaryContainer
                            : scheme.secondaryContainer.withValues(alpha: 0.6)),
                  borderRadius: Radii.mediumAll,
                ),
                child: Icon(
                  icon,
                  size: IconSizes.toolbar,
                  color: destructive
                      ? scheme.onErrorContainer
                      : (selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSecondaryContainer),
                ),
              )
            : null);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leadingWidget != null) ...[
              leadingWidget,
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texts.titleMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: foreground,
                      fontSize: 15,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.bodySmall?.copyWith(
                        color: subtitleColor ?? secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: IconSizes.medium,
                color: secondary.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 带弹出菜单和取值切换动效的选项设置行（移植自 FlClash ListItem.options）。
class SettingsOptionsTile<T> extends StatefulWidget {
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
  State<SettingsOptionsTile<T>> createState() => _SettingsOptionsTileState<T>();
}

class _SettingsOptionsTileState<T> extends State<SettingsOptionsTile<T>> {
  PopupOpen? _openMenu;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      title: widget.title,
      icon: widget.icon,
      leading: widget.leading,
      onTap: () => _openMenu?.call(),
      trailing: CommonPopupBox(
        targetBuilder: (open) {
          _openMenu = open;
          return OptionsValueButton(
            label: widget.textBuilder(widget.value),
            onPressed: open,
          );
        },
        popupBuilder: (_) => CommonPopupMenu(
          items: [
            for (final option in widget.options)
              CommonPopupMenuItem(
                label: widget.textBuilder(option),
                checked: option == widget.value,
                onPressed: () => widget.onChanged(option),
              ),
          ],
        ),
      ),
    );
  }
}
