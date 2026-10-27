// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/server_rail.dart';
import 'package:flspeak/features/workspace/workspace_shell.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/router.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 已连接快照；`disconnect` 只落状态，不走 FFI。
class _ConnectedController extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 7, channelId: 1),
    activeServerId: 's1',
    servers: [
      ServerProfileView(
        id: 's1',
        label: 'Studio',
        host: 'localhost',
        port: 9987,
      ),
    ],
    channels: [ChannelView(id: 1, parentId: 0, name: 'Lobby', description: '')],
    clients: [ClientView(id: 7, nickname: 'Me', uid: 'u7', channelId: 1)],
  );

  @override
  Future<bool> disconnect() async {
    state = const SessionView();
    return true;
  }
}

Future<GoRouter> _pumpShell(
  WidgetTester tester,
  _ConnectedController controller,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: AppRoutes.workspace,
    routes: [
      GoRoute(
        path: AppRoutes.workspace,
        builder: (context, state) => const WorkspaceShell(
          location: AppRoutes.workspace,
          child: Text('workspace'),
        ),
      ),
      GoRoute(
        path: AppRoutes.connect,
        builder: (context, state) => const Scaffold(body: Text('connect-page')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionViewProvider.overrideWith(() => controller)],
      child: MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('右键断开后回到服务器列表', (tester) async {
    final router = await _pumpShell(tester, _ConnectedController());
    expect(find.text('workspace'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(ServerRail),
        matching: find.text('Studio'),
      ),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('断开'));
    await tester.pumpAndSettle();

    expect(find.text('connect-page'), findsOneWidget);
    expect(router.state.uri.path, AppRoutes.connect);
  });

  testWidgets('长按服务器磁贴也能断开', (tester) async {
    final router = await _pumpShell(tester, _ConnectedController());
    expect(find.text('workspace'), findsOneWidget);

    await tester.longPress(
      find.descendant(
        of: find.byType(ServerRail),
        matching: find.text('Studio'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('断开'), findsOneWidget);

    await tester.tap(find.text('断开'));
    await tester.pumpAndSettle();

    expect(find.text('connect-page'), findsOneWidget);
    expect(router.state.uri.path, AppRoutes.connect);
  });

  testWidgets('服务器磁贴的语义节点保留点击与断开动作', (tester) async {
    await _pumpShell(tester, _ConnectedController());

    final tile = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Studio · localhost:9987 · 已连接',
    );
    expect(tile, findsOneWidget);
    final data = tester.getSemantics(tile).getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.customAction), isTrue);
  });
}
