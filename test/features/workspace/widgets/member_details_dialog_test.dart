import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/features/workspace/widgets/client_actions.dart';
import 'package:flspeak/features/workspace/widgets/members_pane.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';

const _peer = ClientView(
  id: 2,
  nickname: 'Peer',
  uid: 'peer-uid',
  channelId: 1,
  inputMuted: true,
  outputMuted: true,
  away: true,
  awayMessage: 'Lunch',
);

class _Controller extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 1),
    clients: [_peer],
    channels: [ChannelView(id: 1, parentId: 0, name: 'Home', description: '')],
  );

  void updateClients(List<ClientView> clients) {
    state = state.copyWith(clients: clients);
  }

  void reconnect() {
    state = state.copyWith(connectionEpoch: state.connectionEpoch + 1);
  }
}

Future<ProviderContainer> _mount(WidgetTester tester, Widget child) async {
  final container = ProviderContainer(
    overrides: [
      sessionViewProvider.overrideWith(_Controller.new),
      sessionAccessProvider.overrideWith((ref) async => const AccessView()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final channelTree in [true, false]) {
    testWidgets(
      '${channelTree ? 'channel tree' : 'members pane'} member highlights on hover and opens details on primary click',
      (tester) async {
        await _mount(
          tester,
          channelTree
              ? const SizedBox(width: 320, child: ChannelPanel())
              : Consumer(
                  builder: (context, ref, child) => MembersPane(
                    view: ref.watch(sessionViewProvider),
                    channelId: 1,
                  ),
                ),
        );
        final row = find.ancestor(
          of: find.text('Peer'),
          matching: find.byType(InkWell),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(row));
        await tester.pumpAndSettle();
        expect(
          tester.widget<InkWell>(row).statesController!.value,
          contains(WidgetState.hovered),
        );
        await mouse.removePointer();
        await tester.tap(find.text('Peer'));
        await tester.pumpAndSettle();
        expect(find.text('用户详情'), findsOneWidget);
        expect(find.text('peer-uid'), findsOneWidget);
        expect(find.widgetWithText(SelectableText, 'Home'), findsOneWidget);
        expect(find.widgetWithText(Chip, '麦克风已静音'), findsOneWidget);
        expect(find.widgetWithText(Chip, '扬声器已静音'), findsOneWidget);
        expect(find.widgetWithText(Chip, '离开：Lunch'), findsOneWidget);
      },
    );
  }

  testWidgets('details follow live member updates and stop at a new session', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      const ClientActionsButton(
        client: _peer,
        child: SizedBox(width: 240, height: 48, child: Text('Peer')),
      ),
    );
    await tester.tap(find.text('Peer'));
    await tester.pumpAndSettle();
    final controller =
        container.read(sessionViewProvider.notifier) as _Controller;
    controller.updateClients([
      const ClientView(
        id: 2,
        nickname: 'Renamed',
        uid: 'peer-uid',
        channelId: 1,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Renamed'), findsOneWidget);
    expect(find.widgetWithText(Chip, '麦克风已静音'), findsNothing);
    controller.reconnect();
    await tester.pumpAndSettle();
    expect(find.text('该用户已离线'), findsOneWidget);
    expect(find.text('Renamed'), findsNothing);
  });

  for (final client in [
    const ClientView(id: 1, nickname: 'Self', uid: 'self-uid', channelId: 1),
    const ClientView(id: 3, nickname: 'No UID', uid: '', channelId: 1),
  ]) {
    testWidgets('${client.nickname} can open details without a context menu', (
      tester,
    ) async {
      final container = await _mount(
        tester,
        ClientActionsButton(
          client: client,
          child: SizedBox(width: 240, height: 48, child: Text(client.nickname)),
        ),
      );
      (container.read(sessionViewProvider.notifier) as _Controller)
          .updateClients([client]);
      await tester.pumpAndSettle();
      await tester.tap(find.text(client.nickname));
      await tester.pumpAndSettle();
      expect(find.text('用户详情'), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, client.nickname),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'channel tree badges bot and FlSpeak clients with semantics and member details shows software and capabilities',
    (tester) async {
      const bot = ClientView(
        id: 10,
        nickname: 'MusicBot',
        uid: 'bot-uid',
        channelId: 1,
        clientType: ClientType.bot,
        appName: 'TsMusicBot',
        appVersion: '2.1.0',
        capabilities: ['chat:slash_commands', 'audio:stereo'],
      );
      const flspeakPeer = ClientView(
        id: 11,
        nickname: 'Alice',
        uid: 'alice-uid',
        channelId: 1,
        clientType: ClientType.flSpeak,
        appName: 'FlSpeak',
        appVersion: '0.1.12',
        capabilities: ['audio:stereo', 'stream:view'],
      );
      final container = await _mount(
        tester,
        const SizedBox(width: 320, child: ChannelPanel()),
      );
      (container.read(sessionViewProvider.notifier) as _Controller)
          .updateClients([bot, flspeakPeer]);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.smart_toy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.electric_bolt_rounded), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('机器人')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('FlSpeak 客户端')), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);

      await tester.tap(find.text('MusicBot'));
      await tester.pumpAndSettle();
      expect(find.text('客户端'), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, 'TsMusicBot v2.1.0'),
        findsOneWidget,
      );
      expect(find.widgetWithText(Chip, 'chat:slash_commands'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'audio:stereo'), findsOneWidget);
    },
  );
}
