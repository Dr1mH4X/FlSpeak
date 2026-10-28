// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/notices.dart';
import 'package:flspeak/features/workspace/widgets/client_actions.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/chat_pane.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(
  WidgetTester tester,
  bool Function() done,
  String label,
) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  fail('Timed out: $label');
}

Widget ui(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildAppTheme(Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: Consumer(
      builder: (context, ref, child) {
        final view = ref.watch(sessionViewProvider);
        final ctl = ref.read(sessionViewProvider.notifier);
        final peer = view.clients
            .where(
              (client) =>
                  client.uid == view.directRecipientUid &&
                  client.id != view.selfClientId,
            )
            .firstOrNull;
        return Scaffold(
          body: Column(
            children: [
              if (peer != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: ClientActionsButton(client: peer),
                ),
              Expanded(
                child: ChatPane(
                  channelName: 'audit',
                  messages: view.visibleMessages(),
                  scope: view.chatScope,
                  canSendChannel: view.connected,
                  busy: view.busy,
                  onScopeChanged: ctl.selectChatScope,
                  onSend: ctl.prepareMessageSender(),
                  recipients: view.clients
                      .where(
                        (peer) =>
                            peer.id != view.selfClientId && peer.uid.isNotEmpty,
                      )
                      .toList(),
                  selfUid: view.selfUid,
                  recipientUid: view.directRecipientUid,
                  onRecipientChanged: ctl.selectDirectRecipient,
                  onReply: ctl.replyToMessage,
                ),
              ),
            ],
          ),
        );
      },
    ),
  ),
);

const _server = String.fromEnvironment('FLSPEAK_LIVE_SERVER');
const _library = String.fromEnvironment('FLSPEAK_NATIVE_LIBRARY');

