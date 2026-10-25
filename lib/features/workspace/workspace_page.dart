import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:go_router/go_router.dart';

import '../../core/channel_display.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'widgets/chat_pane.dart';
import 'widgets/media_grid.dart';
import 'widgets/media_viewer.dart';
import 'workspace_state.dart';

/// 主区域：频道标题 + 消息 / 媒体两个视图，以及未连接时的下一步。
class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({super.key});

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

enum _MainTab { chat, media }

class _WorkspacePageState extends ConsumerState<WorkspacePage> {
  _MainTab _tab = _MainTab.chat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final channelId = ref.watch(activeChannelIdProvider);

    // 换频道时回到消息页，和原型一致；延迟一帧避免在构建期触发 setState。
    ref.listen<int?>(activeChannelIdProvider, (previous, next) {
      if (previous == next || _tab == _MainTab.chat) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tab != _MainTab.chat) {
          setState(() => _tab = _MainTab.chat);
        }
      });
    });

    final channel = channelId == null ? null : view.channelById(channelId);
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChannelHeader(
          compact: compact,
          channelName: channel == null ? null : channelDisplayName(channel),
          selected: _tab,
          onChanged: (tab) => setState(() => _tab = tab),
        ),
        if (view.identityUpgradeTarget != null)
          _IdentityBanner(
            target: view.identityUpgradeTarget!,
            onCancel: ref
                .read(sessionViewProvider.notifier)
                .cancelIdentityUpgrade,
          ),
        _VoiceAlerts(
          view: view,
          onDismissNotice: ref
              .read(sessionViewProvider.notifier)
              .dismissVoiceNotice,
        ),
        Expanded(child: _buildBody(context, l10n, view, channel)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    SessionView view,
    ChannelView? channel,
  ) {
    if (!view.connected && !view.connecting && !view.reconnecting) {
      return EmptyState(
        icon: Icons.power_off_rounded,
        title: l10n.workspaceNotConnectedTitle,
        body: l10n.workspaceNotConnectedBody,
        action: FilledButton.icon(
          onPressed: () => context.go(AppRoutes.connect),
          icon: const Icon(Icons.link_rounded, size: 18),
          label: Text(l10n.connectTitle),
        ),
      );
    }

    if (view.connecting || view.reconnecting) {
      final scheme = context.scheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              view.reconnecting
                  ? l10n.voiceReconnectingAttempt(view.reconnectAttempt ?? 1)
                  : l10n.sessionConnecting,
              style: context.texts.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (channel == null) {
      return EmptyState(
        icon: Icons.forum_outlined,
        body: l10n.workspaceNoChannels,
      );
    }

    final controller = ref.read(sessionViewProvider.notifier);
    switch (_tab) {
      case _MainTab.media:
        final urls = imageUrlsInMessages(
          view.visibleMessages(channelId: channel.id),
        );
        return MediaGrid(
          urls: urls,
          onOpen: (index) =>
              showMediaViewer(context, urls: urls, initialIndex: index),
        );
      case _MainTab.chat:
        return ChatPane(
          key: ValueKey(channel.id),
          channelName: channelDisplayName(channel),
          messages: view.visibleMessages(channelId: channel.id),
          scope: view.chatScope,
          canSendChannel: view.selfChannelId == channel.id,
          busy: view.busy,
          onScopeChanged: controller.selectChatScope,
          onSend: controller.sendMessage,
        );
    }
  }
}

class _TabSpec {
  const _TabSpec({required this.tab, required this.label, required this.icon});

  final _MainTab tab;
  final String label;
  final IconData icon;
}

