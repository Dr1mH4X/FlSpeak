import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notices.dart';
import '../../core/providers.dart';
import '../../core/stream_viewer.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation_sidebar.dart';
import '../../widgets/prism.dart' show AppShape, Surface;
import 'widgets/channel_pane.dart';
import 'widgets/channel_pane_resizer.dart';

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

/// 工作区三栏布局；窄屏将服务器与频道收进抽屉。
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _handleBackPop(bool didPop, Object? result) {
    if (didPop) {
      return;
    }
    if (ref.read(streamViewerProvider).isFullScreen) {
      unawaited(ref.read(streamViewerProvider.notifier).setFullScreen(false));
      return;
    }
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
      return;
    }
    navigateWorkspaceBack(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final l10n = AppLocalizations.of(context);
    final activeServerId = ref.watch(
      sessionViewProvider.select((view) => view.activeServerId),
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

    /// 断开后回到服务器列表：工作区只剩空频道栏，
    /// 用户下一步能做的事全在连接页。
    Future<void> disconnect() async {
      // 以 core 的断开结果为准，不读刚被事件改写的会话状态：广播是异步的，
      // 读状态可能抢在 Disconnected 事件之前。
      final disconnected = await ref
          .read(sessionViewProvider.notifier)
          .disconnect();
      if (disconnected && context.mounted) {
        context.go(AppRoutes.connect);
      }
    }

    // 设置页或连接页嵌在外壳里时，选中频道要回到工作区主区域。
    void selectChannel() {
      if (widget.location != AppRoutes.workspace) {
        context.go(AppRoutes.workspace);
      }
    }

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

    final compactWidth = AppNavigationSidebar.compactWidthOf(context);

    final Widget scaffold;
    if (compact) {
      final isLtr = Directionality.of(context) == TextDirection.ltr;
      scaffold = Scaffold(
        key: _scaffoldKey,
        backgroundColor: context.pageColor,
        drawer: Drawer(
          width: math.min(compactWidth + Sizes.channelPanel, width - 24),
          backgroundColor: panelColor,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedSuperellipseBorder(
            borderRadius: BorderRadius.horizontal(
              right: Radius.circular(Radii.xxxl),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: !isLtr,
            removeRight: isLtr,
            child: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  rail,
                  Expanded(child: panel),
                ],
              ),
            ),
          ),
        ),
        body: surface,
      );
    } else {
      final blurOpacity = ref.watch(windowBlurOpacityProvider);
      scaffold = Scaffold(
        backgroundColor: blurOpacity != null
            ? Colors.transparent
            : context.pageColor,
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
