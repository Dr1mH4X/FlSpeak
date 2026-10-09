import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/workspace_page.dart';
import 'package:flspeak/features/workspace/workspace_shell.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';

import 'support/stub_session.dart';

const _home = ServerProfileView(
  id: 'ts.example.com:9987',
  label: 'home',
  host: 'ts.example.com',
  port: 9987,
);

const _work = ServerProfileView(
  id: 'voice.example.org:9987',
  label: 'work',
  host: 'voice.example.org',
  port: 9987,
);

SessionView _view({
  ChatScope scope = ChatScope.channel,
  List<ChatMessage> messages = const [],
}) => SessionView(
  state: const CoreSessionState_Connected(clientId: 7, channelId: 2),
  servers: const [_home, _work],
  activeServerId: _home.id,
  channels: const [
    ChannelView(id: 1, parentId: 0, name: 'Lobby', description: ''),
    ChannelView(id: 2, parentId: 1, name: 'Talk', description: ''),
  ],
  clients: const [
    ClientView(id: 7, nickname: 'me', uid: 'uid-me', channelId: 2),
    ClientView(id: 8, nickname: 'alice', uid: 'uid-alice', channelId: 2),
  ],
  chatScope: scope,
  messages: messages,
);

Future<StubSessionController> _pumpShell(
  WidgetTester tester,
  SessionView view, {
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final controller = StubSessionController(view);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionViewProvider.overrideWith(() => controller)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildAppTheme(Brightness.dark),
        home: const WorkspaceShell(
          location: '/workspace',
          child: WorkspacePage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('侧栏是服务器栏：每台服务器 + 添加 + 设置，连接中的那台被标出', (tester) async {
    await _pumpShell(tester, _view());

    expect(find.text('Servers'), findsOneWidget);
    expect(find.text('home'), findsWidgets);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('Add server'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    // 连接中的服务器在侧栏显示为已连接。
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('右侧主界面同时有频道列表和聊天栏', (tester) async {
    await _pumpShell(tester, _view());

    expect(find.text('Channels'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    // 频道树：父频道 + 子频道，子频道缩进在父频道之下。
    expect(find.text('Lobby'), findsOneWidget);
    expect(find.text('Talk'), findsOneWidget);
    // 同频道的成员列在频道下面。
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('me'), findsOneWidget);
  });

  testWidgets('未连接时主界面给出下一步，而不是空白', (tester) async {
    await _pumpShell(
      tester,
      const SessionView(
        servers: [_home],
        channels: [
          ChannelView(id: 1, parentId: 0, name: 'Lobby', description: ''),
        ],
      ),
    );

    expect(find.text('Not connected'), findsOneWidget);
    expect(
      find.text(
        'Pick a registered server from the bar on the left, or add a new address.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Connect to a server'),
      findsOneWidget,
    );
    // 服务器栏仍在，服务器管理入口不随连接状态消失。
    expect(find.text('Add server'), findsOneWidget);
  });

  testWidgets('点频道行会请求加入该频道', (tester) async {
    final controller = await _pumpShell(tester, _view());

    await tester.tap(find.text('Lobby'));
    await tester.pumpAndSettle();

    expect(controller.joined, [1]);
  });

  testWidgets('聊天栏发出的是本频道的消息', (tester) async {
    final controller = await _pumpShell(tester, _view());

    await tester.enterText(find.byType(TextField).last, 'hello');
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    await tester.pumpAndSettle();

    expect(controller.sent, ['hello']);
  });

  testWidgets('切到整个服务器范围能发出广播消息', (tester) async {
    final controller = await _pumpShell(tester, _view());

    await tester.tap(find.text('Whole server'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'server wide');
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    await tester.pumpAndSettle();

    expect(controller.sent, ['server wide']);
  });

  testWidgets('消息流按投递范围过滤，自己的消息不显示昵称', (tester) async {
    await _pumpShell(
      tester,
      _view(
        messages: [
          ChatMessage(
            from: 'alice',
            fromUid: 'uid-alice',
            text: 'hi there',
            at: DateTime(2026, 10, 8, 14),
            scope: ChatScope.channel,
            targetId: 2,
          ),
          ChatMessage(
            from: 'me',
            fromUid: 'uid-me',
            text: 'mine',
            at: DateTime(2026, 10, 8, 14, 1),
            scope: ChatScope.channel,
            targetId: 2,
          ),
          ChatMessage(
            from: 'bob',
            fromUid: 'uid-bob',
            text: 'other channel',
            at: DateTime(2026, 10, 8, 14, 2),
            scope: ChatScope.channel,
            targetId: 99,
          ),
        ],
      ),
    );

    expect(find.text('hi there'), findsOneWidget);
    expect(find.text('mine'), findsOneWidget);
    // 别的频道的消息不进来。
    expect(find.text('other channel'), findsNothing);
    // 别人的消息带昵称，自己的只带时间。
    expect(find.text('alice'), findsWidgets);
    expect(find.text('me'), findsOneWidget);
  });

  testWidgets('未进入频道时频道消息被禁用并说明原因', (tester) async {
    await _pumpShell(
      tester,
      _view().copyWith(
        state: const CoreSessionState_Connected(clientId: 7, channelId: 0),
      ),
    );

    expect(
      find.text('Join a channel before sending channel messages.'),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.enabled, isFalse);
  });

  testWidgets('窄屏收成一栏，用分段控件在频道与聊天之间切换', (tester) async {
    await _pumpShell(tester, _view(), size: const Size(600, 900));

    // 频道是默认栏。
    expect(find.text('Lobby'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('hi'), findsNothing);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    // 切到聊天后频道树让位。
    expect(find.text('Lobby'), findsNothing);
  });
}
