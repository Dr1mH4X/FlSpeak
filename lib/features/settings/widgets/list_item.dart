import 'package:flutter/material.dart' hide Checkbox, PopupMenuItem, Switch;

import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart';

sealed class _ListItemAction {
  const _ListItemAction();
}

final class _DefaultAction extends _ListItemAction {
  const _DefaultAction();
}

final class _ToggleAction extends _ListItemAction {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleAction({required this.value, this.onChanged});
}

final class _CheckboxAction extends _ListItemAction {
  final bool value;
  final ValueChanged<bool?>? onChanged;

  const _CheckboxAction({required this.value, this.onChanged});
}

final class _OpenAction extends _ListItemAction {
  const _OpenAction();
}

final class _OptionsAction<T> extends _ListItemAction {
  final List<T> options;
  final T value;
  final String Function(T value) textBuilder;
  final ValueChanged<T> onChanged;

  const _OptionsAction({
    required this.options,
    required this.textBuilder,
    required this.value,
    required this.onChanged,
  });
}

class ListItem<T> extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final EdgeInsets padding;
  final ListRowAlignment alignment;
  final Widget? trailing;
  final _ListItemAction _action;
  final double? horizontalTitleGap;
  final double minVerticalPadding;
  final double? minTileHeight;
  final void Function()? onTap;
  final bool selected;
  final bool destructive;
  final bool invalid;

  const ListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.trailing,
    this.horizontalTitleGap,
    this.onTap,
    this.minTileHeight,
    this.minVerticalPadding = listRowVerticalPadding,
    this.alignment = ListRowAlignment.center,
    this.selected = false,
    this.destructive = false,
    this.invalid = false,
  }) : _action = const _DefaultAction();

  const ListItem.open({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.trailing,
    required this.onTap,
    this.horizontalTitleGap,
    this.minTileHeight,
    this.minVerticalPadding = listRowVerticalPadding,
    this.alignment = ListRowAlignment.center,
    this.selected = false,
    this.destructive = false,
    this.invalid = false,
  }) : _action = const _OpenAction();

  ListItem.options({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.padding = const EdgeInsets.only(left: 16, right: 8),
    required List<T> options,
    required T value,
    required String Function(T value) textBuilder,
    required ValueChanged<T> onChanged,
    this.horizontalTitleGap,
    this.minTileHeight,
    this.minVerticalPadding = listRowVerticalPadding,
    this.alignment = ListRowAlignment.center,
    this.selected = false,
    this.destructive = false,
    this.invalid = false,
  }) : _action = _OptionsAction<T>(
         options: options,
         value: value,
         textBuilder: textBuilder,
         onChanged: onChanged,
       ),
       trailing = null,
       onTap = null;

  ListItem.checkbox({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.padding = const EdgeInsets.only(left: 16, right: 8),
    bool value = false,
    ValueChanged<bool?>? onChanged,
    this.horizontalTitleGap,
    this.minTileHeight,
    this.minVerticalPadding = listRowVerticalPadding,
    this.alignment = ListRowAlignment.center,
    this.selected = false,
    this.destructive = false,
    this.invalid = false,
  }) : _action = _CheckboxAction(value: value, onChanged: onChanged),
       trailing = null,
       onTap = null;

  ListItem.toggle({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.padding = const EdgeInsets.only(left: 16, right: 8),
    required bool value,
    ValueChanged<bool>? onChanged,
    this.horizontalTitleGap,
    this.minTileHeight,
    this.minVerticalPadding = listRowVerticalPadding,
    this.alignment = ListRowAlignment.center,
    this.selected = false,
    this.destructive = false,
    this.invalid = false,
  }) : _action = _ToggleAction(value: value, onChanged: onChanged),
       trailing = null,
       onTap = null;

  Widget _buildRow(
    BuildContext context, {
    required ItemPosition? position,
    void Function()? onTap,
    Widget? trailing,
    Widget? leading,
  }) {
    if (position != null) {
      return ItemPositionProvider(
        position: position,
        child: DecorationListItem(
          leading: leading ?? this.leading,
          title: title,
          subtitle: subtitle,
          trailing: trailing ?? this.trailing,
          contentPadding: padding,
          horizontalTitleGap: horizontalTitleGap,
          minVerticalPadding: minVerticalPadding,
          isSelected: selected,
          invalid: invalid,
          onPressed: onTap,
        ),
      );
    }
    final row = ListRow(
      leading: leading ?? this.leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing ?? this.trailing,
      padding: padding,
      horizontalTitleGap: horizontalTitleGap,
      minVerticalPadding: minVerticalPadding,
      minHeight: minTileHeight ?? listRowMinHeight,
      alignment: alignment,
    );
    if (onTap == null) {
      return row;
    }
    return AnimatedInkWell(
      onTap: onTap,
      customBorder: AppShape.none,
      child: row,
    );
  }

  Widget get _pageTrailing =>
      trailing ??
      const Icon(Icons.chevron_right_rounded, size: IconSizes.medium);

  @override
  Widget build(BuildContext context) {
    final position = ItemPositionProvider.of(context)?.position;
    switch (_action) {
      case _OpenAction():
        return _buildRow(
          context,
          position: position,
          trailing: _pageTrailing,
          onTap: onTap,
        );
      case final _OptionsAction options:
        final optionsDelegate = options as _OptionsAction<T>;
        PopupOpen? openMenu;
        return _buildRow(
          context,
          position: position,
          onTap: () => openMenu?.call(),
          trailing: PopupAnchor(
            targetBuilder: (open) {
              openMenu = open;
              return OptionsValueButton(
                label: optionsDelegate.textBuilder(optionsDelegate.value),
                onPressed: open,
              );
            },
            popupBuilder: (_) => PopupMenu(
              items: [
                for (final option in optionsDelegate.options)
                  PopupMenuItem(
                    label: optionsDelegate.textBuilder(option),
                    checked: option == optionsDelegate.value,
                    onPressed: () => optionsDelegate.onChanged(option),
                  ),
              ],
            ),
          ),
        );
      case final _CheckboxAction checkboxDelegate:
        return _buildRow(
          context,
          position: position,
          onTap: checkboxDelegate.onChanged == null
              ? null
              : () => checkboxDelegate.onChanged!(!checkboxDelegate.value),
          trailing: Checkbox(
            value: checkboxDelegate.value,
            onChanged: checkboxDelegate.onChanged,
          ),
        );
      case final _ToggleAction toggleAction:
        return _buildRow(
          context,
          position: position,
          onTap: toggleAction.onChanged == null
              ? null
              : () => toggleAction.onChanged!(!toggleAction.value),
          trailing: Switch(
            value: toggleAction.value,
            onChanged: toggleAction.onChanged,
          ),
        );
      case _DefaultAction():
        return _buildRow(context, position: position, onTap: onTap);
    }
  }
}
