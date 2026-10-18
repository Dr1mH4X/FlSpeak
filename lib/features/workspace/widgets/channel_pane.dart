import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';
import '../workspace_state.dart';

/// 频道栏：服务器身份、统一的频道树、已连接语音、当前用户。
///
/// TeamSpeak 的频道不区分文字与语音——每个频道既是语音房间也承载文字消息，
/// 所以设计稿里的「文字频道 / 语音频道」两段在真实数据上没有依据，这里只保留
/// 一棵按 `parentId` 展开的频道树，成员跟随所属频道缩进显示。
class ChannelPanel extends ConsumerStatefulWidget {
  const ChannelPanel({this.onChannelSelected, super.key});

  /// 点频道后离开设置页，回到工作区。
  final VoidCallback? onChannelSelected;

  @override
  ConsumerState<ChannelPanel> createState() => _ChannelPanelState();
}

class _ChannelPanelState extends ConsumerState<ChannelPanel> {
  /// 记录被折叠的频道，新出现的频道默认展开。
  final _collapsed = <int>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final view = ref.watch(sessionViewProvider);
    final activeId = ref.watch(activeChannelIdProvider);
    final selfChannel = view.selfChannelId == null
        ? null
        : view.channelById(view.selfChannelId!);
    final String nickname =
        view.selfClient?.nickname ??
        ref.watch(preferencesProvider.select((prefs) => prefs.nickname));

    void toggle(ChannelView channel, bool expanded) {
      setState(() {
        if (expanded) {
          _collapsed.add(channel.id);
        } else {
          _collapsed.remove(channel.id);
        }
      });
    }

    void select(ChannelView channel) {
      ref
          .read(selectedChannelProvider.notifier)
          .select(channel.id, serverId: view.activeServerId);
      // 抽屉不属于路由栈：选中频道后先收起抽屉，再到外壳切回工作区。
      // 桌面没有打开中的抽屉，这一步是空操作。
      Scaffold.maybeOf(context)?.closeDrawer();
      widget.onChannelSelected?.call();
    }

