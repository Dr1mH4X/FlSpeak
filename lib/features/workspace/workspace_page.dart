import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/monogram.dart';
import 'widgets/channel_pane.dart';
import 'widgets/chat_pane.dart';

/// 工作区：标题栏（服务器身份 + 连接动作）+ 频道栏 + 聊天栏。
///
/// 宽屏三栏并排；窄屏收成一栏，用标题栏里的分段控件在频道与聊天之间切换。
class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({super.key});

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

enum _Pane { channels, chat }

class _WorkspacePageState extends ConsumerState<WorkspacePage> {
  _Pane _pane = _Pane.channels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);

    if (!view.connected) {
      return EmptyState(
        icon: Icons.power_off_rounded,
        title: l10n.workspaceNotConnectedTitle,
        body: l10n.workspaceNotConnectedBody,
        maxWidth: 360,
        action: FilledButton.icon(
          onPressed: () => context.go(AppRoutes.connect),
          icon: const Icon(Icons.link_rounded, size: 18),
          label: Text(l10n.connectTitle),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < Breakpoints.compact;
        final wide = constraints.maxWidth >= Breakpoints.wide;
        final channelWidth = wide ? 288.0 : 260.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkspaceHeader(
              compact: compact,
              pane: _pane,
              onPaneChanged: (pane) => setState(() => _pane = pane),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: compact
                  ? (_pane == _Pane.channels
                        ? const ChannelPane()
                        : const ChatPane())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: channelWidth,
                          child: const ChannelPane(),
                        ),
                        VerticalDivider(
                          width: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const Expanded(child: ChatPane()),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceHeader extends ConsumerWidget {
  const _WorkspaceHeader({
    required this.compact,
    required this.pane,
    required this.onPaneChanged,
  });

  final bool compact;
  final _Pane pane;
  final ValueChanged<_Pane> onPaneChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final controller = ref.read(sessionViewProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final server = view.activeServer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          if (server != null) ...[
            ServerMonogram(
              id: server.id,
              label: server.label,
              host: server.host,
              size: 36,
              online: true,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  server?.label ?? l10n.sessionConnected,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    StatusDot(
                      color: context.status.live,
                      ringColor: scheme.surface,
                      size: 8,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${server?.host ?? ''}:${server?.port ?? ''} · '
                        '${l10n.workspaceOnlineCount(view.clients.length)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (compact) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SegmentedButton<_Pane>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _Pane.channels,
                    label: Text(l10n.channelsTitle),
                  ),
                  ButtonSegment(value: _Pane.chat, label: Text(l10n.chatTitle)),
                ],
                selected: {pane},
                onSelectionChanged: (selection) =>
                    onPaneChanged(selection.first),
              ),
            ),
            PopupMenuButton<_HeaderAction>(
              tooltip: l10n.commonMore,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) => switch (action) {
                _HeaderAction.refresh => controller.refresh(),
                _HeaderAction.disconnect => controller.disconnect(),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _HeaderAction.refresh,
                  child: Row(
                    children: [
                      const Icon(Icons.refresh_rounded, size: 18),
                      const SizedBox(width: 10),
                      Text(l10n.workspaceRefresh),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: _HeaderAction.disconnect,
                  child: Row(
                    children: [
                      const Icon(Icons.logout_rounded, size: 18),
                      const SizedBox(width: 10),
                      Text(l10n.serverDisconnect),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            IconButton(
              tooltip: l10n.workspaceRefresh,
              onPressed: () => controller.refresh(),
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: l10n.serverDisconnect,
              onPressed: () => controller.disconnect(),
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

enum _HeaderAction { refresh, disconnect }
