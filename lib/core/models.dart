import 'package:flspeak_ffi/flspeak_ffi.dart';

/// 文字消息的投递范围，由协议里的 `targetMode` 归一化而来。
enum ChatScope {
  direct(1),
  channel(2),
  server(3);

  const ChatScope(this.protocolMode);

  /// TeamSpeak 的 TextMessageTargetMode。
  final int protocolMode;

  static ChatScope fromProtocol(int mode) => switch (mode) {
    2 => ChatScope.channel,
    3 => ChatScope.server,
    _ => ChatScope.direct,
  };
}

/// 聊天消息的界面模型：FFI 事件把同名字段内联在 `CoreEvent.textMessage` 上。
class ChatMessage {
  const ChatMessage({
    required this.from,
    required this.fromUid,
    required this.text,
    required this.at,
    required this.scope,
    required this.targetId,
  });

  final String from;
  final String fromUid;
  final String text;
  final DateTime at;
  final ChatScope scope;

  /// 频道消息是频道 id，私聊是收件客户端 id，服务器广播为 0。
  final int targetId;
}

const Object _unset = Object();

/// `CoreEvent` 流收敛出的界面状态。页面只读这个快照。
class SessionView {
  const SessionView({
    this.state = const CoreSessionState.disconnected(),
    this.servers = const <ServerProfileView>[],
    this.channels = const <ChannelView>[],
    this.clients = const <ClientView>[],
    this.messages = const <ChatMessage>[],
    this.activeServerId,
    this.chatScope = ChatScope.channel,
    this.busy = false,
    this.notice,
  });

  final CoreSessionState state;
  final List<ServerProfileView> servers;
  final List<ChannelView> channels;
  final List<ClientView> clients;
  final List<ChatMessage> messages;

  /// 本次连接使用的档案 id。协议层一次只维持一个连接，界面用它标记哪台服务器在线。
  final String? activeServerId;

  /// 输入框当前投递范围。
  final ChatScope chatScope;

  final bool busy;
  final String? notice;

  bool get connected => state is CoreSessionState_Connected;
  bool get connecting => state is CoreSessionState_Connecting;

  int? get selfClientId => switch (state) {
    CoreSessionState_Connected(:final clientId) => clientId,
    _ => null,
  };

  /// 当前频道。协议里频道 id 0 表示还没落到任何频道，这种情况按「不在频道里」处理。
  int? get selfChannelId => switch (state) {
    CoreSessionState_Connected(:final channelId) when channelId != 0 =>
      channelId,
    _ => null,
  };

  /// 自己的 UID：从在线列表里按客户端 id 反查，事件里的 `fromUid` 才能对上。
  String get selfUid {
    final id = selfClientId;
    if (id == null) {
      return '';
    }
    for (final client in clients) {
      if (client.id == id) {
        return client.uid;
      }
    }
    return '';
  }

  ServerProfileView? get activeServer {
    final id = activeServerId;
    if (id == null) {
      return null;
    }
    for (final server in servers) {
      if (server.id == id) {
        return server;
      }
    }
    return null;
  }

  ChannelView? channelById(int id) {
    for (final channel in channels) {
      if (channel.id == id) {
        return channel;
      }
    }
    return null;
  }

  /// 父频道指向不存在的频道时（例如被权限过滤掉）也算根，避免整棵子树消失。
  List<ChannelView> rootChannels() => channels
      .where((channel) => channelById(channel.parentId) == null)
      .toList();

  List<ChannelView> childrenOf(int parentId) =>
      channels.where((channel) => channel.parentId == parentId).toList();

  List<ClientView> clientsIn(int channelId) =>
      clients.where((client) => client.channelId == channelId).toList();

  int totalIn(int channelId) {
    var count = clientsIn(channelId).length;
    for (final child in childrenOf(channelId)) {
      count += totalIn(child.id);
    }
    return count;
  }

  ClientView? get selfClient {
    final id = selfClientId;
    if (id == null) {
      return null;
    }
    for (final client in clients) {
      if (client.id == id) {
        return client;
      }
    }
    return null;
  }

  /// 当前范围下要显示的消息。
  ///
  /// 私聊在任何范围都显示——漏掉一条私聊比多显示一行严重得多。
  List<ChatMessage> visibleMessages() {
    final channelId = selfChannelId;
    return messages.where((message) {
      if (message.scope == ChatScope.direct) {
        return true;
      }
      if (chatScope == ChatScope.server) {
        return message.scope == ChatScope.server;
      }
      return message.scope == ChatScope.channel &&
          message.targetId == channelId;
    }).toList();
  }

  SessionView copyWith({
    CoreSessionState? state,
    List<ServerProfileView>? servers,
    List<ChannelView>? channels,
    List<ClientView>? clients,
    List<ChatMessage>? messages,
    Object? activeServerId = _unset,
    ChatScope? chatScope,
    bool? busy,
    Object? notice = _unset,
  }) => SessionView(
    state: state ?? this.state,
    servers: servers ?? this.servers,
    channels: channels ?? this.channels,
    clients: clients ?? this.clients,
    messages: messages ?? this.messages,
    activeServerId: identical(activeServerId, _unset)
        ? this.activeServerId
        : activeServerId as String?,
    chatScope: chatScope ?? this.chatScope,
    busy: busy ?? this.busy,
    notice: identical(notice, _unset) ? this.notice : notice as String?,
  );
}

/// 把 FFI 错误翻成可以直接显示给用户的中文文案。
String describeCoreError(CoreError error) => switch (error) {
  CoreError_PolicyDenied(:final message) => '合规策略拒绝：$message',
  CoreError_Connection(:final message) => '连接失败：$message',
  CoreError_Internal(:final message) => '内部错误：$message',
};
