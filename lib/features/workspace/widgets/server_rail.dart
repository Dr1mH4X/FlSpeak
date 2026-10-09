import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../router.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';

/// 服务器栏是否展开。窄屏强制收成图标栏，不看这个状态。
final railExpandedProvider = NotifierProvider<RailController, bool>(
  RailController.new,
);

class RailController extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

/// 工作区左侧的服务器栏：已登记的服务器 + 添加 +（底部）设置。
class ServerRail extends ConsumerWidget {
  const ServerRail({
    required this.location,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  static const expandedWidth = 236.0;
  static const collapsedWidth = 72.0;

  final String location;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final view = ref.watch(sessionViewProvider);

    return Container(
      width: expanded ? expandedWidth : collapsedWidth,
      color: scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RailHeader(expanded: expanded, onToggle: onToggle),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                if (expanded)
                  SectionHeader(label: l10n.railServers)
                else
                  const SizedBox(height: 8),
                for (final server in view.servers)
                  _ServerRow(
                    server: server,
                    online: server.id == view.activeServerId,
                    selected:
                        server.id == view.activeServerId &&
                        location == AppRoutes.workspace,
                    expanded: expanded,
                    onTap: () => context.go(
                      server.id == view.activeServerId
                          ? AppRoutes.workspace
                          : '${AppRoutes.connect}?server=${Uri.encodeComponent(server.id)}',
                    ),
                  ),
                _ActionRow(
                  expanded: expanded,
                  icon: Icons.add_rounded,
                  label: l10n.serverAdd,
                  onTap: () => context.go(AppRoutes.connect),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          _ActionRow(
            expanded: expanded,
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: l10n.settingsTitle,
            selected: location == AppRoutes.settings,
            onTap: () => context.go(AppRoutes.settings),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RailHeader extends StatelessWidget {
  const _RailHeader({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 18,
              color: scheme.onPrimary,
            ),
          ),
          if (expanded) ...[
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.appName, style: text.titleMedium)),
          ],
          if (expanded)
            IconButton(
              tooltip: l10n.railCollapse,
              onPressed: onToggle,
              iconSize: 18,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
        ],
      ),
    );
  }
}

class _ServerRow extends StatefulWidget {
  const _ServerRow({
    required this.server,
    required this.online,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final ServerProfileView server;
  final bool online;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends State<_ServerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final server = widget.server;
    final expanded = widget.expanded;

    final tile = ServerMonogram(
      id: server.id,
      label: server.label,
      host: server.host,
      size: 34,
      online: widget.online,
      dimmed: !widget.online && !widget.selected,
    );

    final row = InkWell(
      onTap: widget.onTap,
      borderRadius: Radii.smallAll,
      child: Container(
        // 最小高度 48 保证可点面积；高度随字号增长，不写死以免大字号被裁掉。
        constraints: const BoxConstraints(minHeight: 48),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: widget.selected || _hovered
              ? scheme.surfaceContainerHigh
              : Colors.transparent,
          borderRadius: Radii.smallAll,
        ),
        child: Row(
          children: [
            SizedBox(width: 34, child: Center(child: tile)),
            if (expanded) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      server.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    Text(
                      widget.online
                          ? l10n.sessionConnected
                          : '${server.host}:${server.port}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: widget.online
                            ? context.status.live
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        children: [
          if (widget.selected)
            Positioned(
              left: 0,
              top: 13,
              bottom: 13,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(2),
                  ),
                ),
              ),
            ),
          expanded
              ? row
              : Tooltip(
                  message: widget.online
                      ? '${server.label} · ${l10n.sessionConnected}'
                      : '${server.label}\n${server.host}:${server.port}',
                  child: row,
                ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.expanded,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selectedIcon,
    this.selected = false,
  });

  final bool expanded;
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final row = InkWell(
      onTap: widget.onTap,
      borderRadius: Radii.smallAll,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: widget.selected || _hovered
              ? scheme.surfaceContainerHigh
              : Colors.transparent,
          borderRadius: Radii.smallAll,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Center(
                child: Icon(
                  widget.selected
                      ? (widget.selectedIcon ?? widget.icon)
                      : widget.icon,
                  size: 20,
                  color: widget.selected
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (widget.expanded) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: widget.selected ? scheme.primary : scheme.onSurface,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.expanded ? row : Tooltip(message: widget.label, child: row),
    );
  }
}