List<_TabSpec> _tabSpecs(AppLocalizations l10n) => [
  _TabSpec(
    tab: _MainTab.chat,
    label: l10n.chatTabMessages,
    icon: Icons.chat_bubble_outline_rounded,
  ),
  _TabSpec(
    tab: _MainTab.media,
    label: l10n.chatTabMedia,
    icon: Icons.photo_library_outlined,
  ),
];

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.compact,
    required this.channelName,
    required this.selected,
    required this.onChanged,
  });

  final bool compact;
  final String? channelName;
  final _MainTab selected;
  final ValueChanged<_MainTab> onChanged;

  /// 三个页签的文字宽度随语言和字号变化；放不下时退回「图标 + tooltip」，
  /// 否则英文长标签或放大字号会把标题挤成零宽。
  bool _tabsFit(
    BuildContext context,
    double availableWidth,
    List<_TabSpec> tabs,
  ) {
    final style = context.texts.labelMedium?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    var tabWidth = 8.0; // 胶囊内边距 4 * 2
    for (final tab in tabs) {
      final painter = TextPainter(
        text: TextSpan(text: tab.label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      tabWidth += 16 + 6 + painter.width + 36; // 图标 + 间距 + 左右内边距
    }
    final chrome =
        2 * (compact ? 8.0 : 24.0) +
        (compact ? Sizes.touch + 8 : 0) +
        20 +
        6 +
        6;
    // 标题至少要留出两三个字的位置，否则宁可用图标页签保住频道名。
    const minTitleWidth = 64.0;
    return tabWidth <= availableWidth - chrome - minTitleWidth;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final horizontal = compact ? 8.0 : 24.0;
    final hasChannel = channelName != null;

    return SizedBox(
      height: Sizes.header,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabs = _tabSpecs(l10n);
          final labeledTabs =
              hasChannel && _tabsFit(context, constraints.maxWidth, tabs);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: Row(
              children: [
                if (compact) ...[
                  IconButton(
                    tooltip: l10n.workspaceOpenMenu,
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(Sizes.touch, Sizes.touch),
                    ),
                    icon: const Icon(Icons.menu_rounded, size: 24),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      channelName ?? l10n.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                if (hasChannel) ...[
                  const SizedBox(width: 6),
                  _ViewTabs(
                    tabs: tabs,
                    selected: selected,
                    labeled: labeledTabs,
                    onChanged: onChanged,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.tabs,
    required this.selected,
    required this.labeled,
    required this.onChanged,
  });

  final List<_TabSpec> tabs;
  final _MainTab selected;
  final bool labeled;
  final ValueChanged<_MainTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainer,
        borderRadius: Radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tab in tabs)
            _TabButton(
              spec: tab,
              active: selected == tab.tab,
              labeled: labeled,
              onTap: () => onChanged(tab.tab),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.spec,
    required this.active,
    required this.labeled,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool active;
  final bool labeled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final foreground = active ? scheme.onSurface : scheme.onSurfaceVariant;

    final content = labeled
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                spec.label,
                maxLines: 1,
                style: context.texts.labelMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          )
        : Icon(spec.icon, size: 18, color: foreground);

    // 36 高的视觉胶囊包在 44 高的落点里：原型是 h-9，触屏最小落点要 44。
    // 点击响应（水波纹）画在胶囊自己的 Material 上，跟胶囊一样大；
    // 外圈 4px 只扩大落点，不画反馈。
    final pill = Container(
      height: 36,
      width: labeled ? null : 36,
      decoration: active
          ? BoxDecoration(
              color: context.cardColor,
              borderRadius: Radii.pillAll,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            )
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.pillAll,
          child: Padding(
            // 活动胶囊 r18（22 − 4）：label 的水平内边距 ≥ 半径才光学对齐。
            padding: labeled
                ? const EdgeInsets.symmetric(horizontal: 18)
                : EdgeInsets.zero,
            child: content,
          ),
        ),
      ),
    );

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: Sizes.touch,
        width: labeled ? null : Sizes.touch,
        child: Center(child: pill),
      ),
    );

    final child = labeled
        ? button
        : Tooltip(message: spec.label, child: button);
    return Semantics(
      button: true,
      selected: active,
      label: labeled ? null : spec.label,
      excludeSemantics: !labeled,
      child: child,
    );
  }
}

class _IdentityBanner extends StatelessWidget {
  const _IdentityBanner({required this.target, required this.onCancel});

  final int target;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        // 与 NoticeBar 一致：同为页面级横幅，圆角取同一档。
        borderRadius: Radii.xxlAll,
      ),
      child: Row(
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.identityUpgrading(target),
              style: context.texts.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(onPressed: onCancel, child: Text(l10n.identityCancel)),
        ],
      ),
    );
  }
}

/// 语音提示：设备不可用 chip 与语音错误条，任何页签下都可见。
class _VoiceAlerts extends StatelessWidget {
  const _VoiceAlerts({required this.view, required this.onDismissNotice});

  final SessionView view;
  final VoidCallback onDismissNotice;

  @override
  Widget build(BuildContext context) {
    if (!view.connected) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!view.voiceInputReady || !view.voiceOutputReady)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!view.voiceInputReady)
                  _DeviceChip(
                    icon: Icons.mic_off_rounded,
                    label: l10n.voiceMicUnavailable,
                  ),
                if (!view.voiceOutputReady)
                  _DeviceChip(
                    icon: Icons.volume_off_rounded,
                    label: l10n.voiceSpeakerUnavailable,
                  ),
              ],
            ),
          ),
        if (view.voiceNotice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: NoticeBar(
              message: view.voiceNotice!,
              dismissTooltip: l10n.commonClose,
              onDismiss: onDismissNotice,
            ),
          ),
      ],
    );
  }
}

/// 设备不可用的状态 chip。
class _DeviceChip extends StatelessWidget {
  const _DeviceChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: Radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.error),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
