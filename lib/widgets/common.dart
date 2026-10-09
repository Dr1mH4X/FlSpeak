import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 提示条：策略拒绝与协议失败都走这里，就近显示而不是弹窗打断。
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    required this.message,
    required this.dismissTooltip,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final String dismissTooltip;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: Radii.smallAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.report_gmailerrorred_rounded,
            size: 20,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            tooltip: dismissTooltip,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: scheme.onErrorContainer,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// 分栏标题。句子大小写，靠字重和颜色分层，不靠全大写。
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.label, this.trailing, super.key});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 空状态是行动邀请：说清楚现在缺什么、下一步点哪里。
///
/// 标题可选——分栏自己已经有标题时不必再写一遍。
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.body,
    this.title,
    this.action,
    this.maxWidth = 320,
    super.key,
  });

  final IconData icon;
  final String? title;
  final String body;
  final Widget? action;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: scheme.onSurfaceVariant),
              const SizedBox(height: 14),
              if (title != null) ...[
                Text(title!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
              ],
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 分栏外壳：统一标题栏高度与分隔线，让左右两栏的顶边对齐。
class PaneShell extends StatelessWidget {
  const PaneShell({
    required this.title,
    required this.child,
    this.trailing,
    this.background,
    super.key,
  });

  static const headerHeight = 52.0;

  final String title;
  final Widget child;
  final Widget? trailing;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: background ?? scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: headerHeight,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: trailing!,
                  )
                else
                  const SizedBox(width: 16),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(child: child),
        ],
      ),
    );
  }
}
