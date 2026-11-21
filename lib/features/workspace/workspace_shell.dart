import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart'
    hide
        ButtonStyle,
        Divider,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network_quality.dart';
import '../../core/notices.dart';
import '../../core/providers.dart';
import '../../core/stream_viewer.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation_sidebar.dart';
import '../../widgets/common.dart';
import '../../widgets/compact_navigation_shell.dart';
import '../../widgets/prism.dart';
import '../../widgets/scaffold/scaffold.dart' as app_scaffold;
import 'widgets/channel_pane.dart';
import 'widgets/channel_pane_resizer.dart';
import 'widgets/network_status.dart';
import 'workspace_page.dart';

/// 工作区统一的返回动作：优先退出已入栈路由，否则回到连接页且保留会话连接。
void navigateWorkspaceBack(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
  } else if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  } else if (router != null) {
    router.go(AppRoutes.connect);
  }
}

/// 工作区三栏布局；窄屏拆为一级「频道树」与二级「频道页」，彻底移除侧滑抽屉。
class WorkspaceShell extends ConsumerStatefulWidget {
  const WorkspaceShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell> {
  void _openChannelPage() {
    Navigator.of(context)
        .push(CardPageRoute<void>(builder: (_) => widget.child));
  }

  void _handleBackPop(bool didPop, Object? result) {
    if (didPop) {
      return;
    }
    if (ref.read(streamViewerProvider).isFullScreen) {
      unawaited(ref.read(streamViewerProvider.notifier).setFullScreen(false));
      return;
    }
    final tabScope = CompactRootTabScope.maybeOf(context);
    if (tabScope != null && tabScope.active && tabScope.activeTabIndex == 1) {
      tabScope.onExitToHome?.call();
      return;
    }
    navigateWorkspaceBack(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final l10n = AppLocalizations.of(context);
    final (
      :activeServerId,
      :activeServerLabel,
      :connected,
      :connecting,
      :reconnecting,
      :reconnectAttempt,
      :identityUpgradeTarget,
    ) = ref.watch(
      sessionViewProvider.select(
        (view) => (
          activeServerId: view.activeServerId,
          activeServerLabel: view.activeServer?.label,
          connected: view.connected,
          connecting: view.connecting,
          reconnecting: view.reconnecting,
          reconnectAttempt: view.reconnectAttempt,
          identityUpgradeTarget: view.identityUpgradeTarget,
        ),
      ),
    );
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < Breakpoints.compact;
    final panelColor = context.isDark
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;

    // 掉线重连期间每换一次尝试就在右上角刷新同一条提示；同一文案由
    // NoticeCenter 去重，不会叠成多张卡片。
    ref.listen<({bool reconnecting, int? attempt})>(
      sessionViewProvider.select(
        (view) =>
            (reconnecting: view.reconnecting, attempt: view.reconnectAttempt),
      ),
      (previous, next) {
        if (!next.reconnecting) {
          return;
        }
        if (previous?.reconnecting == true &&
            previous?.attempt == next.attempt) {
          return;
        }
        ref
            .read(noticeCenterProvider.notifier)
            .show(l10n.workspaceRetrying, tone: NoticeTone.info);
      },
    );

    /// 宽屏断开后回到服务器列表；窄屏原地退化为空状态页并保留根底栏。
    Future<void> disconnect() async {
      // 以 core 的断开结果为准，不读刚被事件改写的会话状态：广播是异步的，
      // 读状态可能抢在 Disconnected 事件之前。
      final disconnected = await ref
          .read(sessionViewProvider.notifier)
          .disconnect();
      if (disconnected && context.mounted && !compact) {
        context.go(AppRoutes.connect);
      }
    }

    // 设置页或连接页嵌在外壳里时，选中频道要回到工作区主区域。
    void selectChannel() {
      if (widget.location != AppRoutes.workspace) {
        context.go(AppRoutes.workspace);
      }
    }

    final compactWidth = AppNavigationSidebar.compactWidthOf(context);

    final Widget scaffold;
    if (compact) {
      final bottomDockInset = CompactBottomInsetScope.of(context);
      final Widget overviewPage;
      if (connecting || reconnecting) {
        overviewPage = app_scaffold.Scaffold(
          backgroundColor: context.pageColor,
          title: l10n.navWorkspace,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ActivityIndicator(size: 36),
                const SizedBox(height: 16),
                Text(
                  reconnecting
                      ? l10n.voiceReconnectingAttempt(reconnectAttempt ?? 1)
                      : l10n.sessionConnecting,
                  style: context.texts.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (!connected) {
        overviewPage = app_scaffold.Scaffold(
          backgroundColor: context.pageColor,
          title: l10n.navWorkspace,
          body: Builder(
            builder: (context) => Padding(
              padding: EdgeInsets.only(
                top: context.appBarInset,
                bottom: bottomDockInset + MediaQuery.paddingOf(context).bottom,
              ),
              child: EmptyState(
                icon: Icons.link_off_rounded,
                body: l10n.workspaceDropped,
              ),
            ),
          ),
        );
      } else {
        overviewPage = app_scaffold.Scaffold(
          backgroundColor: context.pageColor,
          titleWidget: _CompactOverviewTitle(
            serverLabel: activeServerLabel ?? l10n.navWorkspace,
          ),
          actions: [
            const _CompactMicButton(),
            const _CompactSpeakerButton(),
            _CompactDisconnectButton(
              onDisconnect: () => unawaited(disconnect()),
            ),
          ],
          body: Builder(
            builder: (context) => Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: EdgeInsets.only(top: context.appBarInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (identityUpgradeTarget != null)
                      WorkspaceIdentityBanner(
                        target: identityUpgradeTarget,
                        onCancel: ref
                            .read(sessionViewProvider.notifier)
                            .cancelIdentityUpgrade,
                      ),
                    const WorkspaceVoiceAlerts(),
                    Expanded(
                      child: ChannelPanel(
                        showHeader: false,
                        showUserFooter: false,
                        bottomInset:
                            bottomDockInset +
                            MediaQuery.paddingOf(context).bottom,
                        onChannelSelected: _openChannelPage,
                        onCompactDirectChat: _openChannelPage,
                        onCompactWatchStream: (_) => _openChannelPage(),
                        onShowChannelDetails: (channel) => unawaited(
                          showChannelDetailsSheet(context, channel),
                        ),
                        onShowChannelFiles: (channel) => unawaited(
                          showChannelFilesSheet(context, channel.id),
                        ),
                        onShowMemberDetails: (client) =>
                            unawaited(showMemberDetailsSheet(context, client)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      scaffold = overviewPage;
    } else {
      final rail = RepaintBoundary(
        child: AppNavigationSidebar(
          selectedDestination: AppNavDestination.server,
          activeServerId: activeServerId,
        ),
      );
      final panel = RepaintBoundary(
        child: ColoredBox(
          color: panelColor,
          child: ChannelPanel(
            onChannelSelected: selectChannel,
            onDisconnect: () => unawaited(disconnect()),
          ),
        ),
      );
      final surface = RepaintBoundary(
        child: _MainSurface(compact: compact, child: widget.child),
      );
      scaffold = Scaffold(
        backgroundColor: context.pageColor,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rail,
            Expanded(
              child: SidebarContentInset(
                hasSidebar: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ChannelPaneResizer(
                      // 分隔条自身也占地，算上限时一并扣掉，主区域不再被它挤穿。
                      maxWidth: math.max(
                        Sizes.channelPanelMin,
                        width -
                            compactWidth -
                            Sizes.mainPaneMin -
                            ChannelPaneResizer.handleWidth,
                      ),
                      child: panel,
                    ),
                    Expanded(child: surface),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBackPop,
      child: scaffold,
    );
  }
}

class _CompactOverviewTitle extends ConsumerWidget {
  const _CompactOverviewTitle({required this.serverLabel});

  final String serverLabel;

  Future<void> _openNetworkSheet(BuildContext context) {
    return showSheet<void>(
      context: context,
      builder: (sheetContext) => Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              NetworkTelemetryPanel(
                onClose: () => Navigator.of(sheetContext).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final (:connected, :network) = ref.watch(
      sessionViewProvider.select(
        (view) => (connected: view.connected, network: view.network),
      ),
    );
    final qualityColor = networkQualityColorOf(
      context,
      connected: connected,
      telemetry: network,
    );
    final pingText = network?.roundTripMs != null
        ? formatNetworkPing(l10n, network!.roundTripMs)
        : switch (networkQuality(network)) {
            NetworkQuality.unknown => l10n.networkMeasuring,
            _ => l10n.voiceConnected,
          };

    return Semantics(
      button: true,
      label: '$serverLabel · ${l10n.networkStatus}: $pingText',
      child: AnimatedInkWell(
        onTap: () => unawaited(_openNetworkSheet(context)),
        customBorder: AppShape.full,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  serverLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: context.raisedSurfaceColor,
                  shape: AppShape.full,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: ShapeDecoration(
                          color: qualityColor,
                          shape: AppShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 7),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        pingText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactMicButton extends ConsumerWidget {
  const _CompactMicButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final (:muted, :selfSpeaking) = ref.watch(
      sessionViewProvider.select(
        (view) => (muted: view.muted, selfSpeaking: view.selfSpeaking),
      ),
    );
    final foreground = muted
        ? scheme.onErrorContainer
        : selfSpeaking
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final background = muted
        ? scheme.errorContainer
        : selfSpeaking
        ? scheme.primaryContainer
        : null;
    return IconButton(
      onPressed: () =>
          unawaited(ref.read(sessionViewProvider.notifier).setMuted(!muted)),
      isSelected: muted || selfSpeaking,
      style: ButtonStyle.from(
        backgroundColor: background,
        foregroundColor: foreground,
      ),
      icon: Icon(
        muted ? Icons.mic_off_rounded : Icons.mic_rounded,
        size: IconSizes.toolbar,
        semanticLabel: muted ? l10n.voiceUnmute : l10n.voiceMute,
      ),
    );
  }
}

class _CompactSpeakerButton extends ConsumerWidget {
  const _CompactSpeakerButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final deafened = ref.watch(
      sessionViewProvider.select((view) => view.deafened),
    );
    return IconButton(
      onPressed: () => unawaited(
        ref.read(sessionViewProvider.notifier).setDeafened(!deafened),
      ),
      isSelected: deafened,
      style: deafened
          ? ButtonStyle.from(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
            )
          : null,
      icon: Icon(
        deafened ? Icons.headset_off_rounded : Icons.headphones_rounded,
        size: IconSizes.toolbar,
        semanticLabel: deafened ? l10n.voiceUndeafen : l10n.voiceDeafen,
      ),
    );
  }
}

class _CompactDisconnectButton extends ConsumerWidget {
  const _CompactDisconnectButton({required this.onDisconnect});

  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final busy = ref.watch(sessionViewProvider.select((view) => view.busy));
    return IconButton.filled(
      onPressed: busy ? null : onDisconnect,
      style: ButtonStyle.from(
        backgroundColor: scheme.error,
        foregroundColor: scheme.onError,
      ),
      icon: Icon(
        Icons.call_end_rounded,
        size: IconSizes.toolbar,
        semanticLabel: l10n.serverDisconnect,
      ),
    );
  }
}

/// 主内容区在桌面与导航分隔，顶栏直通窗口上沿。
class _MainSurface extends StatelessWidget {
  const _MainSurface({required this.compact, required this.child});

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Surface(
      color: context.pageColor,
      shape: AppShape.none,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
