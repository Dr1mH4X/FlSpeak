import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionLabel(
        label: title,
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      ),
      SettingsCard(children: children),
    ],
  );
}

/// 设置卡片：复用 [HairlineCard] 卡片家族，行之间共用一根发丝分隔线。
class SettingsCard extends StatelessWidget {
  const SettingsCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final border = hairlineSide(context);
    return HairlineCard(
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0)
              Divider(height: 1, thickness: 1, color: border.color),
            children[index],
          ],
        ],
      ),
    );
  }
}

/// 设置行：整行可点，左侧图标、标题 + 副标题、右侧尾部控件或箭头。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.onTap,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String title;

  /// 当前值，例如昵称、当前语言、当前设备名。设置行不承载解释文案。
  final String? subtitle;

  /// 副标题上色；连接状态用语义色，其余保持中性。
  final Color? subtitleColor;

  /// 右侧控件。给了 Switch / 图标按钮就不再画箭头。
  final Widget? trailing;

  final VoidCallback? onTap;

  /// 破坏性操作：标题与图标用 error 色。
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final texts = context.texts;
    final foreground = destructive ? scheme.error : scheme.onSurface;
    final secondary = scheme.onSurfaceVariant;

    // M3 list item：ink/hover/semantics 交给 ListTile，样式仍由主题与
    // 这里的显式样式锁住，保持卡片里的行高节奏。
    return ListTile(
      leading: Icon(
        icon,
        size: 20,
        color: destructive ? scheme.error : secondary,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: texts.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: texts.bodySmall?.copyWith(
                color: subtitleColor ?? secondary,
              ),
            ),
      trailing:
          trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right_rounded, size: 18, color: secondary)
              : null),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
