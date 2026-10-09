import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/connect/connect_page.dart';
import 'package:flspeak/l10n/app_localizations.dart';

import 'support/stub_session.dart';

const _home = ServerProfileView(
  id: 'ts.example.com:9987',
  label: 'home',
  host: 'ts.example.com',
  port: 9987,
);

Widget _app(SessionView view, {String? serverId}) => ProviderScope(
  overrides: [
    sessionViewProvider.overrideWith(() => StubSessionController(view)),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: ConnectPage(serverId: serverId),
  ),
);

void main() {
  testWidgets('打开时是连接界面：地址录入 + 已登记列表为空时的指引', (tester) async {
    await tester.pumpWidget(_app(const SessionView()));

    expect(find.text('FlSpeak'), findsOneWidget);
    expect(find.text('Connect to a server'), findsNothing);
    expect(find.text('Register a new server'), findsOneWidget);
    // 地址至少有一个可见标签，且按钮说明它会登记这台服务器。
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Add server'), findsWidgets);
    expect(
      find.text(
        'No server yet. Type an address above to register the first one.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('列出已登记的服务器，连接中的那台标成已连接', (tester) async {
    await tester.pumpWidget(
      _app(
        const SessionView(
          servers: [_home],
          activeServerId: 'ts.example.com:9987',
          state: CoreSessionState_Connected(clientId: 7, channelId: 1),
        ),
      ),
    );

    expect(find.text('home'), findsOneWidget);
    expect(find.text('ts.example.com:9987'), findsOneWidget);
    expect(find.text('Connected'), findsWidgets);
    // 已连接时可以直接回到工作区。
    expect(find.text('Back to workspace'), findsOneWidget);
  });

  testWidgets('点服务器卡片进入昵称步骤，只差昵称就能连接', (tester) async {
    await tester.pumpWidget(_app(const SessionView(servers: [_home])));

    await tester.tap(find.text('home'));
    await tester.pumpAndSettle();

    expect(find.text('Nickname'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    // 地址属于档案，昵称步骤里不再出现地址输入。
    expect(find.text('Server address'), findsNothing);
  });

  testWidgets('从服务器栏带 server 参数进来时直接落在昵称步骤', (tester) async {
    await tester.pumpWidget(
      _app(const SessionView(servers: [_home]), serverId: _home.id),
    );

    expect(find.text('Nickname'), findsOneWidget);
    expect(find.text('Register a new server'), findsNothing);
  });

  testWidgets('地址为空时给出字段级错误，不发请求', (tester) async {
    final controller = StubSessionController(const SessionView());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionViewProvider.overrideWith(() => controller)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: ConnectPage(),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add server'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid server address.'), findsOneWidget);
    expect(controller.registered, isEmpty);
  });
}
