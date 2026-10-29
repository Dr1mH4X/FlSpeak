// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/models.dart';
import '../../../core/image_host.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import 'chat_pane.dart';

class _ChatHarness extends StatefulWidget {
  const _ChatHarness({this.pick, this.upload, this.send, super.key});
  final Future<PickedChatImage?> Function()? pick;
  final Future<String?> Function(Uint8List)? upload;
  final Future<bool> Function(String, String)? send;
  @override
  State<_ChatHarness> createState() => _ChatHarnessState();
}

class _ChatHarnessState extends State<_ChatHarness> {
  String recipient = 'alice';
  List<ChatMessage> messages = [];
  void select(String uid) => setState(() => recipient = uid);
  void replaceMessages(List<ChatMessage> value) =>
      setState(() => messages = value);
  @override
  Widget build(BuildContext context) {
    final target = recipient;
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChatPane(
          channelName: 'Lobby',
          messages: messages,
          scope: ChatScope.direct,
          canSendChannel: true,
          busy: false,
          selfUid: 'self',
          selfClientId: 1,
          recipients: const [
            ClientView(id: 2, nickname: 'Alice', uid: 'alice', channelId: 5),
            ClientView(id: 3, nickname: 'Bob', uid: 'bob', channelId: 5),
          ],
          recipientUid: target,
          recipientId: target == 'alice' ? 2 : 3,
          onRecipientChanged: select,
          onReply: (_) {},
          onScopeChanged: (_) {},
          onSend: (text) =>
              widget.send?.call(target, text) ?? Future.value(true),
          onPickImage: widget.pick,
          onUploadImage: widget.upload,
        ),
      ),
    );
  }
}

PickedChatImage _picked() => PickedChatImage(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIcznzHwAFAAJ2x7r4FgAAAABJRU5ErkJggg==',
  ),
  name: 'picked.png',
);

