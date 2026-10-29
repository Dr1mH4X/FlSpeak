// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/models.dart';
import '../../../core/image_host.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import 'chat_pane.dart';

void main() {
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
      await tester.tap(find.text('Peer'));
      await tester.pumpAndSettle();
      expect(chosen, 'peer');
    },
  );
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
