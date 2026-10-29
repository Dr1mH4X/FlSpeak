import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/connect/connect_page.dart';
import 'features/settings/settings_page.dart';
import 'features/workspace/workspace_page.dart';
import 'features/workspace/workspace_shell.dart';
import 'theme/app_motion.dart';

abstract final class AppRoutes {
  /// 打开应用落在这里：身份 + 服务器列表。
  static const connect = '/connect';

  /// 进入之后的工作区，左侧固定是服务器栏。
  static const workspace = '/workspace';

  /// 整页设置。用 push 打开，返回时回到来路。
  static const settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.connect,
    routes: [
      GoRoute(
        path: AppRoutes.connect,
        pageBuilder: (context, state) => _page(
          context,
          state,
          ConnectPage(serverId: state.uri.queryParameters['server']),
        ),
      ),
      GoRoute(
        path: AppRoutes.workspace,
        pageBuilder: (context, state) => _page(
          context,
          state,
          const WorkspaceShell(
            location: AppRoutes.workspace,
            child: WorkspacePage(),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) =>
            _page(context, state, const SettingsPage()),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

// go_router 的 material_ui.MaterialApp 与 SDK MaterialApp 是不同类型；
// 显式提供页面，避免默认检测回退到 NoTransitionPage。
CustomTransitionPage<void> _page(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: reduceMotion ? Duration.zero : Motion.effectsDefault,
    reverseTransitionDuration: reduceMotion
        ? Duration.zero
        : Motion.effectsFast,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
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
