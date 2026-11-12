import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/features/workspace/widgets/member_details_pane.dart';
import 'package:flspeak/features/workspace/widgets/channel_details_pane.dart';
import 'package:flspeak/features/workspace/widgets/members_pane.dart';
import 'package:flspeak/features/workspace/workspace_page.dart';
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
    activeServerId: 'server-1',
    clients: [_peer],
    channels: [
      ChannelView(id: 1, parentId: 0, name: 'Home', description: 'Home Topic'),
      ChannelView(id: 2, parentId: 0, name: 'Lobby', description: ''),
    ],
  );

  void updateClients(List<ClientView> clients) {
    state = state.copyWith(clients: clients);
  }

  void reconnect() {
    state = state.copyWith(connectionEpoch: state.connectionEpoch + 1);
  }
}

class _FakeCore extends Fake implements CoreSession {
  @override
  Future<void> queryPeerIdentity({required int targetClid}) async {}
  @override
  Future<Uint8List> fetchAvatar({required String uid}) async => Uint8List(0);
  @override
  Future<String> channelDescription({required int channelId}) async => '';
}

Future<ProviderContainer> _mountWorkspace(
  WidgetTester tester, {
  Widget? sidePanel,
}) async {
  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(_FakeCore()),
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
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sidePanel != null) sidePanel,
              const Expanded(child: WorkspacePage()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final channelTree in [true, false]) {
    testWidgets(
      '${channelTree ? 'channel tree' : 'members pane'} member highlights on hover and opens details in workspace pane without modal dialog',
      (tester) async {
        await _mountWorkspace(
          tester,
          sidePanel: SizedBox(
            width: 320,
            child: channelTree
                ? const ChannelPanel()
                : Consumer(
                    builder: (context, ref, child) => MembersPane(
                      view: ref.watch(sessionViewProvider),
                      channelId: 1,
                    ),
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

        // Primary click on member
        await tester.tap(find.text('Peer'));
        await tester.pumpAndSettle();

        // No modal dialog should pop up
        expect(find.byType(Dialog), findsNothing);

        // Details pane should be rendered in the main workspace
        expect(find.byType(MemberDetailsPane), findsOneWidget);
        expect(find.text('peer-uid'), findsOneWidget);
        expect(find.widgetWithText(SelectableText, 'Home'), findsOneWidget);
        expect(find.text('麦克风已静音'), findsOneWidget);
        expect(find.text('扬声器已静音'), findsOneWidget);
        expect(find.text('离开：Lunch'), findsOneWidget);

        // Clicking a channel should clear member details and switch to channel details
        if (channelTree) {
          await tester.tap(find.text('Lobby'));
          await tester.pumpAndSettle();
          expect(find.byType(MemberDetailsPane), findsNothing);
          expect(find.byType(ChannelDetailsPane), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'clicking messages tab after selecting member switches to direct chat with that member',
    (tester) async {
      final container = await _mountWorkspace(
        tester,
        sidePanel: const SizedBox(width: 320, child: ChannelPanel()),
      );

      // Tap member Peer
      await tester.tap(find.text('Peer'));
      await tester.pumpAndSettle();

      expect(find.byType(MemberDetailsPane), findsOneWidget);

      // Tap Messages tab (icon Icons.chat_bubble_rounded)
      final messagesTab = find.byIcon(Icons.chat_bubble_rounded);
      await tester.tap(messagesTab);
      await tester.pumpAndSettle();

      final session = container.read(sessionViewProvider);
      expect(session.chatScope, ChatScope.direct);
      expect(session.directRecipientUid, 'peer-uid');
      expect(session.directRecipientId, 2);
    },
  );

  testWidgets('details follow live member updates and show offline banner', (
    tester,
  ) async {
    final container = await _mountWorkspace(
      tester,
      sidePanel: const SizedBox(width: 320, child: ChannelPanel()),
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

    expect(find.text('Renamed'), findsWidgets);
    expect(find.text('麦克风已静音'), findsNothing);

    // Remove client from server
    controller.updateClients([]);
    await tester.pumpAndSettle();

    // Stays on member details pane with offline badge
    expect(find.byType(MemberDetailsPane), findsOneWidget);
    expect(find.text('该用户已离线'), findsOneWidget);
  });

  for (final client in [
    const ClientView(id: 1, nickname: 'Self', uid: 'self-uid', channelId: 1),
    const ClientView(id: 3, nickname: 'No UID', uid: '', channelId: 1),
  ]) {
    testWidgets('${client.nickname} can open details without a context menu', (
      tester,
    ) async {
      final container = await _mountWorkspace(
        tester,
        sidePanel: const SizedBox(width: 320, child: ChannelPanel()),
      );
      (container.read(sessionViewProvider.notifier) as _Controller)
          .updateClients([client]);
      await tester.pumpAndSettle();

      await tester.tap(find.text(client.nickname));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(MemberDetailsPane), findsOneWidget);
      expect(find.text(client.nickname), findsWidgets);
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
      final container = await _mountWorkspace(
        tester,
        sidePanel: const SizedBox(width: 320, child: ChannelPanel()),
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
      expect(find.text('chat:slash_commands'), findsOneWidget);
      expect(find.text('audio:stereo'), findsOneWidget);
    },
  );
}
