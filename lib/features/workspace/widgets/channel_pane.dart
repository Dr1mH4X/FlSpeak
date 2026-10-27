import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/channel_display.dart';
import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/channel_icon.dart';
import '../../../widgets/monogram.dart';
import '../workspace_state.dart';
import 'voice_activity_ribbon.dart';

/// 频道栏：服务器身份、统一的频道树、当前用户。
///
/// TeamSpeak 的频道不区分文字与语音——每个频道既是语音房间也承载文字消息，
/// 所以设计稿里的「文字频道 / 语音频道」两段在真实数据上没有依据，这里只保留
/// 一棵按 `parentId` 展开的频道树，成员跟随所属频道缩进显示。
class ChannelPanel extends ConsumerStatefulWidget {
  const ChannelPanel({this.onChannelSelected, this.onDisconnect, super.key});

  /// 点频道后离开设置页，回到工作区。
  final VoidCallback? onChannelSelected;
  final VoidCallback? onDisconnect;

  @override
  ConsumerState<ChannelPanel> createState() => _ChannelPanelState();
}

class _ChannelPanelState extends ConsumerState<ChannelPanel> {
  /// 上一次点击的频道、点下去之前的高亮位置与双击判定窗口。按 `channelId`
  /// 比对，而不是按行位置，因为 `ListView.builder` 会按位置复用行。
  ({int channelId, SelectedChannel? fallback, Timer timer})? _pendingTap;

  @override
  void dispose() {
    _pendingTap?.timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final view = ref.watch(sessionViewProvider);
    final activeId = ref.watch(activeChannelIdProvider);

    void select(ChannelView channel) {
      ref
          .read(selectedChannelProvider.notifier)
          .select(channel.id, serverId: view.activeServerId);
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
          .join(channel.id, serverId: view.activeServerId, fallback: fallback);
      if (!context.mounted) {
        return;
      }
      // 抽屉不属于路由栈：加入频道后先收起抽屉，再到外壳切回工作区。
      // 桌面没有打开中的抽屉，这一步是空操作。
      Scaffold.maybeOf(context)?.closeDrawer();
      widget.onChannelSelected?.call();
    }

    // 右键菜单的加入：按点菜单那一刻的选中位置回退，不受双击窗口干扰。
    void joinFromMenu(ChannelView channel) {
      unawaited(join(channel, fallback: ref.read(selectedChannelProvider)));
    }

    // 单击只看、双击进入。不用 `InkWell.onDoubleTap`：它会把手势竞技场按到
    // `kDoubleTapTimeout` 之后，单击反馈也跟着晚一拍。改成按点击间隔自己判定，
    // 单击当场派发，第二次点击落在窗口内才算双击。
    void tap(ChannelView channel) {
      final pending = _pendingTap;
      _pendingTap?.timer.cancel();
      if (pending != null &&
          pending.channelId == channel.id &&
          _canJoin(view, channel)) {
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

    return Material(
      color: scheme.surfaceContainerLow,
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
                    tap,
                    joinFromMenu,
                  ),
                ),
              ],
            ),
          ),
          _UserFooter(
            view: view,
            onDisconnect: widget.onDisconnect,
            muted: view.muted,
            deafened: view.deafened,
            away: view.away,
            onToggleMute: () =>
                ref.read(sessionViewProvider.notifier).setMuted(!view.muted),
            onToggleDeafen: () => ref
                .read(sessionViewProvider.notifier)
                .setDeafened(!view.deafened),
            onToggleAway: () =>
                ref.read(sessionViewProvider.notifier).setAway(!view.away),
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
    return SizedBox(
      height: Sizes.header,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 4),
        child: Row(
          children: [
            Icon(Icons.dns_outlined, size: 20, color: context.scheme.primary),
            const SizedBox(width: 10),
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
    void Function(ChannelView channel) onTap,
    // 菜单通道的加入：回退位置由调用方按当时的选中补齐。
    void Function(ChannelView channel) onJoin,
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
          _ChannelRow(:final channel, :final depth, :final spacer) =>
            _ChannelTile(
              channel: channel,
              depth: depth,
              selected: channel.id == activeId,
              onTap: () => onTap(channel),
              onJoin: () => onJoin(channel),
              canJoin: _canJoin(view, channel),
              spacer: spacer,
            ),
          _MemberRow(:final client, :final depth) => _MemberTile(
            client: client,
            depth: depth,
            // 服务器不回显自己的声音，自己说话由 SelfSpeaking 事件单独表达。
            speaking:
                view.speaking.contains(client.id) ||
                (client.id == view.selfClientId && view.selfSpeaking),
          ),
        };
      },
    );
  }

  List<_TreeRow> _flatten(SessionView view) {
    final rows = <_TreeRow>[];

    void walk(ChannelView channel, int depth) {
      // spacer 只改变名字的画法：行高、选中与加入都和普通频道一致（官方
      // 客户端里双击装饰频道同样能进入房间）。
      final spacer = parseChannelSpacer(channel.name);
      final children = view.orderedChildrenOf(channel.id);
      final members = view.clientsIn(channel.id);
      rows.add(_ChannelRow(channel: channel, depth: depth, spacer: spacer));
      for (final member in members) {
        rows.add(_MemberRow(client: member, depth: depth + 1));
      }
      for (final child in children) {
        walk(child, depth + 1);
      }
    }

    for (final root in view.orderedRootChannels()) {
      walk(root, 0);
    }
    return rows;
  }
}

sealed class _TreeRow {
  const _TreeRow();
}

