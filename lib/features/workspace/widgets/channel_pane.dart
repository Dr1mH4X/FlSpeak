import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart'
    hide
        ButtonStyle,
        Divider,
        FilledButton,
        IconButton,
        OutlinedButton,
        PopupMenuItem,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/channel_display.dart';
import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../core/stream_publisher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/channel_icon.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';
import '../../../widgets/prism.dart';
import '../../../widgets/window_header.dart';
import '../workspace_state.dart';
import 'channel_password_dialog.dart';
import 'client_actions.dart';
import 'member_avatar.dart';
import 'member_status_flags.dart';
import 'network_status.dart';
import 'screen_share_picker_dialog.dart';
import 'voice_activity_ribbon.dart';

/// 频道栏：服务器身份、统一的频道树、当前用户。
///
/// TeamSpeak 的频道不区分文字与语音——每个频道既是语音房间也承载文字消息，
/// 所以设计稿里的「文字频道 / 语音频道」两段在真实数据上没有依据，这里只保留
/// 一棵按 `parentId` 展开的频道树，成员跟随所属频道缩进显示。
class ChannelPanel extends StatelessWidget {
  const ChannelPanel({
    this.onChannelSelected,
    this.onDisconnect,
    this.showHeader = true,
    this.showUserFooter = true,
    this.bottomInset = 0,
    this.onCompactDirectChat,
    this.onCompactWatchStream,
    this.onShowChannelDetails,
    this.onShowChannelFiles,
    this.onShowMemberDetails,
    super.key,
  });

  /// 点频道后离开设置页，回到工作区；窄屏模式下触发推入二级频道页。
  final VoidCallback? onChannelSelected;
  final VoidCallback? onDisconnect;
  final bool showHeader;
  final bool showUserFooter;
  final double bottomInset;
  final VoidCallback? onCompactDirectChat;
  final ValueChanged<StreamView>? onCompactWatchStream;
  final ValueChanged<ChannelView>? onShowChannelDetails;
  final ValueChanged<ChannelView>? onShowChannelFiles;
  final ValueChanged<ClientView>? onShowMemberDetails;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    return Surface(
      color: showHeader ? scheme.surfaceContainerLow : context.pageColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) const _ChannelHeader(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(label: l10n.channelsSection),
                Expanded(
                  child: _ChannelTree(
                    onChannelSelected: onChannelSelected,
                    bottomInset: bottomInset,
                    onCompactDirectChat: onCompactDirectChat,
                    onCompactWatchStream: onCompactWatchStream,
                    onShowChannelDetails: onShowChannelDetails,
                    onShowChannelFiles: onShowChannelFiles,
                    onShowMemberDetails: onShowMemberDetails,
                  ),
                ),
              ],
            ),
          ),
          if (showUserFooter)
            SafeArea(
              top: false,
              left: false,
              right: false,
              child: _UserFooter(onDisconnect: onDisconnect),
            ),
        ],
      ),
    );
  }
}