    return Material(
      color: context.isDark
          ? scheme.surfaceContainerLow
          : scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, l10n, view),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(label: l10n.channelsSection),
                Expanded(
                  child: _buildTree(
                    context,
                    l10n,
                    view,
                    activeId,
                    toggle,
                    select,
                  ),
                ),
              ],
            ),
          ),
          if (selfChannel != null) _ConnectedVoiceCard(channel: selfChannel),
          _UserFooter(
            nickname: nickname,
            connected: view.connected,
            muted: view.muted,
            deafened: view.deafened,
            onToggleMute: () =>
                ref.read(sessionViewProvider.notifier).setMuted(!view.muted),
            onToggleDeafen: () => ref
                .read(sessionViewProvider.notifier)
                .setDeafened(!view.deafened),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l10n,
    SessionView view,
  ) {
    final scheme = context.scheme;
    final controller = ref.read(sessionViewProvider.notifier);

    return SizedBox(
      height: Sizes.header,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                view.activeServer?.label ?? l10n.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (view.connected || view.connecting)
              PopupMenuButton<_PanelAction>(
                tooltip: l10n.commonMore,
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                onSelected: (action) {
                  switch (action) {
                    case _PanelAction.refresh:
                      controller.refresh();
                    case _PanelAction.disconnect:
                      controller.disconnect();
                  }
                },
                itemBuilder: (context) => [
                  if (view.connected)
                    PopupMenuItem(
                      value: _PanelAction.refresh,
                      child: _MenuRow(
                        icon: Icons.refresh_rounded,
                        label: l10n.workspaceRefresh,
                      ),
                    ),
                  PopupMenuItem(
                    value: _PanelAction.disconnect,
                    child: _MenuRow(
                      icon: Icons.logout_rounded,
                      label: l10n.serverDisconnect,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTree(
    BuildContext context,
    AppLocalizations l10n,
    SessionView view,
    int? activeId,
    void Function(ChannelView channel, bool expanded) onToggle,
    void Function(ChannelView channel) onSelect,
  ) {
    final rows = _flatten(view);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Text(
          view.connected ? l10n.workspaceNoChannels : l10n.channelsEmpty,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row) {
          _ChannelRow(:final channel, :final depth, :final expanded) =>
            _ChannelTile(
              channel: channel,
              depth: depth,
              selected: channel.id == activeId,
              memberCount: view.clientsIn(channel.id).length,
              expanded: expanded,
              hasContent:
                  view.clientsIn(channel.id).isNotEmpty ||
                  view.childrenOf(channel.id).isNotEmpty,
              onToggle: () => onToggle(channel, expanded),
              onSelect: () => onSelect(channel),
            ),
          _MemberRow(:final client, :final depth) => _MemberTile(
            client: client,
            depth: depth,
            speaking: view.speaking.contains(client.id),
          ),
        };
      },
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

enum _PanelAction { refresh, disconnect }

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
    required this.selected,
    required this.memberCount,
    required this.expanded,
    required this.hasContent,
    required this.onToggle,
    required this.onSelect,
  });

  final ChannelView channel;
  final int depth;
  final bool selected;
  final int memberCount;
  final bool expanded;
  final bool hasContent;
  final VoidCallback onToggle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final name = channel.name.isEmpty ? '#${channel.id}' : channel.name;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: Radii.pillAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSelect,
            borderRadius: Radii.pillAll,
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: hasContent
                          ? Tooltip(
                              message: expanded
                                  ? l10n.channelCollapse
                                  : l10n.channelExpand,
                              child: InkWell(
                                onTap: onToggle,
                                customBorder: const CircleBorder(),
                                child: SizedBox(
                                  width: 32,
                                  height: 40,
                                  child: Icon(
                                    expanded
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.keyboard_arrow_right_rounded,
                                    size: 20,
                                    color: foreground,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                    Icon(Icons.tag_rounded, size: 20, color: foreground),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                          fontWeight: selected
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (memberCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '$memberCount',
                          style: context.texts.labelSmall?.copyWith(
                            color: foreground,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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
    required this.speaking,
  });

  final ClientView client;
  final int depth;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Padding(
      padding: EdgeInsets.only(left: 40.0 + (depth - 1) * 16.0, right: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            MemberAvatar(
              label: initialsOf(client.nickname),
              size: AvatarSize.small,
              speaking: speaking,
              onSurface: true,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                client.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  fontSize: 13,
                  color: speaking ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已连接语音卡：只陈述状态，不放「断开语音」——TeamSpeak 没有「离开语音但不离开
/// 频道」这个概念，真正的断开入口在频道栏菜单里。
class _ConnectedVoiceCard extends StatelessWidget {
  const _ConnectedVoiceCard({required this.channel});

  final ChannelView channel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final name = channel.name.isEmpty ? '#${channel.id}' : channel.name;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: Radii.xxlAll,
      ),
      child: Row(
        children: [
          const _LiveDot(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.voiceConnected,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    fontSize: 12,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 语音连接指示点：用定时器驱动一次「扩散 + 淡出」的隐式动画。
///
/// 没有用 `AnimationController.repeat`：无限循环的 ticker 会让测试里的
/// `pumpAndSettle` 永远等不到静止帧。定时器周期比动画时长长，动画一停就能
/// 判定为静止；关闭系统动画时只保留静态圆点。
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> {
  static const _period = Duration(milliseconds: 1400);
  static const _pulseDuration = Duration(milliseconds: 1100);

  Timer? _timer;
  bool _pulse = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    _pulse = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _timer = Timer.periodic(_period, _onTick);
  }

  void _onTick(Timer timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }
    setState(() => _pulse = !_pulse);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.scheme.primary;
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: _pulseDuration,
            curve: Curves.easeOut,
            width: _pulse ? 16 : 8,
            height: _pulse ? 16 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: _pulse ? 0 : 0.45),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: primary),
          ),
        ],
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.nickname,
    required this.connected,
    required this.muted,
    required this.deafened,
    required this.onToggleMute,
    required this.onToggleDeafen,
  });

  final String nickname;
  final bool connected;
  final bool muted;
  final bool deafened;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleDeafen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClientAvatar(nickname: nickname, size: AvatarSize.medium),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    connected
                        ? l10n.sessionConnected
                        : l10n.sessionDisconnected,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _IconToggle(
              tooltip: muted ? l10n.voiceUnmute : l10n.voiceMute,
              icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              active: muted,
              onTap: onToggleMute,
            ),
            _IconToggle(
              tooltip: deafened ? l10n.voiceUndeafen : l10n.voiceDeafen,
              icon: deafened
                  ? Icons.headset_off_rounded
                  : Icons.headphones_rounded,
              active: deafened,
              onTap: onToggleDeafen,
            ),
          ],
        ),
      ),
    );
  }
}

/// 静音/闭麦开关：视觉圆点 36，落点撑到 44（触摸目标下限）。
class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: active,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: Sizes.touch,
            height: Sizes.touch,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? scheme.error.withValues(alpha: 0.12)
                      : Colors.transparent,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: active ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
  );
}
