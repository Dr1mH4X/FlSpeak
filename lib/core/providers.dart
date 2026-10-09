import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import 'models.dart';

/// 在 `main()` 里用真实句柄覆盖；测试里用假的实现覆盖。
final coreSessionProvider = Provider<CoreSession>(
  (ref) => throw StateError('coreSessionProvider 必须在 ProviderScope 里覆盖'),
);

/// 核心状态文件位置，设置页展示用。
final storePathProvider = Provider<String>((ref) => '');

/// `CoreEvent` 流收敛成的界面状态。
final sessionViewProvider = NotifierProvider<SessionController, SessionView>(
  SessionController.new,
);

class SessionController extends Notifier<SessionView> {
  /// 只保留本次会话的消息；上限防止长时间挂着时无限增长。
  static const _messageLimit = 500;

  @override
  SessionView build() {
    final session = ref.watch(coreSessionProvider);
    final subscription = session.events().listen(_onEvent);
    ref.onDispose(subscription.cancel);
    return const SessionView();
  }

  /// 录入服务器。返回新档案，地址被策略拒绝时返回 `null` 并把原因写进提示条。
  Future<ServerProfileView?> addServer({
    required String label,
    required String address,
  }) async {
    ServerProfileView? created;
    await _run(() async {
      created = await ref
          .read(coreSessionProvider)
          .registerServer(label: label, address: address);
    });
    return created;
  }

  Future<void> removeServer(String id) async {
    await _run(() => ref.read(coreSessionProvider).removeServer(id: id));
  }

  Future<void> connect({required String id, required String nickname}) async {
    await _run(() async {
      // 先记下目标档案：状态事件只带客户端 id，界面需要知道连的是哪台服务器。
      state = state.copyWith(activeServerId: id, messages: const []);
      await ref.read(coreSessionProvider).connect(id: id, nickname: nickname);
      await refresh();
    });
  }

  Future<void> disconnect() async {
    await _run(() => ref.read(coreSessionProvider).disconnect());
  }

  Future<void> joinChannel(int channelId, {String? password}) async {
    final clientId = state.selfClientId;
    if (clientId == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(coreSessionProvider)
          .moveToChannel(
            clientId: clientId,
            channelId: channelId,
            password: password,
          );
      await refresh();
    });
  }

  void selectChatScope(ChatScope scope) {
    state = state.copyWith(chatScope: scope);
  }

  /// 按当前范围发送。频道范围要求已进入某个频道，否则拒绝发送而不是发错地方。
  Future<void> sendMessage(String text) async {
    final message = text.trim();
    if (message.isEmpty) {
      return;
    }

    final scope = state.chatScope;
    final targetId = switch (scope) {
      ChatScope.channel => state.selfChannelId,
      ChatScope.server => 0,
      ChatScope.direct => null,
    };
    if (targetId == null) {
      state = state.copyWith(notice: '还没有进入任何频道，无法发送频道消息。');
      return;
    }

    await _run(
      () => ref
          .read(coreSessionProvider)
          .sendText(
            targetMode: scope.protocolMode,
            targetId: targetId,
            message: message,
          ),
    );
  }

  /// 连接成功后拉一次频道与成员快照。
  Future<void> refresh() async {
    final session = ref.read(coreSessionProvider);
    try {
      final channels = await session.listChannels();
      final clients = await session.listClients();
      state = state.copyWith(channels: channels, clients: clients);
    } on CoreError catch (error) {
      state = state.copyWith(notice: describeCoreError(error));
    }
  }

  void dismissNotice() {
    state = state.copyWith(notice: null);
  }

  Future<void> _run(Future<void> Function() action) async {
    state = state.copyWith(busy: true, notice: null);
    try {
      await action();
    } on CoreError catch (error) {
      state = state.copyWith(notice: describeCoreError(error));
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  void _onEvent(CoreEvent event) {
    final current = state;
    switch (event) {
      case CoreEvent_State(state: final next):
        state = switch (next) {
          CoreSessionState_Disconnected() => current.copyWith(
            state: next,
            activeServerId: null,
            channels: const [],
            clients: const [],
          ),
          _ => current.copyWith(state: next),
        };
      case CoreEvent_Servers(:final profiles):
        state = current.copyWith(servers: profiles);
      case CoreEvent_TextMessage(
        :final from,
        :final fromUid,
        :final message,
        :final targetMode,
        :final targetId,
      ):
        final appended = [
          ...current.messages,
          ChatMessage(
            from: from,
            fromUid: fromUid,
            text: message,
            at: DateTime.now(),
            scope: ChatScope.fromProtocol(targetMode),
            targetId: targetId,
          ),
        ];
        state = current.copyWith(
          messages: appended.length > _messageLimit
              ? appended.sublist(appended.length - _messageLimit)
              : appended,
        );
      case CoreEvent_ClientJoined(:final id, :final nickname, :final channelId):
        final others = current.clients.where((client) => client.id != id);
        state = current.copyWith(
          clients: [
            ...others,
            ClientView(
              id: id,
              nickname: nickname,
              uid: '',
              channelId: channelId,
            ),
          ],
        );
      case CoreEvent_ClientLeft(:final id):
        state = current.copyWith(
          clients: current.clients.where((client) => client.id != id).toList(),
        );
      case CoreEvent_ClientMoved(:final id, :final channelId):
        state = current.copyWith(
          clients: [
            for (final client in current.clients)
              if (client.id == id)
                ClientView(
                  id: client.id,
                  nickname: client.nickname,
                  uid: client.uid,
                  channelId: channelId,
                )
              else
                client,
          ],
        );
      case CoreEvent_Log():
        // 协议日志不进界面，避免刷屏。
        break;
      case CoreEvent_Denied(:final message):
        state = current.copyWith(notice: message);
      case CoreEvent_Failed(:final message):
        state = current.copyWith(
          notice: message,
          activeServerId: null,
          channels: const [],
          clients: const [],
        );
    }
  }
}

/// 连接时使用的昵称，进程内保存。
final nicknameProvider = NotifierProvider<NicknameController, String>(
  NicknameController.new,
);

class NicknameController extends Notifier<String> {
  static const _fallback = 'ts-client';

  @override
  String build() => _fallback;

  void update(String value) {
    final trimmed = value.trim();
    state = trimmed.isEmpty ? _fallback : trimmed;
  }
}

/// 界面语言；`null` 表示跟随系统。
final localeProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);

class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  void update(Locale? locale) => state = locale;
}
