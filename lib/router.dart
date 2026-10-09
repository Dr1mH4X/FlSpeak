import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/connect/connect_page.dart';
import 'features/settings/settings_page.dart';
import 'features/workspace/workspace_page.dart';
import 'features/workspace/workspace_shell.dart';

abstract final class AppRoutes {
  /// 打开应用落在这里：录入地址、挑服务器、填昵称。
  static const connect = '/connect';

  /// 进入之后的工作区，左侧固定是服务器栏。
  static const workspace = '/workspace';
  static const settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.connect,
    routes: [
      GoRoute(
        path: AppRoutes.connect,
        builder: (context, state) =>
            ConnectPage(serverId: state.uri.queryParameters['server']),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            WorkspaceShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.workspace,
            builder: (context, state) => const WorkspacePage(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
