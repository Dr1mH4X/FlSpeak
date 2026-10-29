import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../l10n/app_localizations.dart';
import 'channel_display.dart';

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
    this.fromId = 0,
  });

  final String from;
  final String fromUid;
  final int fromId;
  final String text;
  final DateTime at;
  final ChatScope scope;

  /// 频道消息是频道 id，私聊是收件客户端 id，服务器广播为 0。
  final int targetId;

  factory ChatMessage.fromCore(CoreMessage message) => ChatMessage(
    from: message.from,
    fromUid: message.fromUid,
    fromId: message.fromId,
    text: message.message,
    at: DateTime.fromMillisecondsSinceEpoch(message.at),
    scope: ChatScope.fromProtocol(message.targetMode),
    targetId: message.targetId,
  );
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
    this.directRecipientUid,
    this.directRecipientId,
    this.busy = false,
    this.failureSeq = 0,
    this.connectionEpoch = 0,
    this.accessRevision = 0,
    this.muted = false,
    this.deafened = false,
    this.away = false,
    this.voiceInputReady = false,
    this.voiceOutputReady = false,
    this.speaking = const <int>{},
    this.selfSpeaking = false,
    this.pttMode = false,
    this.identityUpgradeTarget,
    this.transfers = const {},
    this.activeFileDownloads = const {},
  });

  final Map<int, FileTransfer> transfers;
  final Map<(int, int), int?> activeFileDownloads;
  final CoreSessionState state;
  final List<ServerProfileView> servers;
  final List<ChannelView> channels;
  final List<ClientView> clients;
  final List<ChatMessage> messages;

  /// 本次连接使用的档案 id。协议层一次只维持一个连接，界面用它标记哪台服务器在线。
  final String? activeServerId;

  /// 输入框当前投递范围。
  final ChatScope chatScope;
  final String? directRecipientUid;
  final int? directRecipientId;

  ClientView? get directRecipient {
    if (directRecipientId != null) {
      for (final client in clients) {
        if (client.id == directRecipientId &&
            client.uid == directRecipientUid &&
            client.id != selfClientId) {
          return client;
        }
      }
      return null;
    }
    final matches = clients
        .where(
          (client) =>
              client.uid == directRecipientUid && client.id != selfClientId,
        )
        .toList();
    return matches.length == 1 ? matches.first : null;
  }

  bool isOwnMessage(ChatMessage message) {
    if (message.fromId > 0 && selfClientId != null) {
      return message.fromId == selfClientId;
    }
    if (message.scope == ChatScope.direct &&
        selfClientId != null &&
        message.targetId > 0) {
      return message.targetId != selfClientId;
    }
    final uid = selfUid;
    return uid.isNotEmpty && message.fromUid == uid;
  }

  final bool busy;

  /// 连接失败或被拒事件的序号。只给连接页判断等待状态，不渲染。
  final int failureSeq;

  final int connectionEpoch;

  /// 权限与成员组快照的单调递增版本号；用于通知下游衍生 Provider 触发重查。
  final int accessRevision;

  /// 自己是否处于静音/聋听状态；由 Rust 的 Voice 事件确认。
  final bool muted;
  final bool deafened;

  /// 自己是否标记了离开；只是服务器上的标志，不影响音频。
  final bool away;
  final bool voiceInputReady;
  final bool voiceOutputReady;

  /// 当前正在说话的客户端 id。只在集合变化时由 Rust 推送。
  final Set<int> speaking;

  /// 本端 VAD/PTT 是否正在发送。
  final bool selfSpeaking;

  final bool pttMode;

  /// 非空表示正在提升身份等级，值为目标等级。
  final int? identityUpgradeTarget;

  bool get connected => state is CoreSessionState_Connected;
  bool get connecting => state is CoreSessionState_Connecting;
  bool get reconnecting => state is CoreSessionState_Reconnecting;

  int? get reconnectAttempt => switch (state) {
    CoreSessionState_Reconnecting(:final attempt) => attempt,
    _ => null,
  };

  int? get reconnectDelayMs => switch (state) {
    CoreSessionState_Reconnecting(:final delayMs) => delayMs,
    _ => null,
  };

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

  /// 同上两个查询，但按 `channel_order` 链表语义排成展示顺序。
  List<ChannelView> orderedRootChannels() => orderSiblings(rootChannels());

  List<ChannelView> orderedChildrenOf(int parentId) =>
      orderSiblings(childrenOf(parentId));

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

  /// 当前范围下要显示的消息。默认看自己所在的频道。
  ///
  /// 私聊在任何范围都显示——漏掉一条私聊比多显示一行严重得多。
  List<ChatMessage> visibleMessages({int? channelId}) {
    final scopeChannel = channelId ?? selfChannelId;
    return messages.where((message) {
      if (message.scope == ChatScope.direct) {
        return true;
      }
      if (chatScope == ChatScope.server) {
        return message.scope == ChatScope.server;
      }
      return message.scope == ChatScope.channel &&
          message.targetId == scopeChannel;
    }).toList();
  }

  SessionView copyWith({
    Map<int, FileTransfer>? transfers,
    Map<(int, int), int?>? activeFileDownloads,
    CoreSessionState? state,
    List<ServerProfileView>? servers,
    List<ChannelView>? channels,
    List<ClientView>? clients,
    List<ChatMessage>? messages,
    Object? activeServerId = _unset,
    ChatScope? chatScope,
    Object? directRecipientUid = _unset,
    Object? directRecipientId = _unset,
    bool? busy,
    int? failureSeq,
    int? connectionEpoch,
    int? accessRevision,
    bool? muted,
    bool? deafened,
    bool? away,
    bool? voiceInputReady,
    bool? voiceOutputReady,
    Set<int>? speaking,
    bool? selfSpeaking,
    bool? pttMode,
    Object? identityUpgradeTarget = _unset,
  }) => SessionView(
    transfers: transfers ?? this.transfers,
    activeFileDownloads: activeFileDownloads ?? this.activeFileDownloads,
    state: state ?? this.state,
    servers: servers ?? this.servers,
    channels: channels ?? this.channels,
    clients: clients ?? this.clients,
    messages: messages ?? this.messages,
    activeServerId: identical(activeServerId, _unset)
        ? this.activeServerId
        : activeServerId as String?,
    chatScope: chatScope ?? this.chatScope,
    directRecipientUid: identical(directRecipientUid, _unset)
        ? this.directRecipientUid
        : directRecipientUid as String?,
    directRecipientId: identical(directRecipientId, _unset)
        ? this.directRecipientId
        : directRecipientId as int?,
    busy: busy ?? this.busy,
    failureSeq: failureSeq ?? this.failureSeq,
    connectionEpoch: connectionEpoch ?? this.connectionEpoch,
    accessRevision: accessRevision ?? this.accessRevision,
    muted: muted ?? this.muted,
    deafened: deafened ?? this.deafened,
    away: away ?? this.away,
    voiceInputReady: voiceInputReady ?? this.voiceInputReady,
    voiceOutputReady: voiceOutputReady ?? this.voiceOutputReady,
    speaking: speaking ?? this.speaking,
    selfSpeaking: selfSpeaking ?? this.selfSpeaking,
    pttMode: pttMode ?? this.pttMode,
    identityUpgradeTarget: identical(identityUpgradeTarget, _unset)
        ? this.identityUpgradeTarget
        : identityUpgradeTarget as int?,
  );
}

/// 把 FFI 错误翻成可以直接显示给用户的文案。
String describeCoreError(CoreError error, [AppLocalizations? l10n]) =>
    switch (error) {
      CoreError_InvalidAddress(:final message) => '服务器地址不可用：$message',
      CoreError_BlockedAddress(:final message) => '已阻止该地址：$message',
      CoreError_Connection(:final message) => '连接失败：$message',
      CoreError_ChannelPasswordRequired(:final message) =>
        l10n?.channelPasswordWrong ?? message,
      CoreError_Internal(:final message) => '内部错误：$message',
    };

class FileTransfer {
  const FileTransfer({
    required this.remotePath,
    required this.total,
    this.transferred = 0,
    this.finished = false,
    this.error,
  });
  final String remotePath;
  final int total;
  final int transferred;
  final bool finished;
  final String? error;
}