void main() {
  setUpAll(() async {
    if (_library.isNotEmpty) {
      await RustLib.init(externalLibrary: ExternalLibrary.open(_library));
    }
  });
  testWidgets('two temporary clients use real FFI and private UI reply', (
    tester,
  ) async {
    late Directory dir;
    Directory? cleanupDir;
    final sessions = <CoreSession>[];
    final containers = <ProviderContainer>[];
    final profiles = <ServerProfileView>[];
    final suffix = DateTime.now().millisecondsSinceEpoch;
    final names = [
      'FLS-PM-A-${suffix % 100000}',
      'FLS-PM-B-${suffix % 100000}',
    ];
    try {
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('flspeak-private-ui-');
        cleanupDir = dir;
        for (var i = 0; i < 2; i++) {
          final core = CoreSession(
            storePath: '${dir.path}/$i/servers.json',
            audioEnabled: false,
          );
          sessions.add(core);
          await core.setAutoReconnect(enabled: false);
          profiles.add(
            await core.registerServer(label: 'private-test', address: _server),
          );
        }
      });
      for (var i = 0; i < 2; i++) {
        containers.add(
          ProviderContainer(
            overrides: [
              coreSessionProvider.overrideWithValue(sessions[i]),
              storePathProvider.overrideWithValue(
                '${dir.path}/$i/servers.json',
              ),
              preferencesStoreProvider.overrideWithValue(
                PreferencesStore.inMemory(
                  preferences: SessionPreferences(
                    nickname: names[i],
                    locale: 'zh',
                  ),
                ),
              ),
            ],
          ),
        );
      }
      final a = containers[0].read(sessionViewProvider.notifier);
      final b = containers[1].read(sessionViewProvider.notifier);
      await tester.runAsync(() async {
        expect(await a.connect(id: profiles[0].id, nickname: names[0]), isTrue);
        expect(await b.connect(id: profiles[1].id, nickname: names[1]), isTrue);
        await a.refresh();
        await b.refresh();
      });
      SessionView av() => containers[0].read(sessionViewProvider);
      SessionView bv() => containers[1].read(sessionViewProvider);
      await until(
        tester,
        () =>
            av().selfUid.isNotEmpty &&
            bv().selfUid.isNotEmpty &&
            av().clients.any((p) => p.uid == bv().selfUid) &&
            bv().clients.any((p) => p.uid == av().selfUid),
        'both private identities visible',
      );
      final aid = av().selfClientId!, bid = bv().selfClientId!;
      final auid = av().selfUid, buid = bv().selfUid;
      debugPrint('temporary A=$aid B=$bid; both UID mappings present');
      await tester.pumpWidget(ui(containers[0]));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(names[1]));
      await tester.pumpAndSettle();
      expect(av().chatScope, ChatScope.direct);
      expect(av().directRecipientUid, buid);
      final first = 'FLS private UI $suffix: 你好 🌍 | \\\nsecond line';
      await tester.enterText(find.byType(TextField), first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await until(
        tester,
        () =>
            !av().busy &&
            av().messages.any((m) => m.text == first) &&
            bv().messages.any((m) => m.text == first),
        'A UI send delivered and echoed',
      );
      final received = bv().messages.singleWhere((m) => m.text == first);
      expect(received.fromUid, auid);
      expect(received.scope, ChatScope.direct);
      expect(received.targetId, bid);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      debugPrint('A picker -> B: real private message and sender echo passed');
      await tester.pumpWidget(ui(containers[1]));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.reply_rounded));
      await tester.pumpAndSettle();
      expect(bv().chatScope, ChatScope.direct);
      expect(bv().directRecipientUid, auid);
      final reply = 'FLS private reply $suffix: 收到 ✅';
      await tester.enterText(find.byType(TextField), reply);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await until(
        tester,
        () =>
            !bv().busy &&
            av().messages.any((m) => m.text == reply) &&
            bv().messages.any((m) => m.text == reply),
        'B reply UI delivered and echoed',
      );
      final back = av().messages.singleWhere((m) => m.text == reply);
      expect(back.fromUid, buid);
      expect(back.scope, ChatScope.direct);
      expect(back.targetId, aid);
      debugPrint('B Reply -> A: real private reply passed');
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('戳一下'));
      await tester.pumpAndSettle();
      final poke = 'FLS live poke $suffix';
      await tester.enterText(find.byType(TextField).last, poke);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '戳一下'));
      await until(
        tester,
        () => containers[0]
            .read(noticeCenterProvider)
            .any((notice) => notice.message.contains(poke)),
        'A receives UI poke from B',
      );
      final otherPoke = 'FLS return poke $suffix';
      final poked = await tester.runAsync(() => a.pokeClient(buid, otherPoke));
      expect(poked, isTrue);
      await until(
        tester,
        () => containers[1]
            .read(noticeCenterProvider)
            .any((notice) => notice.message.contains(otherPoke)),
        'B receives return poke',
      );
      final histories = await tester.runAsync(
        () async => [
          for (var i = 0; i < 2; i++)
            await File('${dir.path}/$i/messages.jsonl').readAsString(),
        ],
      );
      for (final history in histories!) {
        final records = history
            .trim()
            .split('\n')
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        expect(records.any((row) => row['message'] == first), isTrue);
        expect(records.any((row) => row['message'] == reply), isTrue);
      }
      await tester.runAsync(() async {
        await sessions[1].disconnect();
        await a.refresh();
      });
      await until(
        tester,
        () => av().directRecipient == null,
        'departed peer invalidates private target',
      );
      final rejected = await tester.runAsync(
        () => a.sendMessage('offline-canary-never-transmitted'),
      );
      expect(rejected, isFalse);
      debugPrint(
        'offline target rejected locally; histories contain both private messages',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.runAsync(() async {
        for (final core in sessions) {
          await core.disconnect();
          await core.shutdown();
        }
      });
      await tester.pumpWidget(const SizedBox.shrink());
      for (final container in containers) {
        container.dispose();
      }
      await tester.runAsync(() async {
        if (cleanupDir != null && await cleanupDir!.exists()) {
          await cleanupDir!.delete(recursive: true);
        }
      });
    }
  }, skip: _server.isEmpty || _library.isEmpty);
  test(
    'real Rust upload enforces the HTTP contract and rejects redirects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests =
          <
            ({
              String path,
              String method,
              String? authorization,
              String? contentType,
              List<int> bytes,
            })
          >[];
      final subscription = server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        requests.add((
          path: request.uri.path,
          method: request.method,
          authorization: request.headers.value(HttpHeaders.authorizationHeader),
          contentType: request.headers.contentType?.mimeType,
          bytes: bytes,
        ));
        request.response.statusCode = request.uri.path.startsWith('/redirect/')
            ? 302
            : 201;
        if (request.response.statusCode == 302) {
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/unexpected',
          );
        }
        await request.response.close();
      });
      try {
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIcznzHwAFAAJ2x7r4FgAAAABJRU5ErkJggg==',
        );
        final root = 'http://127.0.0.1:${server.port}';
        final url = await uploadImage(
          uploadBase: '$root/upload/',
          publicBase: 'https://images.example.com/public/',
          token: 'fixture-token',
          bytes: bytes,
        );
        expect(url, startsWith('https://images.example.com/public/'));
        expect(url, endsWith('.png'));
        expect(requests.single.method, 'PUT');
        expect(requests.single.bytes, bytes);
        expect(requests.single.authorization, 'Bearer fixture-token');
        expect(requests.single.contentType, 'image/png');
        await expectLater(
          uploadImage(
            uploadBase: '$root/redirect/',
            publicBase: 'https://images.example.com/public/',
            token: 'fixture-token',
            bytes: bytes,
          ),
          throwsA(isA<CoreError>()),
        );
        expect(requests, hasLength(2));
        expect(
          requests.any((request) => request.path == '/unexpected'),
          isFalse,
        );
        await expectLater(
          uploadImage(
            uploadBase: '$root/upload/',
            publicBase: 'https://images.example.com/public/',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
          throwsA(isA<CoreError>()),
        );
        expect(requests, hasLength(2));
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    },
    skip: _library.isEmpty,
  );
}
