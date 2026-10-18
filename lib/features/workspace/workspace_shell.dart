import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'widgets/channel_pane.dart';
import 'widgets/server_rail.dart';

/// 工作区外壳：左侧服务器栏 + 频道栏，右侧内容卡片。
///
/// 宽度达到 [Breakpoints.compact] 时两栏固定展开；更窄时收进抽屉，
/// 主区域占满宽度。设置入口属于服务器栏（左下角），不在频道栏底部。
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
    final notice = view.notice;
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
    );
    final panel = ChannelPanel(onChannelSelected: selectChannel);
    final surface = _MainSurface(
      compact: compact,
      notice: notice,
      onDismissNotice: ref.read(sessionViewProvider.notifier).dismissNotice,
      child: child,
    );

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
            SizedBox(width: Sizes.channelPanel, child: panel),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                child: surface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 右侧主内容卡片：桌面端浮在页面底色上，窄屏铺满。
class _MainSurface extends StatelessWidget {
  const _MainSurface({
    required this.compact,
    required this.child,
    required this.notice,
    required this.onDismissNotice,
  });

  final bool compact;
  final Widget child;
  final String? notice;
  final VoidCallback onDismissNotice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return Material(
      color: compact
          ? scheme.surface
          : context.isDark
          ? scheme.surfaceContainer
          : scheme.surfaceContainerLowest.withValues(alpha: 0.6),
      borderRadius: compact ? null : Radii.xxxlAll,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: NoticeBar(
                message: notice!,
                dismissTooltip: l10n.commonClose,
                onDismiss: onDismissNotice,
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
