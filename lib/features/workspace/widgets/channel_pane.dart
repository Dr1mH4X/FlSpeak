import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';

/// 频道栏：频道树 + 每个频道下的在线成员。
///
/// 展开状态记录的是「被折叠」的频道，所以新出现的频道默认是展开的。
class ChannelPane extends ConsumerStatefulWidget {
  const ChannelPane({super.key});

  @override
  ConsumerState<ChannelPane> createState() => _ChannelPaneState();
}

class _ChannelPaneState extends ConsumerState<ChannelPane> {
  final _collapsed = <int>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final rows = _flatten(view);

    return PaneShell(
      title: l10n.channelsTitle,
      trailing: Text(
        '${view.channels.length}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontFeatures: tabularFigures,
        ),
      ),
      child: rows.isEmpty
          ? EmptyState(icon: Icons.forum_outlined, body: l10n.channelsEmpty)
          : ListView.builder(
              padding: const EdgeInsets.only(top: 6, bottom: 16),
              itemCount: rows.length,
              itemBuilder: (context, index) => switch (rows[index]) {
                _ChannelRow(:final channel, :final depth, :final expanded) =>
                  _ChannelTile(
                    channel: channel,
                    depth: depth,
                    expanded: expanded,
                    hasChildren: view.totalIn(channel.id) > 0,
                    current: view.selfChannelId == channel.id,
                    members: view.clientsIn(channel.id).length,
                    busy: view.busy,
                    onToggle: () => setState(
                      () => expanded
                          ? _collapsed.add(channel.id)
                          : _collapsed.remove(channel.id),
                    ),
                    onJoin: () => ref
                        .read(sessionViewProvider.notifier)
                        .joinChannel(channel.id),
                  ),
                _MemberRow(:final client, :final depth) => _MemberTile(
                  client: client,
                  depth: depth,
                  isSelf: client.id == view.selfClientId,
                  selfLabel: l10n.channelCurrent,
                ),
              },
            ),
    );
  }

  List<_TreeRow> _flatten(SessionView view) {
    final rows = <_TreeRow>[];

    void walk(ChannelView channel, int depth) {
      final children = view.childrenOf(channel.id);
      final members = view.clientsIn(channel.id);
      final expanded =
          !_collapsed.contains(channel.id) &&
          (members.isNotEmpty || children.isNotEmpty);
      rows.add(_ChannelRow(channel: channel, depth: depth, expanded: expanded));
      if (!expanded) {
        return;
      }
      for (final member in members) {
        rows.add(_MemberRow(client: member, depth: depth + 1));
      }
      for (final child in children) {
        walk(child, depth + 1);
      }
    }

    final roots = view.rootChannels()..sort((a, b) => a.id.compareTo(b.id));
    for (final root in roots) {
      walk(root, 0);
    }
    return rows;
  }
}

sealed class _TreeRow {
  const _TreeRow();
}

class _ChannelRow extends _TreeRow {
  const _ChannelRow({
    required this.channel,
    required this.depth,
    required this.expanded,
  });

  final ChannelView channel;
  final int depth;
  final bool expanded;
}

class _MemberRow extends _TreeRow {
  const _MemberRow({required this.client, required this.depth});

  final ClientView client;
  final int depth;
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.depth,
    required this.expanded,
    required this.hasChildren,
    required this.current,
    required this.members,
    required this.busy,
    required this.onToggle,
    required this.onJoin,
  });

  final ChannelView channel;
  final int depth;
  final bool expanded;
  final bool hasChildren;
  final bool current;
  final int members;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = channel.name.isEmpty ? '#${channel.id}' : channel.name;

    return Padding(
      padding: EdgeInsets.only(left: 8 + depth * 14, right: 8),
      child: Tooltip(
        message: channel.description.isEmpty
            ? l10n.channelJoin
            : '${l10n.channelJoin} · ${channel.description}',
        child: InkWell(
          // 整行就是「进入这个频道」的落点，所以行本身必须够高。
          onTap: current || busy ? null : onJoin,
          borderRadius: Radii.smallAll,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: current ? scheme.surfaceContainerHigh : null,
              borderRadius: Radii.smallAll,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  // 展开/收起是行内的次级落点：行自己已经提供了大落点，
                  // 所以这里只保证宽度够按，不抢行的主操作。
                  child: hasChildren
                      ? IconButton(
                          tooltip: expanded
                              ? l10n.channelCollapse
                              : l10n.channelExpand,
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                          onPressed: onToggle,
                          icon: Icon(
                            expanded
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_right_rounded,
                          ),
                        )
                      : null,
                ),
                Icon(
                  current ? Icons.graphic_eq_rounded : Icons.forum_outlined,
                  size: 17,
                  color: current
                      ? context.status.live
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                      color: current
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (members > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '$members',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                if (current)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      l10n.channelCurrent,
                      style: text.labelSmall?.copyWith(
                        color: context.status.live,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.client,
    required this.depth,
    required this.isSelf,
    required this.selfLabel,
  });

  final ClientView client;
  final int depth;
  final bool isSelf;
  final String selfLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(left: 8 + depth * 14, right: 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.only(left: 32, right: 12, top: 4, bottom: 4),
        child: Row(
          children: [
            ClientAvatar(
              nickname: client.nickname,
              size: 24,
              highlighted: isSelf,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                client.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  color: isSelf ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (isSelf)
              Text(
                selfLabel,
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