class _ChannelHeader extends ConsumerWidget {
  const _ChannelHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final serverLabel = ref.watch(
      sessionViewProvider.select((view) => view.activeServer?.label),
    );
    return SafeArea(
      bottom: false,
      left: false,
      right: false,
      child: SizedBox(
        height: Sizes.header,
        child: WindowDragRegion(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(
              children: [
                Icon(
                  Icons.dns_outlined,
                  size: IconSizes.medium,
                  color: context.scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    serverLabel ?? l10n.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleMedium?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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

class _ChannelTree extends ConsumerStatefulWidget {
  const _ChannelTree({
    this.onChannelSelected,
    this.bottomInset = 0,
    this.onCompactDirectChat,
    this.onCompactWatchStream,
    this.onShowChannelDetails,
    this.onShowChannelFiles,
    this.onShowMemberDetails,
  });

  final VoidCallback? onChannelSelected;
  final double bottomInset;
  final VoidCallback? onCompactDirectChat;
  final ValueChanged<StreamView>? onCompactWatchStream;
  final ValueChanged<ChannelView>? onShowChannelDetails;
  final ValueChanged<ChannelView>? onShowChannelFiles;
  final ValueChanged<ClientView>? onShowMemberDetails;

  @override
  ConsumerState<_ChannelTree> createState() => _ChannelTreeState();
}

class _ChannelTreeState extends ConsumerState<_ChannelTree> {
  /// 上一次点击的频道、点下去之前的高亮位置与双击判定窗口。按 `channelId`
  /// 比对，而不是按行位置，因为列表复用会按位置复用行。
  ({int channelId, SelectedChannel? fallback, Timer timer})? _pendingTap;
  List<ChannelView>? _cachedChannels;
  List<ClientView>? _cachedClients;
  List<_TreeRow> _cachedRows = const [];

  @override
  void dispose() {
    _pendingTap?.timer.cancel();
    super.dispose();
  }

  List<_TreeRow> _flattenCached(
    List<ChannelView> channels,
    List<ClientView> clients,
  ) {
    if (identical(channels, _cachedChannels) &&
        identical(clients, _cachedClients)) {
      return _cachedRows;
    }
    final channelIds = <int>{for (final channel in channels) channel.id};
    final roots = <ChannelView>[];
    final childrenByParent = <int, List<ChannelView>>{};
    for (final channel in channels) {
      if (!channelIds.contains(channel.parentId)) {
        roots.add(channel);
      } else {
        (childrenByParent[channel.parentId] ??= <ChannelView>[]).add(channel);
      }
    }
    final clientsByChannel = <int, List<ClientView>>{};
    for (final client in clients) {
      (clientsByChannel[client.channelId] ??= <ClientView>[]).add(client);
    }

    final rows = <_TreeRow>[];
    void walk(ChannelView channel, int depth) {
      // spacer 只改变名字的画法：行高、选中与加入都和普通频道一致（官方
      // 客户端里双击装饰频道同样能进入房间）。
      final spacer = parseChannelSpacer(channel.name);
      rows.add(_ChannelRow(channel: channel, depth: depth, spacer: spacer));
      final members = clientsByChannel[channel.id];
      if (members != null) {
        for (final member in members) {
          rows.add(_MemberRow(client: member, depth: depth + 1));
        }
      }
      final children = childrenByParent[channel.id];
      if (children != null) {
        for (final child in children) {
          walk(child, depth + 1);
        }
      }
    }

    for (final root in roots) {
      walk(root, 0);
    }
    _cachedChannels = channels;
    _cachedClients = clients;
    _cachedRows = rows;
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final (
      :connected,
      :busy,
      :activeServerId,
      :selfChannelId,
      :channels,
      :clients,
    ) = ref.watch(
      sessionViewProvider.select(
        (view) => (
          connected: view.connected,
          busy: view.busy,
          activeServerId: view.activeServerId,
          selfChannelId: view.selfChannelId,
          channels: view.channels,
          clients: view.clients,
        ),
      ),
    );
    final activeId = ref.watch(activeChannelIdProvider);
    final hasSelectedMember = ref.watch(
      selectedMemberProvider.select(
        (selected) => selected != null && selected.serverId == activeServerId,
      ),
    );

    void select(ChannelView channel) {
      ref
          .read(selectedChannelProvider.notifier)
          .select(channel.id, serverId: activeServerId);
      ref.read(sessionViewProvider.notifier).selectChatScope(ChatScope.channel);
      widget.onChannelSelected?.call();
    }

    // 双击/右键加入频道：TS 里换频道就是移动到该频道的语音房间。
    // [fallback] 是加入被服务端拒时退回的高亮位置：双击的第一次点击已经改过
    // 高亮，得退回点下去之前的位置；右键菜单不动高亮，退回当前选中即可。
    Future<void> join(
      ChannelView channel, {
      required SelectedChannel? fallback,
    }) async {
      await ref
          .read(selectedChannelProvider.notifier)
          .join(
            channel.id,
            serverId: activeServerId,
            fallback: fallback,
            requestPassword: () =>
                requestChannelPassword(context, ref, channel.id),
          );
      if (!context.mounted) {
        return;
      }
      if (ref.read(selectedChannelProvider)?.channelId == channel.id) {
        ref
            .read(sessionViewProvider.notifier)
            .selectChatScope(ChatScope.channel);
      }
      // 抽屉不属于路由栈：加入频道后先收起抽屉，再到外壳切回工作区。
      // 桌面没有打开中的抽屉，这一步是空操作。
      Scaffold.maybeOf(context)?.closeDrawer();
      widget.onChannelSelected?.call();
    }

    void joinFromMenu(ChannelView channel) {
      unawaited(join(channel, fallback: ref.read(selectedChannelProvider)));
    }

    bool canJoinChannel(ChannelView channel) =>
        connected && !busy && selfChannelId != channel.id;

    // 窄屏单击即加入（若未在该频道）并推入二级页，无 300ms 双击延迟；
    // 桌面端维持单击预览、双击加入。
    void tap(ChannelView channel) {
      if (context.isCompact) {
        if (selfChannelId == channel.id) {
          select(channel);
          return;
        }
        if (!canJoinChannel(channel)) {
          return;
        }
        final currentSelected = ref.read(selectedChannelProvider);
        final fallback = currentSelected?.channelId == channel.id
            ? null
            : currentSelected;
        unawaited(() async {
          await ref
              .read(selectedChannelProvider.notifier)
              .join(
                channel.id,
                serverId: activeServerId,
                fallback: fallback,
                requestPassword: () =>
                    requestChannelPassword(context, ref, channel.id),
              );
          if (!mounted) {
            return;
          }
          final view = ref.read(sessionViewProvider);
          final joined =
              view.connected &&
              view.activeServerId == activeServerId &&
              (view.selfChannelId == channel.id ||
                  ref.read(selectedChannelProvider)?.channelId == channel.id);
          if (joined) {
            ref
                .read(sessionViewProvider.notifier)
                .selectChatScope(ChatScope.channel);
            widget.onChannelSelected?.call();
          }
        }());
        return;
      }
      final pending = _pendingTap;
      _pendingTap?.timer.cancel();
      if (pending != null &&
          pending.channelId == channel.id &&
          canJoinChannel(channel)) {
        _pendingTap = null;
        unawaited(join(channel, fallback: pending.fallback));
        return;
      }
      final fallback = ref.read(selectedChannelProvider);
      select(channel);
      _pendingTap = (
        channelId: channel.id,
        fallback: fallback,
        timer: Timer(kDoubleTapTimeout, () {
          _pendingTap = null;
          // 窄屏频道栏在抽屉里：抽屉留到双击窗口结束再收，否则第二次点击
          // 会落在正在移开的抽屉或遮罩上，触屏就没有双击加入了。
          if (mounted) {
            Scaffold.maybeOf(context)?.closeDrawer();
          }
        }),
      );
    }

    final rows = _flattenCached(channels, clients);
    if (rows.isEmpty) {
      // 掉线时主区域已经说明状态，频道栏留空，不再重复同一句话。
      if (!connected) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Text(
          l10n.workspaceNoChannels,
          style: context.texts.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final compact = context.isCompact;
    final dividerColor = dividerColorOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return PrismListView(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + widget.bottomInset),
      estimatedItemExtent: 40,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row) {
          _ChannelRow(:final channel, :final depth, :final spacer) =>
            MemoBuilder(
              inputs: [
                channel,
                depth,
                !hasSelectedMember && channel.id == activeId,
                canJoinChannel(channel),
                spacer?.align,
                spacer?.text,
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
                scheme.onSurfaceVariant,
                dividerColor,
                reduceMotion,
                compact,
                widget.onShowChannelDetails != null,
                widget.onShowChannelFiles != null,
              ],
              builder: (context) => _ChannelTile(
                channel: channel,
                depth: depth,
                selected: !hasSelectedMember && channel.id == activeId,
                onTap: () => tap(channel),
                onJoin: () => joinFromMenu(channel),
                canJoin: canJoinChannel(channel),
                spacer: spacer,
                onShowDetails: compact && widget.onShowChannelDetails != null
                    ? () => widget.onShowChannelDetails!(channel)
                    : null,
                onShowFiles: compact && widget.onShowChannelFiles != null
                    ? () => widget.onShowChannelFiles!(channel)
                    : null,
              ),
            ),
          _MemberRow(:final client, :final depth) => MemoBuilder(
            inputs: [
              client,
              depth,
              compact,
              widget.onShowMemberDetails != null,
              widget.onCompactDirectChat != null,
              widget.onCompactWatchStream != null,
            ],
            builder: (context) => _MemberTile(
              client: client,
              depth: depth,
              compactMenuOnTap: compact,
              onShowDetails: widget.onShowMemberDetails == null
                  ? null
                  : () => widget.onShowMemberDetails!(client),
              onDirectChat: widget.onCompactDirectChat,
              onWatchStream: widget.onCompactWatchStream,
            ),
          ),
        };
      },
    );
  }
}

sealed class _TreeRow {
  const _TreeRow();
}

class _ChannelRow extends _TreeRow {
  const _ChannelRow({required this.channel, required this.depth, this.spacer});

  final ChannelView channel;
  final int depth;
  final ChannelSpacer? spacer;
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
    required this.onTap,
    required this.onJoin,
    required this.canJoin,
    this.spacer,
    this.onShowDetails,
    this.onShowFiles,
  });

  final ChannelView channel;
  final int depth;
  final bool selected;

  /// 桌面单击预览、窄屏单击直接加入并进入二级频道页。
  final VoidCallback onTap;

  /// 双击或右键/长按菜单加入；已在频道里、未连接或命令进行中时不可用。
  final VoidCallback onJoin;
  final bool canJoin;

  /// 非 null 表示这是 spacer 频道：行高与点击、加入行为和普通频道一致，
  /// 只有名字区域换成装饰画法。
  final ChannelSpacer? spacer;
  final VoidCallback? onShowDetails;
  final VoidCallback? onShowFiles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final name = channelDisplayName(channel);
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final menuItems = [
      if (canJoin)
        PopupMenuItem(
          glyph: AppGlyphs.login,
          label: l10n.channelJoinMenu,
          onPressed: onJoin,
        ),
      if (onShowDetails != null)
        PopupMenuItem(
          glyph: AppGlyphs.info,
          label: l10n.channelDetails,
          onPressed: onShowDetails,
        ),
      if (onShowFiles != null)
        PopupMenuItem(
          glyph: AppGlyphs.folder,
          label: l10n.chatTabFiles,
          onPressed: onShowFiles,
        ),
    ];

    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: SecondaryMenu(
        enabled: menuItems.isNotEmpty,
        openOnSecondaryTap: true,
        items: menuItems,
        builder: (context, _) => Semantics(
          button: true,
          selected: selected,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.effectsFast,
            curve: Motion.effectsDefaultCurve,
            decoration: ShapeDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              shape: AppShape.md,
            ),
            child: ClipRSuperellipse(
              borderRadius: AppRadius.md,
              child: AnimatedInkWell(
                onTap: onTap,
                customBorder: AppShape.md,
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: spacer == null
                        ? Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Row(
                              children: [
                                ChannelIcon(
                                  iconId: channel.iconId,
                                  color: foreground,
                                ),
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
                                if (channel.passwordProtected == true)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Icon(
                                      Icons.lock_rounded,
                                      size: IconSizes.small,
                                      color: foreground,
                                      semanticLabel:
                                          l10n.channelPasswordProtected,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : _spacerBody(context, foreground),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 官方 spacer 行不带频道图标，只有装饰内容本身；
  /// 颜色跟随行的前景（选中时用胶囊上的对比色）。
  Widget _spacerBody(BuildContext context, Color foreground) {
    if (spacer!.isLine) {
      // 官方按字符画线（_ 实线 / - 虚线 / . 点线），这里统一用一条分隔线表达。
      return Align(child: Container(height: 1, color: dividerColorOf(context)));
    }
    if (spacer!.text.isEmpty) {
      // 纯前缀的空 spacer 在官方里占一个空行，不写任何内容。
      return const SizedBox.shrink();
    }
    final style = context.texts.bodySmall?.copyWith(
      fontSize: 13,
      color: foreground,
    );
    if (spacer!.align == SpacerAlign.fill) {
      return _FillSpacerText(text: spacer!.text, style: style);
    }
    return Align(
      alignment: switch (spacer!.align) {
        SpacerAlign.left => AlignmentDirectional.centerStart,
        SpacerAlign.center => AlignmentDirectional.center,
        SpacerAlign.right => AlignmentDirectional.centerEnd,
        // fill 在上面单独处理，这里只为穷尽。
        SpacerAlign.fill => AlignmentDirectional.center,
      },
      child: Text(
        spacer!.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// `[*spacer]` 的官方语义：把文本当单元重复铺满整行；只放完整单元，行尾不留半截。
class _FillSpacerText extends StatelessWidget {
  const _FillSpacerText({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return WidthBuilder(
      builder: (context, width) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final unitWidth = painter.width;
        painter.dispose();
        if (unitWidth <= 0 || !width.isFinite) {
          return const SizedBox.shrink();
        }
        final repeat = (width / unitWidth).floor();
        return Align(
          child: Text(
            text * (repeat < 1 ? 1 : repeat),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: style,
          ),
        );
      },
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.client,
    required this.depth,
    this.compactMenuOnTap = false,
    this.onShowDetails,
    this.onDirectChat,
    this.onWatchStream,
  });

  final ClientView client;
  final int depth;
  final bool compactMenuOnTap;
  final VoidCallback? onShowDetails;
  final VoidCallback? onDirectChat;
  final ValueChanged<StreamView>? onWatchStream;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final activeServerId = ref.watch(
      sessionViewProvider.select((view) => view.activeServerId),
    );
    final selected = ref.watch(
      selectedMemberProvider.select(
        (item) =>
            item != null &&
            item.serverId == activeServerId &&
            item.clientId == client.id &&
            item.uid == client.uid,
      ),
    );
    // 服务器不回显自己的声音，自己说话由 SelfSpeaking 事件单独表达。
    final speaking = ref.watch(
      sessionViewProvider.select(
        (view) =>
            view.speaking.contains(client.id) ||
            (client.id == view.selfClientId && view.selfSpeaking),
      ),
    );
    final sharingScreen = ref.watch(
      sessionViewProvider.select((view) => view.isClientSharingScreen(client)),
    );
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final avatar = SessionMemberAvatar(
      uid: client.uid,
      nickname: client.nickname,
      size: AvatarSize.small,
      speaking: speaking,
      onSurface: true,
    );

    return Padding(
      padding: EdgeInsets.only(left: 32.0 + (depth - 1) * 16.0, right: 6),
      child: ClientActionsButton(
        client: client,
        compactMenuOnTap: compactMenuOnTap,
        onShowDetails: onShowDetails,
        onDirectChat: onDirectChat,
        onWatchStream: onWatchStream,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // 头像本身用光环表达说话；读屏靠外层标签拿到同一个状态。
              speaking
                  ? Semantics(label: l10n.memberSpeaking, child: avatar)
                  : avatar,
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        client.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall?.copyWith(
                          fontSize: 13,
                          color: foreground,
                        ),
                      ),
                    ),
                    if (client.clientType == ClientType.bot) ...[
                      const SizedBox(width: 4),
                      Semantics(
                        label: l10n.clientTypeBot,
                        child: Icon(
                          Icons.smart_toy_rounded,
                          size: 13,
                          color: scheme.tertiary,
                        ),
                      ),
                    ] else if (client.clientType == ClientType.flSpeak) ...[
                      const SizedBox(width: 4),
                      Semantics(
                        label: l10n.clientTypeFlSpeak,
                        child: Icon(
                          Icons.electric_bolt_rounded,
                          size: 13,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              MemberStatusFlags(client: client, sharingScreen: sharingScreen),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserFooter extends ConsumerStatefulWidget {
  const _UserFooter({this.onDisconnect});

  final VoidCallback? onDisconnect;

  @override
  ConsumerState<_UserFooter> createState() => _UserFooterState();
}

class _UserFooterState extends ConsumerState<_UserFooter> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = ref.read(sessionViewProvider).networkPanelPinned;
  }

  void _toggleNetwork() {
    if (_expanded) {
      _closeNetwork();
    } else {
      setState(() => _expanded = true);
    }
  }

  void _closeNetwork() {
    if (!_expanded) {
      return;
    }
    setState(() => _expanded = false);
    if (ref.read(sessionViewProvider).networkPanelPinned) {
      ref.read(sessionViewProvider.notifier).setNetworkPanelPinned(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final (
      :connected,
      :reconnecting,
      :busy,
      :selfChannelId,
      :muted,
      :deafened,
      :away,
    ) = ref.watch(
      sessionViewProvider.select(
        (view) => (
          connected: view.connected,
          reconnecting: view.reconnecting,
          busy: view.busy,
          selfChannelId: view.selfChannelId,
          muted: view.muted,
          deafened: view.deafened,
          away: view.away,
        ),
      ),
    );
    final sharingScreen = ref.watch(
      streamPublisherProvider.select((state) => state.isActive),
    );

    ref.listen<({int epoch, bool connected, bool pinned})>(
      sessionViewProvider.select(
        (view) => (
          epoch: view.connectionEpoch,
          connected: view.connected,
          pinned: view.networkPanelPinned,
        ),
      ),
      (previous, next) {
        if (previous != null &&
            (next.epoch != previous.epoch ||
                (!next.connected && previous.connected))) {
          if (_expanded) {
            setState(() => _expanded = false);
          }
          return;
        }
        if (next.pinned && !(previous?.pinned ?? false) && !_expanded) {
          setState(() => _expanded = true);
        }
      },
    );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: SurfaceCard(
        shape: AppShape.md,
        clip: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CardExtension(
              expanded: _expanded,
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NetworkTelemetryPanel(onClose: _closeNetwork),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Divider(height: 1, thickness: 1),
                  ),
                ],
              ),
            ),
            if (connected || reconnecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final (
                            :isConnected,
                            :network,
                            :channelLabel,
                          ) = ref.watch(
                            sessionViewProvider.select((view) {
                              final channel = view.selfChannelId == null
                                  ? null
                                  : view.channelById(view.selfChannelId!);
                              return (
                                isConnected: view.connected,
                                network: view.network,
                                channelLabel: channel == null
                                    ? (view.activeServer?.label ?? l10n.appName)
                                    : channelDisplayName(channel),
                              );
                            }),
                          );
                          return NetworkStatus(
                            connected: isConnected,
                            network: network,
                            expanded: _expanded,
                            onToggle: _toggleNetwork,
                            channelLabel: channelLabel,
                          );
                        },
                      ),
                    ),
                    if (connected && selfChannelId != null)
                      _IconToggle(
                        key: const ValueKey('voice-screen-share-toggle'),
                        label: sharingScreen
                            ? l10n.streamStopShare
                            : l10n.streamStartShare,
                        icon: sharingScreen
                            ? Icons.stop_screen_share_rounded
                            : Icons.screen_share_rounded,
                        active: sharingScreen,
                        onTap: () {
                          if (sharingScreen) {
                            unawaited(
                              ref
                                  .read(sessionViewProvider.notifier)
                                  .stopScreenShare(),
                            );
                          } else {
                            unawaited(
                              showScreenSharePickerAndStart(context, ref),
                            );
                          }
                        },
                      ),
                    if (widget.onDisconnect != null)
                      IconButton.filled(
                        onPressed: busy ? null : widget.onDisconnect,
                        style: ButtonStyle.from(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                        ),
                        icon: Icon(
                          Icons.call_end_rounded,
                          size: IconSizes.toolbar,
                          semanticLabel: l10n.serverDisconnect,
                        ),
                      ),
                  ],
                ),
              ),
            if (connected || reconnecting)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Divider(height: 1, thickness: 1),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.28),
                        borderRadius: Radii.mediumAll,
                      ),
                      child: const SizedBox(
                        height: 40,
                        child: VoiceActivityRibbon(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _IconToggle(
                    label: muted ? l10n.voiceUnmute : l10n.voiceMute,
                    icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    active: muted,
                    onTap: () =>
                        ref.read(sessionViewProvider.notifier).setMuted(!muted),
                  ),
                  _IconToggle(
                    label: deafened ? l10n.voiceUndeafen : l10n.voiceDeafen,
                    icon: deafened
                        ? Icons.headset_off_rounded
                        : Icons.headphones_rounded,
                    active: deafened,
                    onTap: () => ref
                        .read(sessionViewProvider.notifier)
                        .setDeafened(!deafened),
                  ),
                  _IconToggle(
                    label: away ? l10n.voiceUnaway : l10n.voiceAway,
                    icon: Icons.schedule_rounded,
                    active: away,
                    activeContainer: scheme.primaryContainer,
                    activeOnContainer: scheme.onPrimaryContainer,
                    onTap: () =>
                        ref.read(sessionViewProvider.notifier).setAway(!away),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 用户卡向上延伸的展开区：内容随高度因子被裁剪，关闭动画结束后才释放面板。
class _CardExtension extends StatefulWidget {
  const _CardExtension({required this.expanded, required this.builder});

  final bool expanded;
  final WidgetBuilder builder;

  @override
  State<_CardExtension> createState() => _CardExtensionState();
}

class _CardExtensionState extends State<_CardExtension>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.effectsDefault,
    reverseDuration: Motion.effectsFast,
  );
  late bool _visible = widget.expanded;

  @override
  void initState() {
    super.initState();
    if (widget.expanded) {
      _controller.value = 1;
    }
    _controller.addStatusListener(_handleStatus);
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.expanded && _visible) {
      setState(() => _visible = false);
    }
  }

  @override
  void didUpdateWidget(covariant _CardExtension oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _controller.duration = reduceMotion ? Duration.zero : Motion.effectsDefault;
    _controller.reverseDuration = reduceMotion
        ? Duration.zero
        : Motion.effectsFast;
    if (widget.expanded) {
      if (!_visible) {
        setState(() => _visible = true);
      }
      if (reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else {
      if (reduceMotion) {
        _controller.value = 0;
        if (_visible) {
          setState(() => _visible = false);
        }
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.builder(context),
      builder: (context, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: _controller.value,
          child: child,
        ),
      ),
    );
  }
}

/// 静音/闭麦开关：视觉圆点 36，落点撑到 48（M3 触控下限）。
class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.activeContainer,
    this.activeOnContainer,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  /// 激活态的 container 语义对；静音类状态缺省用 error 对，中性状态
  /// （离开）传 primary 对。透明度叠底在暗色下发浊，container 对
  /// 亮暗都成立。
  final Color? activeContainer;
  final Color? activeOnContainer;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final activeBackground = activeContainer ?? scheme.errorContainer;
    final activeForeground = activeOnContainer ?? scheme.onErrorContainer;
    return Semantics(
      label: label,
      button: true,
      toggled: active,
      child: IconButton(
        onPressed: onTap,
        isSelected: active,
        style: ButtonStyle.from(
          backgroundColor: active ? activeBackground : Colors.transparent,
          foregroundColor: active ? activeForeground : scheme.onSurfaceVariant,
          shape: AppShape.circle,
          minimumSize: const Size(36, 36),
          maximumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
        ),
        icon: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : Motion.effectsFast,
          switchInCurve: Motion.effectsFastCurve,
          switchOutCurve: Motion.effectsFastCurve.flipped,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: animation.drive(Tween(begin: 0.8, end: 1.0)),
              child: child,
            ),
          ),
          child: Icon(
            icon,
            key: ValueKey(icon),
            size: IconSizes.toolbar,
            color: active ? activeForeground : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
