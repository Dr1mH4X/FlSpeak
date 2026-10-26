import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';

import '../../router.dart';
import '../../theme/app_theme.dart';
import 'widgets/channel_pane.dart';
import 'widgets/channel_pane_resizer.dart';
import 'widgets/server_rail.dart';

/// 工作区外壳：左侧服务器栏 + 频道栏 + 主内容区，三栏通边铺满窗口。
///
/// 窗口圆角完全交给操作系统按系统偏好处理，应用不再自绘外框和留边；
/// 更窄时两栏收进抽屉，主区域占满宽度。设置入口属于服务器栏（左下角），
/// 不在频道栏底部。
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
    final view = ref.watch(sessionViewProvider);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < Breakpoints.compact;
    final panelColor = context.isDark
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;

    void selectServer(ServerProfileView server) {
      if (server.id == view.activeServerId && view.connected) {
        context.go(AppRoutes.workspace);
      } else {
        context.go(
          '${AppRoutes.connect}?server=${Uri.encodeComponent(server.id)}',
        );
      }
    }

    void addServer() => context.go(AppRoutes.connect);

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

    // 设置页可能被路由包进外壳：这种情况下按钮已经处于目标页，不再重复入栈。
    void openSettings() {
      if (location != AppRoutes.settings) {
        context.push(AppRoutes.settings);
      }
    }

    // 设置页或连接页嵌在外壳里时，选中频道要回到工作区主区域。
    void selectChannel() {
      if (location != AppRoutes.workspace) {
        context.go(AppRoutes.workspace);
      }
    }

    final rail = ServerRail(
      onSelect: selectServer,
      onAdd: addServer,
      onSettings: openSettings,
      onDisconnect: () => unawaited(disconnect()),
    );
    final panel = ChannelPanel(onChannelSelected: selectChannel);
    final surface = _MainSurface(compact: compact, child: child);

    if (compact) {
      return Scaffold(
        backgroundColor: scheme.surface,
        drawer: Drawer(
          width: math.min(ServerRail.width + Sizes.channelPanel, width - 24),
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
                    ServerRail.width -
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

/// 右侧主内容区：三栏之一，与窗口通边；窄屏铺满。
class _MainSurface extends StatelessWidget {
  const _MainSurface({required this.compact, required this.child});

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Material(
      // 三个分支都是实色面板：亮色半透明白在浅色底上会发灰，也和暗色
      // 分支的观感不一致。
      color: compact
          ? scheme.surface
          : context.isDark
          ? scheme.surfaceContainer
          : scheme.surfaceContainerLowest,
      child: child,
    );
  }
}
