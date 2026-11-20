import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/connect/connect_page.dart';
import 'features/settings/settings_page.dart';
import 'features/workspace/workspace_page.dart';
import 'features/workspace/workspace_shell.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';
import 'widgets/compact_navigation_shell.dart';

abstract final class AppRoutes {
  /// 打开应用落在这里：身份 + 服务器列表。
  static const connect = '/connect';

  /// 进入之后的工作区，左侧固定是服务器栏。
  static const workspace = '/workspace';

  /// 整页设置。用 push 打开，返回时回到来路。
  static const settings = '/settings';
}

final rootNavigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return GlobalKey<NavigatorState>();
});

final routerProvider = Provider<GoRouter>((ref) {
  final navigatorKey = ref.watch(rootNavigatorKeyProvider);
  late final GoRouter router;
  router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: AppRoutes.connect,
    routes: [
      GoRoute(
        path: AppRoutes.connect,
        pageBuilder: (context, state) {
          final isRoot = _isRootMatch(router, state);
          if (!context.isCompact || !isRoot) {
            return _page(
              state,
              ConnectPage(serverId: state.uri.queryParameters['server']),
              // 宽屏根标签与 FlClash 一致直接跳转，不做路由转场。
              root: !context.isCompact,
            );
          }
          return _compactShellPage(
            state,
            location: AppRoutes.connect,
            serverId: state.uri.queryParameters['server'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) {
          final isRoot = _isRootMatch(router, state);
          if (!context.isCompact || !isRoot) {
            return _page(state, const SettingsPage());
          }
          return _compactShellPage(state, location: AppRoutes.settings);
        },
      ),
      GoRoute(
        path: AppRoutes.workspace,
        pageBuilder: (context, state) {
          final isRoot = _isRootMatch(router, state);
          if (!context.isCompact || !isRoot) {
            return _page(
              state,
              const WorkspaceShell(
                location: AppRoutes.workspace,
                child: WorkspacePage(),
              ),
              // 宽屏根标签与 FlClash 一致直接跳转，不做路由转场。
              root: !context.isCompact,
            );
          }
          return _compactShellPage(state, location: AppRoutes.workspace);
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

bool _isRootMatch(GoRouter router, GoRouterState state) {
  final matches = router.routerDelegate.currentConfiguration.matches;
  return matches.isEmpty || matches.first.pageKey == state.pageKey;
}

CustomTransitionPage<void> _compactShellPage(
  GoRouterState state, {
  required String location,
  String? serverId,
}) {
  return _page(
    state,
    CompactNavigationShell(location: location, serverId: serverId),
    key: const ValueKey<String>('compact-navigation-shell'),
  );
}

// go_router 的 material_ui.MaterialApp 与 SDK MaterialApp 是不同类型；
// 显式提供页面，避免默认检测回退到 NoTransitionPage。
CustomTransitionPage<void> _page(
  GoRouterState state,
  Widget child, {
  LocalKey? key,
  bool root = false,
}) {
  return CustomTransitionPage<void>(
    key: key ?? state.pageKey,
    transitionDuration: root ? Duration.zero : Motion.effectsDefault,
    reverseTransitionDuration: root ? Duration.zero : Motion.effectsFast,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final progress = animation.drive(
        CurveTween(curve: Motion.effectsDefaultCurve),
      );
      return FadeTransition(
        opacity: progress,
        child: SlideTransition(
          position: progress.drive(
            Tween(begin: const Offset(0, 0.02), end: Offset.zero),
          ),
          child: child,
        ),
      );
    },
  );
}
