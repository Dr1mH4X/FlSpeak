import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';

ChatMessage message({
  required ChatScope scope,
  required int targetId,
  String fromUid = 'peer',
  String peerUid = '',
  String text = 'message',
}) => ChatMessage(
  from: fromUid == 'self' ? 'Self' : 'Peer',
  fromUid: fromUid,
  text: text,
  at: DateTime(2026),
  scope: scope,
  targetId: targetId,
  peerUid: peerUid,
);

void main() {
  final messages = [
    message(scope: ChatScope.channel, targetId: 7, text: 'lobby'),
    message(scope: ChatScope.channel, targetId: 8, text: 'elsewhere'),
    message(scope: ChatScope.server, targetId: 0, text: 'broadcast'),
    message(scope: ChatScope.direct, targetId: 1, peerUid: 'alice', text: 'hi'),
    message(
      scope: ChatScope.direct,
      targetId: 2,
      fromUid: 'self',
      peerUid: 'alice',
      text: 'hello',
    ),
    message(scope: ChatScope.direct, targetId: 1, peerUid: 'bob', text: 'psst'),
  ];

  SessionView view(ChatScope scope, {String? recipient = 'alice'}) =>
      SessionView(
        messages: messages,
        chatScope: scope,
        directRecipientUid: recipient,
      );

  test('channel scope shows the viewed channel only', () {
    final visible = view(ChatScope.channel).visibleMessages(channelId: 7);
    expect(visible.map((item) => item.text), ['lobby']);
  });

  test('server scope shows broadcasts only', () {
    final visible = view(ChatScope.server).visibleMessages(channelId: 7);
    expect(visible.map((item) => item.text), ['broadcast']);
  });

  test('direct scope shows one conversation in both directions', () {
    final visible = view(ChatScope.direct).visibleMessages(channelId: 7);
    expect(visible.map((item) => item.text), ['hi', 'hello']);
  });

  test('legacy direct records without peer_uid stay with the sender', () {
    final legacy = ChatMessage(
      from: 'Alice',
      fromUid: 'alice',
      fromId: 3,
      text: 'old hello',
      at: DateTime(2025),
      scope: ChatScope.direct,
      targetId: 1,
    );
    final view = SessionView(
      messages: [legacy],
      chatScope: ChatScope.direct,
      directRecipientUid: 'alice',
    );
    expect(view.visibleMessages(channelId: 7).single.text, 'old hello');
  });

  test('direct scope without a recipient shows nothing', () {
    final visible = view(
      ChatScope.direct,
      recipient: null,
    ).visibleMessages(channelId: 7);
    expect(visible, isEmpty);
  });
}
