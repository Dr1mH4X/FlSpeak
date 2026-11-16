// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton,
        TextField;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/image_host.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/features/workspace/widgets/chat_pane.dart';
import 'package:flspeak/widgets/prism.dart';

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
      theme: buildAppTheme(Brightness.light),
      locale: const Locale('zh'),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        PrismUiLocalizationsDelegate(),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          PrismRootScope(brightness: Brightness.light, child: child!),
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
    await tester.pumpAndSettle();
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
      final scroll = tester
          .widget<PrismListView>(find.byType(PrismListView))
          .controller!;
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
      await tester.drag(find.byType(PrismListView), const Offset(0, 300));
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
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
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
      expect(input.controller!.text, '');
      expect(input.enabled, isTrue);
      expect(input.focusNode!.hasFocus, isTrue);
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
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sends, 1);
      response.complete(false);
      await tester.pumpAndSettle();
      expect(input.controller!.text, 'unsent draft');
      expect(input.focusNode!.hasFocus, isTrue);
      response = Completer<bool>();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      response.complete(true);
      await tester.pumpAndSettle();
      expect(input.controller!.text, '');
      expect(input.focusNode!.hasFocus, isTrue);
      expect(sends, 2);
    },
  );

  testWidgets(
    'recipient picker names the private target and the pane drops channel copy',
    (tester) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
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
      expect(find.text('Channel introduction'), findsNothing);
      expect(find.text('Peer'), findsOneWidget);
      expect(find.text('发送到 Peer'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.person_rounded));
      await tester.pumpAndSettle();
      // 用户选项默认收起，点击展开后方可选中对应私聊成员。
      await tester.tap(find.text('私聊'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListRow, 'Peer'));
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
  testWidgets('unread scopes and peers surface a marker on the scope control', (
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
            unreadScopes: const {ChatScope.server},
            unreadPeers: const {'alice'},
            onRecipientChanged: (_) {},
            onReply: (_) {},
            onScopeChanged: (_) {},
            onSend: (_) async => true,
          ),
        ),
      ),
    );

    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
    await tester.pumpAndSettle();
    // 服务器行与「私聊」分组各一个圆点；私聊成员行折叠时不构建。
    expect(find.byIcon(Icons.circle), findsNWidgets(2));
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
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
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
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          PrismUiLocalizationsDelegate(),
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            PrismRootScope(brightness: Brightness.light, child: child!),
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
      sendButton.style?.minimumSize,
      isNot(const Size(Sizes.touch, Sizes.touch)),
    );
    expect(sendButton.style?.backgroundColor?.resolve({}), isNull);
  });

  testWidgets(
    'slash command autocomplete fetches lazily, filters by prefix, completes with space, and auto-dismisses',
    (tester) async {
      final fetched = <ClientView>[];
      var botRecipient = const ClientView(
        id: 9,
        nickname: 'MusicBot',
        uid: 'bot-uid',
        channelId: 5,
        clientType: ClientType.bot,
        capabilities: ['chat:slash_commands'],
      );

      late StateSetter updateState;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            updateState = setState;
            return MaterialApp(
              theme: buildAppTheme(Brightness.light),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SizedBox(
                  width: 480,
                  height: 600,
                  child: ChatPane(
                    channelName: 'Lobby',
                    messages: const [],
                    scope: ChatScope.direct,
                    canSendChannel: true,
                    busy: false,
                    selfUid: 'self',
                    selfClientId: 1,
                    recipients: [botRecipient],
                    recipientUid: 'bot-uid',
                    recipientId: 9,
                    onRecipientChanged: (_) {},
                    onFetchBotCommands: fetched.add,
                    onReply: (_) {},
                    onScopeChanged: (_) {},
                    onSend: (_) async => true,
                  ),
                ),
              ),
            );
          },
        ),
      );

      // 首次键入 "/" 且本地尚未缓存命令列表时，触发按需拉取回调。
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      expect(fetched, hasLength(1));
      expect(fetched.single.uid, 'bot-uid');

      // 回包填入 botCommands 后，浮层展示匹配的命令项。
      updateState(() {
        botRecipient = const ClientView(
          id: 9,
          nickname: 'MusicBot',
          uid: 'bot-uid',
          channelId: 5,
          clientType: ClientType.bot,
          capabilities: ['chat:slash_commands'],
          botCommands: [
            BotCommandView(name: 'play', args: '<url|歌名>', desc: '点播指定歌曲或音频流'),
            BotCommandView(name: 'skip', args: '', desc: '跳过当前播放曲目'),
          ],
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('/play'), findsOneWidget);
      expect(find.text('<url|歌名>'), findsOneWidget);
      expect(find.text('点播指定歌曲或音频流'), findsOneWidget);
      expect(find.text('/skip'), findsOneWidget);

      // 输入前缀过滤命令列表。
      await tester.enterText(find.byType(TextField), '/pl');
      await tester.pump();
      expect(find.text('/play'), findsOneWidget);
      expect(find.text('/skip'), findsNothing);

      // 点击候选命令后自动填入 "/play " 并收起补全浮层。
      await tester.tap(find.text('/play'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '/play ',
      );
      expect(find.text('点播指定歌曲或音频流'), findsNothing);
    },
  );

  testWidgets(
    'command autocomplete strictly matches declared botCommandPrefix and completes with it',
    (tester) async {
      const botRecipient = ClientView(
        id: 9,
        nickname: 'TSMusicBot',
        uid: 'bot-uid',
        channelId: 5,
        clientType: ClientType.bot,
        capabilities: ['chat:slash_commands'],
        botCommandPrefix: '!',
        botCommands: [
          BotCommandView(name: 'play', args: '<url>', desc: '播放音乐'),
          BotCommandView(name: 'skip', args: '', desc: '下一首'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 600,
              child: ChatPane(
                channelName: 'Lobby',
                messages: const [],
                scope: ChatScope.direct,
                canSendChannel: true,
                busy: false,
                selfUid: 'self',
                selfClientId: 1,
                selfChannelId: 5,
                recipients: const [botRecipient],
                recipientUid: 'bot-uid',
                recipientId: 9,
                onRecipientChanged: (_) {},
                onReply: (_) {},
                onScopeChanged: (_) {},
                onSend: (_) async => true,
              ),
            ),
          ),
        ),
      );

      // 声明了 "!" 前缀的机器人不响应 "/"。
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      expect(find.text('/play'), findsNothing);
      expect(find.text('!play'), findsNothing);

      // 键入 "!" 后匹配并展示 "!play" 与 "!skip"。
      await tester.enterText(find.byType(TextField), '!');
      await tester.pumpAndSettle();
      expect(find.text('!play'), findsOneWidget);
      expect(find.text('!skip'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '!pl');
      await tester.pump();
      expect(find.text('!play'), findsOneWidget);
      expect(find.text('!skip'), findsNothing);

      await tester.tap(find.text('!play'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '!play ',
      );
      expect(find.text('播放音乐'), findsNothing);
    },
  );

  testWidgets(
    'channel chat merges commands from same-channel bots with matching prefix and shows bot label',
    (tester) async {
      const musicBot = ClientView(
        id: 9,
        nickname: 'TSMusicBot',
        uid: 'music-uid',
        channelId: 5,
        clientType: ClientType.bot,
        capabilities: ['chat:slash_commands'],
        botCommandPrefix: '!',
        botCommands: [
          BotCommandView(name: 'play', args: '<url>', desc: '播放音乐'),
        ],
      );
      const clawBot = ClientView(
        id: 10,
        nickname: 'ClawBot',
        uid: 'claw-uid',
        channelId: 5,
        clientType: ClientType.bot,
        capabilities: ['chat:slash_commands'],
        botCommands: [
          BotCommandView(name: 'ask', args: '<prompt>', desc: '向助手提问'),
        ],
      );
      const remoteBot = ClientView(
        id: 11,
        nickname: 'RemoteBot',
        uid: 'remote-uid',
        channelId: 8,
        clientType: ClientType.bot,
        capabilities: ['chat:slash_commands'],
        botCommandPrefix: '!',
        botCommands: [BotCommandView(name: 'ping', args: '', desc: '远程频道命令')],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 600,
              child: ChatPane(
                channelName: 'Lobby',
                messages: const [],
                scope: ChatScope.channel,
                canSendChannel: true,
                busy: false,
                selfUid: 'self',
                selfClientId: 1,
                selfChannelId: 5,
                recipients: const [musicBot, clawBot, remoteBot],
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

      // 键入 "!" 只匹配当前频道且前缀为 "!" 的 TSMusicBot，并显示机器人名称标签。
      await tester.enterText(find.byType(TextField), '!');
      await tester.pumpAndSettle();
      expect(find.text('!play'), findsOneWidget);
      expect(find.text('TSMusicBot'), findsOneWidget);
      expect(find.text('/ask'), findsNothing);
      expect(find.text('!ping'), findsNothing);

      // 键入 "/" 只匹配未声明前缀（默认 "/"）的 ClawBot。
      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      expect(find.text('/ask'), findsOneWidget);
      expect(find.text('ClawBot'), findsOneWidget);
      expect(find.text('!play'), findsNothing);
    },
  );

  testWidgets(
    'enter and send button both preserve composer focus across busy sends for consecutive messages',
    (tester) async {
      final sent = <String>[];
      var busy = false;
      late StateSetter updateState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            updateState = setState;
            return MaterialApp(
              theme: buildAppTheme(Brightness.light),
              locale: const Locale('zh'),
              localizationsDelegates: const [
                ...AppLocalizations.localizationsDelegates,
                PrismUiLocalizationsDelegate(),
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) =>
                  PrismRootScope(brightness: Brightness.light, child: child!),
              home: Scaffold(
                body: ChatPane(
                  channelName: 'Lobby',
                  messages: const [],
                  scope: ChatScope.channel,
                  canSendChannel: true,
                  busy: busy,
                  selfUid: 'self',
                  recipients: const [],
                  recipientUid: null,
                  onRecipientChanged: (_) {},
                  onReply: (_) {},
                  onScopeChanged: (_) {},
                  onSend: (text) async {
                    updateState(() => busy = true);
                    await Future<void>.delayed(Duration.zero);
                    sent.add(text);
                    updateState(() => busy = false);
                    return true;
                  },
                ),
              ),
            );
          },
        ),
      );

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pump();
      tester.testTextInput.enterText('first');
      await tester.pump();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.pumpAndSettle();
      expect(sent, ['first']);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

      // 不重新点击输入框，直接键入第二条并点击发送按钮。
      tester.testTextInput.enterText('second');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(sent, ['first', 'second']);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

      // 点击输入框与发送栏外部区域时仍能正常收起焦点。
      await tester.tap(find.byType(PrismListView));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    },
  );

  testWidgets(
    'typing a new message during pending send keeps it clean on both success and failure',
    (tester) async {
      var pending = Completer<bool>();
      final sent = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
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
              onSend: (text) {
                sent.add(text);
                return pending.future;
              },
            ),
          ),
        ),
      );

      final field = find.byType(TextField);
      await tester.enterText(field, 'first');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // 第一条尚未完成时立即输入第二条，成功完成不会混入旧文本。
      tester.testTextInput.enterText('second');
      await tester.pump();
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'second');

      // 第二条发送期间若又输入第三条，即使第二条失败也不覆盖用户新输入。
      pending = Completer<bool>();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      tester.testTextInput.enterText('third');
      await tester.pump();
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'third');
      expect(sent, ['first', 'second']);
    },
  );

  testWidgets(
    'tapping outside during async image upload does not yank focus back after completion',
    (tester) async {
      final upload = Completer<String?>();
      final sent = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
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
              onPickImage: () async => _picked(),
              onUploadImage: (_) => upload.future,
              onSend: (text) async {
                sent.add(text);
                return true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择图片'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

      // 上传期间用户主动点到消息列表失焦。
      await tester.tap(find.byType(PrismListView));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);

      upload.complete('https://images.example.com/async.png');
      await tester.pumpAndSettle();
      expect(sent, ['![](<https://images.example.com/async.png>)']);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    },
  );

  testWidgets(
    'floating composer and slash menu toggle LiquidGlass via scope and bottom scroll clears composer',
    (tester) async {
      final messages = List.generate(
        30,
        (index) => ChatMessage(
          from: 'Alice',
          fromUid: 'alice',
          fromId: 2,
          text: 'message $index',
          at: DateTime.utc(2026, 1, 1).add(Duration(seconds: index)),
          scope: ChatScope.channel,
          targetId: 5,
        ),
      );
      const bot = ClientView(
        id: 7,
        nickname: 'HelperBot',
        uid: 'helper-bot',
        channelId: 5,
        clientType: ClientType.bot,
        capabilities: ['chat:slash_commands'],
        botCommandPrefix: '/',
        botCommands: [BotCommandView(name: 'ask', args: '', desc: '提问')],
      );

      Future<void> mount(LiquidGlassQuality? quality) async {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(quality),
            theme: buildAppTheme(Brightness.light),
            locale: const Locale('zh'),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => PrismRootScope(
              brightness: Brightness.light,
              liquidGlass: quality,
              child: child!,
            ),
            home: Scaffold(
              body: SizedBox(
                width: 640,
                height: 480,
                child: ChatPane(
                  channelName: 'Lobby',
                  messages: messages,
                  scope: ChatScope.channel,
                  canSendChannel: true,
                  busy: false,
                  selfUid: 'self',
                  selfClientId: 1,
                  selfChannelId: 5,
                  recipients: const [bot],
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
        await tester.pumpAndSettle();
      }

      await mount(null);
      expect(find.byType(LiquidGlass), findsNothing);
      final listFinder = find.byType(PrismListView);
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(of: listFinder, matching: find.byType(Scrollable))
            .first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final lastMessageFinder = find.text('message 29');
      expect(lastMessageFinder, findsOneWidget);
      final lastMessageBottom = tester.getBottomLeft(lastMessageFinder).dy;
      final composerTop = tester.getTopLeft(find.byType(TextField)).dy;
      expect(lastMessageBottom, lessThanOrEqualTo(composerTop));

      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      expect(find.text('/ask'), findsOneWidget);
      expect(find.byType(LiquidGlass), findsNothing);

      await mount(LiquidGlassQuality.standard);
      expect(find.byType(LiquidGlass), findsOneWidget);

      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      expect(find.text('/ask'), findsOneWidget);
      expect(find.byType(LiquidGlass), findsNWidgets(2));
    },
  );
}
