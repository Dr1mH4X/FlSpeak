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

/// 设置卡片：页面级圆角（35）加一根发丝描边，行之间共用一根发丝分隔线。
class SettingsCard extends StatelessWidget {
  const SettingsCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final border = hairlineSide(context);
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: Radii.xxxlAll,
        border: Border.fromBorderSide(border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A171D1B),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
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
    this.description,
    this.subtitleColor,
    this.trailing,
    this.onTap,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String title;

  /// 当前值，例如昵称、当前语言、当前设备名。
  final String? subtitle;

  /// 补充说明，例如「连接服务器时使用的昵称」。
  final String? description;

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

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: destructive ? scheme.error : secondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: texts.bodySmall?.copyWith(
                          color: subtitleColor ?? secondary,
                        ),
                      ),
                    ),
                  if (description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: texts.bodySmall?.copyWith(color: secondary),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 18, color: secondary),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }
    return InkWell(onTap: onTap, child: content);
  }
}