/// 可以双击/右键加入：已连接、没有命令在跑，且自己还不在这个频道里。
bool _canJoin(SessionView view, ChannelView channel) =>
    view.connected && !view.busy && view.selfChannelId != channel.id;

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
  });

  final ChannelView channel;
  final int depth;
  final bool selected;

  /// 单击：只换主区域展示的频道；双击由父级按点击间隔判定后另外加入。
  final VoidCallback onTap;

  /// 双击或右键菜单加入；已在频道里、未连接或命令进行中时不可用。
  final VoidCallback onJoin;
  final bool canJoin;

  /// 非 null 表示这是 spacer 频道：行高与点击、加入行为和普通频道一致，
  /// 只有名字区域换成装饰画法。
  final ChannelSpacer? spacer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final name = channelDisplayName(channel);
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: SecondaryMenu(
        enabled: canJoin,
        openOnSecondaryTap: true,
        items: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.login_rounded, size: 18),
            onPressed: canJoin ? onJoin : null,
            child: Text(l10n.channelJoinMenu),
          ),
        ],
        builder: (context, menuController) => Semantics(
          button: true,
          selected: selected,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.effectsFast,
            curve: Motion.effectsDefaultCurve,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: Radii.mediumAll,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: Radii.mediumAll,
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
                                      size: 15,
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
    final scheme = context.scheme;
    if (spacer!.isLine) {
      // 官方按字符画线（_ 实线 / - 虚线 / . 点线），这里统一用一条分隔线表达。
      return Align(child: Container(height: 1, color: scheme.outlineVariant));
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final unitWidth = painter.width;
        painter.dispose();
        if (unitWidth <= 0 || !constraints.maxWidth.isFinite) {
          return const SizedBox.shrink();
        }
        final repeat = (constraints.maxWidth / unitWidth).floor();
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
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final avatar = MemberAvatar(
      label: initialsOf(client.nickname),
      size: AvatarSize.small,
      speaking: speaking,
      onSurface: true,
    );

    return Padding(
      padding: EdgeInsets.only(left: 40.0 + (depth - 1) * 16.0, right: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            // 头像本身用光环表达说话；读屏靠外层标签拿到同一个状态。
            speaking
                ? Semantics(label: l10n.memberSpeaking, child: avatar)
                : avatar,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                client.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            // 服务器回显的设备状态：快照没带标志（null）时不显示。
            if (client.inputMuted ?? false)
              _MemberFlag(
                label: l10n.memberMicMuted,
                icon: Icons.mic_off_rounded,
              ),
            if (client.outputMuted ?? false)
              _MemberFlag(
                label: l10n.memberSpeakerMuted,
                icon: Icons.volume_off_rounded,
              ),
            if (client.away ?? false)
              _MemberFlag(
                label: switch (client.awayMessage) {
                  null || '' => l10n.memberAway,
                  final message => l10n.memberAwayWith(message),
                },
                icon: Icons.schedule_rounded,
                color: scheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

/// 成员行尾的状态标志：与其他成员昵称保持间距。
class _MemberFlag extends StatelessWidget {
  const _MemberFlag({required this.label, required this.icon, this.color});

  final String label;
  final IconData icon;

  /// 静音类标志缺省用 error，离开这类中性状态换主色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(
        icon,
        size: 14,
        color: color ?? scheme.error,
        semanticLabel: label,
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.view,
    required this.muted,
    required this.deafened,
    required this.away,
    required this.onToggleMute,
    required this.onToggleDeafen,
    required this.onToggleAway,
    this.onDisconnect,
  });

  final SessionView view;
  final bool muted;
  final bool deafened;
  final bool away;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleAway;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final channel = view.selfChannelId == null
        ? null
        : view.channelById(view.selfChannelId!);
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: Radii.largeAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (view.connected || view.reconnecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.network_check_rounded,
                    size: 22,
                    color: view.connected
                        ? context.status.live
                        : scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          view.connected
                              ? l10n.voiceConnected
                              : l10n.sessionConnecting,
                          style: context.texts.labelMedium?.copyWith(
                            color: view.connected
                                ? context.status.live
                                : scheme.primary,
                          ),
                        ),
                        Text(
                          channel == null
                              ? (view.activeServer?.label ?? l10n.appName)
                              : channelDisplayName(channel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onDisconnect != null)
                    IconButton(
                      onPressed: view.busy ? null : onDisconnect,
                      icon: Icon(
                        Icons.call_end_rounded,
                        size: 20,
                        semanticLabel: l10n.serverDisconnect,
                      ),
                    ),
                ],
              ),
            ),
          if (view.connected || view.reconnecting)
            Divider(
              height: 1,
              indent: 12,
              endIndent: 12,
              color: scheme.outlineVariant,
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
                  onTap: onToggleMute,
                ),
                _IconToggle(
                  label: deafened ? l10n.voiceUndeafen : l10n.voiceDeafen,
                  icon: deafened
                      ? Icons.headset_off_rounded
                      : Icons.headphones_rounded,
                  active: deafened,
                  onTap: onToggleDeafen,
                ),
                _IconToggle(
                  label: away ? l10n.voiceUnaway : l10n.voiceAway,
                  icon: Icons.schedule_rounded,
                  active: away,
                  activeContainer: scheme.primaryContainer,
                  activeOnContainer: scheme.onPrimaryContainer,
                  onTap: onToggleAway,
                ),
              ],
            ),
          ),
        ],
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
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: Sizes.touch,
          height: Sizes.touch,
          child: Center(
            child: AnimatedContainer(
              width: 36,
              height: 36,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.effectsFast,
              curve: Motion.effectsDefaultCurve,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? activeBackground : Colors.transparent,
              ),
              child: Icon(
                icon,
                size: 20,
                color: active ? activeForeground : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
