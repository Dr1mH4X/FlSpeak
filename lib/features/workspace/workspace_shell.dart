import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/notices.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import 'widgets/channel_pane.dart';
import 'widgets/channel_pane_resizer.dart';
import '../../widgets/app_navigation_sidebar.dart';

/// 工作区三栏布局；窄屏将服务器与频道收进抽屉。
class WorkspaceShell extends ConsumerWidget {
  const WorkspaceShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.scheme;
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < Breakpoints.compact;
    final panelColor = context.isDark
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;

    // 掉线重连期间每换一次尝试就在右上角刷新同一条提示；同一文案由
    // NoticeCenter 去重，不会叠成多张卡片。
    ref.listen<SessionView>(sessionViewProvider, (previous, next) {
      if (!next.reconnecting) {
        return;
      }
      if (previous?.reconnecting == true &&
          previous?.reconnectAttempt == next.reconnectAttempt) {
        return;
      }
      ref
          .read(noticeCenterProvider.notifier)
          .show(l10n.workspaceRetrying, tone: NoticeTone.info);
    });

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
      if (location != AppRoutes.workspace) {
        context.go(AppRoutes.workspace);
      }
    }

    final rail = AppNavigationSidebar(
      selectedDestination: AppNavDestination.server,
      activeServerId: view.activeServerId,
    );
    final panel = ChannelPanel(
      onChannelSelected: selectChannel,
      onDisconnect: () => unawaited(disconnect()),
    );
    final surface = _MainSurface(compact: compact, child: child);

    if (compact) {
      return Scaffold(
        backgroundColor: scheme.surface,
        drawer: Drawer(
          width: math.min(
            AppNavigationSidebar.compactWidth + Sizes.channelPanel,
            width - 24,
          ),
          backgroundColor: panelColor,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(
              right: Radius.circular(Radii.xxxl),
            ),
          ),
          clipBehavior: Clip.antiAlias,
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
        body: SafeArea(child: surface),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rail,
            ChannelPaneResizer(
              // 分隔条自身也占地，算上限时一并扣掉，主区域不再被它挤穿。
              maxWidth: math.max(
                Sizes.channelPanelMin,
                width -
                    AppNavigationSidebar.compactWidth -
                    Sizes.mainPaneMin -
                    ChannelPaneResizer.handleWidth,
              ),
              child: panel,
            ),
            Expanded(child: surface),
          ],
        ),
      ),
    );
  }
}

/// 主内容区在桌面以圆角与导航分隔，窄屏铺满。
class _MainSurface extends StatelessWidget {
  const _MainSurface({required this.compact, required this.child});

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Material(
      color: scheme.surface,
      borderRadius: compact
          ? BorderRadius.zero
          : const BorderRadius.only(topLeft: Radius.circular(Radii.xxl)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
