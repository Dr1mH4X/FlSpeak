import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../core/channel_display.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_motion.dart';
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

class _WorkspacePageState extends ConsumerState<WorkspacePage>
    with SingleTickerProviderStateMixin {
  // M3 primary tabs：页签状态由 TabController 持有，指示器动画随组件自带。
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  )..addListener(_handleTabChanged);
  _MainTab _tab = _MainTab.chat;

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    final tab = _MainTab.values[_tabController.index];
    if (tab != _tab) {
      setState(() => _tab = tab);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final channelId = ref.watch(activeChannelIdProvider);

    // 换频道时回到消息页，和原型一致；延迟一帧避免在构建期触发 setState。
    ref.listen<int?>(activeChannelIdProvider, (previous, next) {
      if (previous == next || _tabController.index == 0) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController.index != 0) {
          if (MediaQuery.disableAnimationsOf(context)) {
            _tabController.index = 0;
          } else {
            _tabController.animateTo(0);
          }
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
          tabController: _tabController,
        ),
        if (view.identityUpgradeTarget != null)
          _IdentityBanner(
            target: view.identityUpgradeTarget!,
            onCancel: ref
                .read(sessionViewProvider.notifier)
                .cancelIdentityUpgrade,
          ),
        _VoiceAlerts(view: view),
        Expanded(
          // 视图替换走 crossfade（M3 effects default）：同一容器内换内容
          // 不做位移，避免整块内容跳来跳去。
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.effectsDefault,
            switchInCurve: Motion.effectsDefaultCurve,
            switchOutCurve: Motion.effectsDefaultCurve.flipped,
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: _buildBody(context, l10n, view, channel),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    SessionView view,
    ChannelView? channel,
  ) {
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
        icon: Icons.forum_rounded,
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
    icon: Icons.chat_bubble_rounded,
  ),
  _TabSpec(
    tab: _MainTab.media,
    label: l10n.chatTabMedia,
    icon: Icons.photo_library_rounded,
  ),
];

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.compact,
    required this.channelName,
    required this.tabController,
  });

  final bool compact;
  final String? channelName;
  final TabController tabController;

  /// 三个页签的文字宽度随语言和字号变化；放不下时退回「图标 + 语义标签」，
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
    var tabWidth = 0.0;
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
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(Sizes.touch, Sizes.touch),
                    ),
                    icon: Icon(
                      Icons.menu_rounded,
                      size: 24,
                      semanticLabel: l10n.workspaceOpenMenu,
                    ),
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
                    controller: tabController,
                    labeled: labeledTabs,
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

/// 频道头里的视图切换：M3 primary tabs（`TabBar`）。
///
/// 之前是手写的胶囊按钮组；segmented button 在 M3 Expressive 里已不再
/// 推荐，替代的 connected button group 在 Flutter 上不可用，primary tabs
/// 是同级视图切换的规范组件，指示器动画与语义由组件自带。
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.tabs,
    required this.controller,
    required this.labeled,
  });

  final List<_TabSpec> tabs;
  final TabController controller;
  final bool labeled;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      // M3 scrollable tabs 的默认对齐：首签偏移一个 tab 边距。
      tabAlignment: TabAlignment.startOffset,
      // 频道头只有 64 高，页签压到 40 贴标题基线。
      splashBorderRadius: Radii.pillAll,
      tabs: [
        for (final tab in tabs)
          Tab(
            height: 48,
            child: labeled
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tab.icon, size: 16),
                      const SizedBox(width: 6),
                      Text(tab.label, maxLines: 1),
                    ],
                  )
                : Icon(tab.icon, size: 18, semanticLabel: tab.label),
          ),
      ],
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
        // 与页面级横幅同一档圆角。
        borderRadius: Radii.xxlAll,
      ),
      child: Row(
        children: [
          Icon(
            Icons.workspace_premium_rounded,
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

/// 语音设备状态 chip，任何页签下都可见。瞬时语音错误走右上角提示。
class _VoiceAlerts extends StatelessWidget {
  const _VoiceAlerts({required this.view});

  final SessionView view;

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
        // container 语义对：透明度叠底在暗色下发浊，正文对比不稳。
        color: scheme.errorContainer,
        borderRadius: Radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onErrorContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
