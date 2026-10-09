import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/theme/app_theme.dart';

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

/// 频道树刻意做成三层：根 -> 子 -> 孙，并且孙频道属于另一个根的分支。
const _channels = [
  ChannelView(id: 1, parentId: 0, name: 'Lobby', description: ''),
  ChannelView(id: 2, parentId: 1, name: 'Talk', description: ''),
  ChannelView(id: 3, parentId: 2, name: 'AFK', description: ''),
  ChannelView(id: 9, parentId: 0, name: 'Music', description: ''),
  // 父频道不在列表里（例如被权限过滤掉），必须仍然能被渲染成根。
  ChannelView(id: 20, parentId: 404, name: 'Orphan', description: ''),
];

const _clients = [
  ClientView(id: 7, nickname: 'me', uid: 'uid-me', channelId: 2),
  ClientView(id: 8, nickname: 'alice', uid: 'uid-alice', channelId: 2),
  ClientView(id: 9, nickname: 'bob', uid: 'uid-bob', channelId: 3),
  ClientView(id: 10, nickname: 'carol', uid: 'uid-carol', channelId: 9),
];

SessionView _connected({ChatScope scope = ChatScope.channel}) => SessionView(
  state: const CoreSessionState_Connected(clientId: 7, channelId: 2),
  servers: const [_home, _work],
  activeServerId: _home.id,
  channels: _channels,
  clients: _clients,
  chatScope: scope,
);

void main() {
  group('频道树', () {
    test('父频道缺失时仍作为根出现，不会整棵子树消失', () {
      final roots = _connected().rootChannels().map((c) => c.id).toList();
      expect(roots, containsAll(<int>[1, 9, 20]));
    });

    test('子频道按 parentId 归位', () {
      final view = _connected();
      expect(view.childrenOf(1).map((c) => c.id), [2]);
      expect(view.childrenOf(2).map((c) => c.id), [3]);
      expect(view.childrenOf(3), isEmpty);
    });

    test('人数含所有后代频道', () {
      final view = _connected();
      expect(view.clientsIn(2).length, 2);
      // 2 里 2 人 + 3 里 1 人
      expect(view.totalIn(2), 3);
      expect(view.totalIn(1), 3);
      expect(view.totalIn(9), 1);
    });
  });

  group('自己是谁', () {
    test('selfUid 按客户端 id 反查，能用它对齐消息的 fromUid', () {
      expect(_connected().selfUid, 'uid-me');
    });

    test('未连接时没有 selfUid', () {
      expect(const SessionView().selfUid, isEmpty);
    });
  });

  group('消息范围', () {
    final messages = [
      ChatMessage(
        from: 'alice',
        fromUid: 'uid-alice',
        text: 'in channel 2',
        at: DateTime(2026),
        scope: ChatScope.channel,
        targetId: 2,
      ),
      ChatMessage(
        from: 'bob',
        fromUid: 'uid-bob',
        text: 'in channel 3',
        at: DateTime(2026),
        scope: ChatScope.channel,
        targetId: 3,
      ),
      ChatMessage(
        from: 'carol',
        fromUid: 'uid-carol',
        text: 'server wide',
        at: DateTime(2026),
        scope: ChatScope.server,
        targetId: 0,
      ),
      ChatMessage(
        from: 'dave',
        fromUid: 'uid-dave',
        text: 'private',
        at: DateTime(2026),
        scope: ChatScope.direct,
        targetId: 7,
      ),
    ];

    test('频道范围只显示本频道消息，私聊始终显示', () {
      final view = _connected().copyWith(messages: messages);
      expect(view.visibleMessages().map((m) => m.text), [
        'in channel 2',
        'private',
      ]);
    });

    test('服务器范围显示广播消息，私聊仍然显示', () {
      final view = _connected(scope: ChatScope.server)
          .copyWith(messages: messages);
      expect(view.visibleMessages().map((m) => m.text), [
        'server wide',
        'private',
      ]);
    });
  });

  test('targetMode 归一化成投递范围', () {
    expect(ChatScope.fromProtocol(1), ChatScope.direct);
    expect(ChatScope.fromProtocol(2), ChatScope.channel);
    expect(ChatScope.fromProtocol(3), ChatScope.server);
    expect(ChatScope.channel.protocolMode, 2);
    expect(ChatScope.server.protocolMode, 3);
  });

  test('activeServer 按档案 id 取回连接中的那台', () {
    expect(_connected().activeServer?.label, 'home');
    expect(const SessionView().activeServer, isNull);
  });

  test('copyWith 能把 activeServerId 显式清空', () {
    expect(_connected().copyWith(activeServerId: null).activeServer, isNull);
  });

  test('relativeTime 在一天内用相对值，超过一天回到时钟', () {
    final now = DateTime(2026, 10, 8, 14, 30);
    expect(relativeTime(now.subtract(const Duration(seconds: 5)), now), 'now');
    expect(relativeTime(now.subtract(const Duration(minutes: 12)), now), '12m');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now), '3h');
    expect(relativeTime(DateTime(2026, 10, 6, 9, 5), now), '09:05');
  });
}