void main() {
  testWidgets('private recipients keep separate drafts', (tester) async {
    final key = GlobalKey<_ChatHarnessState>();
    await tester.pumpWidget(_ChatHarness(key: key));
    await tester.enterText(find.byType(TextField).last, 'for Alice');
    key.currentState!.select('bob');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '',
    );
    await tester.enterText(find.byType(TextField).last, 'for Bob');
    key.currentState!.select('alice');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'for Alice',
    );
    key.currentState!.select('bob');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'for Bob',
    );
  });

  testWidgets('late image selection belongs to the original recipient', (
    tester,
  ) async {
    final key = GlobalKey<_ChatHarnessState>();
    final picked = Completer<PickedChatImage?>();
    await tester.pumpWidget(_ChatHarness(key: key, pick: () => picked.future));
    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择图片'));
    await tester.pump();
    key.currentState!.select('bob');
    await tester.pump();
    picked.complete(_picked());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    key.currentState!.select('alice');
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
    'switching target during upload keeps its cached image and cannot send it to the new target',
    (tester) async {
      final key = GlobalKey<_ChatHarnessState>();
      final upload = Completer<String?>();
      var uploads = 0;
      final sent = <(String, String)>[];
      await tester.pumpWidget(
        _ChatHarness(
          key: key,
          pick: () async => _picked(),
          upload: (_) {
            uploads++;
            return upload.future;
          },
          send: (target, text) async {
            sent.add((target, text));
            return true;
          },
        ),
      );
      await tester.enterText(find.byType(TextField).last, 'caption');
      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      key.currentState!.select('bob');
      await tester.pump();
      upload.complete('https://images.example.com/picked.png');
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(find.byType(Image), findsNothing);
      key.currentState!.select('alice');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(uploads, 1);
      expect(sent.single, (
        'alice',
        'caption\n![](<https://images.example.com/picked.png>)',
      ));
    },
  );

  testWidgets('a completed send clears its inactive draft', (tester) async {
    final key = GlobalKey<_ChatHarnessState>();
    final reply = Completer<bool>();
    await tester.pumpWidget(
      _ChatHarness(key: key, send: (_, text) => reply.future),
    );
    await tester.enterText(find.byType(TextField).last, 'already sent');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    key.currentState!.select('bob');
    await tester.pump();
    reply.complete(true);
    await tester.pumpAndSettle();
    key.currentState!.select('alice');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '',
    );
  });

  testWidgets(
    'incoming chat preserves history reading and follows capped history while at the bottom',
    (tester) async {
      final key = GlobalKey<_ChatHarnessState>();
      ChatMessage message(int id, {String? text}) => ChatMessage(
        from: 'Alice',
        fromUid: 'alice',
        fromId: 2,
        text: text ?? 'message $id',
        at: DateTime.utc(2026, 1, 1).add(Duration(seconds: id)),
        scope: ChatScope.direct,
        targetId: 1,
      );
      await tester.pumpWidget(_ChatHarness(key: key));
      var messages = List.generate(40, (index) => message(index));
      key.currentState!.replaceMessages(messages);
      await tester.pumpAndSettle();
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      scroll.jumpTo(0);
      await tester.pump();
      messages = [...messages, message(40)];
      key.currentState!.replaceMessages(messages);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      key.currentState!.replaceMessages([
        ...messages.skip(1),
        message(41, text: List.filled(12, 'long message').join('\n')),
      ]);
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(1));

      key.currentState!.replaceMessages([
        ...messages,
        message(42, text: List.filled(16, 'another long message').join('\n')),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, greaterThan(72));
    },
  );

  testWidgets(
    'pending send cannot duplicate; failure retains draft; success clears it',
    (tester) async {
      var response = Completer<bool>();
      var sends = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatPane(
              channelName: 'Lobby',
              messages: const [],
              scope: ChatScope.channel,
              canSendChannel: true,
              busy: false,
              selfUid: 'self',
              recipients: const [],
              recipientUid: null,
              onRecipientChanged: (_) {},
              onReply: (_) {},
              onScopeChanged: (_) {},
              onSend: (_) {
                sends++;
                return response.future;
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'unsent draft');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.controller!.text, 'unsent draft');
      expect(input.enabled, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.send_rounded),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(sends, 1);
      response.complete(false);
      await tester.pumpAndSettle();
      expect(input.controller!.text, 'unsent draft');
      response = Completer<bool>();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      response.complete(true);
      await tester.pumpAndSettle();
      expect(input.controller!.text, '');
      expect(sends, 2);
    },
  );

  testWidgets(
    'recipient picker names the private target and channel description is visible',
    (tester) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatPane(
              channelName: 'Lobby',
              description: 'Channel introduction',
              messages: const [],
              scope: ChatScope.direct,
              canSendChannel: false,
              busy: false,
              selfUid: 'self',
              recipients: const [
                ClientView(id: 2, nickname: 'Peer', uid: 'peer', channelId: 1),
              ],
              recipientUid: 'peer',
              onRecipientChanged: (uid) => chosen = uid,
              onReply: (_) {},
              onScopeChanged: (_) {},
              onSend: (_) async => true,
            ),
          ),
        ),
      );
      expect(find.text('Channel introduction'), findsOneWidget);
      expect(find.text('发送到 Peer'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.person_rounded));
      await tester.pumpAndSettle();
      // 用户选项默认收起，点击展开后方可选中对应私聊成员。
      await tester.tap(find.text('私聊'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Peer'));
      await tester.pumpAndSettle();
      expect(chosen, 'peer');
    },
  );

  testWidgets('scope picker direct recipient list is collapsed by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatPane(
            channelName: 'Lobby',
            messages: const [],
            scope: ChatScope.channel,
            canSendChannel: true,
            busy: false,
            selfUid: 'self',
            recipients: const [
              ClientView(id: 2, nickname: 'Alice', uid: 'alice', channelId: 1),
            ],
            recipientUid: null,
            onRecipientChanged: (_) {},
            onReply: (_) {},
            onScopeChanged: (_) {},
            onSend: (_) async => true,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
    await tester.pumpAndSettle();

    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect(tile.initiallyExpanded, isFalse);
    expect(find.text('Alice'), findsNothing);

    await tester.tap(find.text('私聊'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
  });
  testWidgets(
    'image send preserves uploaded URL and draft on failure; retry does not upload twice',
    (tester) async {
      final image = PickedChatImage(
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIcznzHwAFAAJ2x7r4FgAAAABJRU5ErkJggg==',
        ),
        name: 'picked.png',
      );
      var uploads = 0;
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatPane(
              channelName: 'Lobby',
              messages: const [],
              scope: ChatScope.channel,
              canSendChannel: true,
              busy: false,
              selfUid: 'self',
              recipients: const [],
              recipientUid: null,
              onRecipientChanged: (_) {},
              onReply: (_) {},
              onScopeChanged: (_) {},
              onPickImage: () async => image,
              onUploadImage: (bytes) async {
                uploads++;
                return 'https://images.example.com/object.png';
              },
              onSend: (text) async {
                sent.add(text);
                return sent.length > 1;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择图片'));
      await tester.pump();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(image.bytes),
          tester.element(find.byType(Scaffold)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('picked.png'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'caption');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.text('picked.png'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'caption',
      );
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(uploads, 1);
      expect(sent, hasLength(2));
      expect(sent[0], sent[1]);
      expect(sent[1], 'caption\n![](<https://images.example.com/object.png>)');
      expect(find.text('picked.png'), findsNothing);
    },
  );

  testWidgets(
    'long channel name falls back to generic channel hint without growing composer height',
    (tester) async {
      Widget buildPane(String channelName) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 600,
            child: ChatPane(
              channelName: channelName,
              messages: const [],
              scope: ChatScope.channel,
              canSendChannel: true,
              busy: false,
              selfUid: 'self',
              recipients: const [],
              recipientUid: null,
              onRecipientChanged: (_) {},
              onReply: (_) {},
              onScopeChanged: (_) {},
              onSend: (_) async => true,
            ),
          ),
        ),
      );

      await tester.pumpWidget(buildPane('Lobby'));
      expect(find.text('发送到 Lobby'), findsOneWidget);
      final shortHeight = tester.getSize(find.byType(TextField)).height;

      await tester.pumpWidget(
        buildPane('*入口 Entrance* 墓地 —— 超长频道名称测试 AABBCCDDEEFFGG'),
      );
      expect(find.text('发送到 本频道'), findsOneWidget);
      final longHeight = tester.getSize(find.byType(TextField)).height;
      expect(longHeight, shortHeight);
    },
  );

  testWidgets('composer send button does not force minimumSize Sizes.touch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 600,
            child: ChatPane(
              channelName: 'Lobby',
              messages: const [],
              scope: ChatScope.channel,
              canSendChannel: true,
              busy: false,
              selfUid: 'self',
              recipients: const [],
              recipientUid: null,
              onRecipientChanged: (_) {},
              onReply: (_) {},
              onScopeChanged: (_) {},
              onSend: (_) async => true,
            ),
          ),
        ),
      ),
    );

    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send_rounded),
    );
    expect(
      sendButton.style?.minimumSize?.resolve({}),
      isNot(const Size(Sizes.touch, Sizes.touch)),
    );
    expect(sendButton.style?.backgroundColor?.resolve({}), isNull);
  });
}
