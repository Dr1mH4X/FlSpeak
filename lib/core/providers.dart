import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import 'models.dart';
import 'preferences.dart';

/// 在 `main()` 里用真实句柄覆盖；测试里用假的实现覆盖。
final coreSessionProvider = Provider<CoreSession>(
  (ref) => throw StateError('coreSessionProvider 必须在 ProviderScope 里覆盖'),
);

/// `servers.json` 的绝对路径，设置页展示与复制用。同样在 `main()` 里覆盖。
final storePathProvider = Provider<String>(
  (ref) => throw StateError('storePathProvider 必须在 ProviderScope 里覆盖'),
);

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
    // 初始档案在 spawn 时就广播过一次，广播通道不补发给订阅者；订阅后主动拉一遍，
    // 否则打开应用时已保存的服务器列表要等下一次增删才会出现。
    unawaited(_loadServers(session));
    return const SessionView();
  }

  Future<void> _loadServers(CoreSession session) async {
    try {
      final servers = await session.listServers();
      if (ref.mounted) {
        state = state.copyWith(servers: servers);
      }
    } on CoreError catch (error) {
      if (ref.mounted) {
        state = state.copyWith(notice: describeCoreError(error));
      }
    }
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
      state = state.copyWith(
        activeServerId: id,
        messages: const [],
        speaking: const {},
        voiceNotice: null,
      );
      // 频道/成员快照由 actor 在连接成功后主动推送，不再额外拉一遍。
      await ref.read(coreSessionProvider).connect(id: id, nickname: nickname);
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

  /// 静音只停发送；deafen 同时停发送并静音播放。状态以 Rust 的 Voice 事件为准。
  Future<void> setMuted(bool muted) async {
    try {
      await ref.read(coreSessionProvider).setMuted(muted: muted);
    } on CoreError catch (error) {
      state = state.copyWith(voiceNotice: describeCoreError(error));
    }
  }

  Future<void> setDeafened(bool deafened) async {
    try {
      await ref.read(coreSessionProvider).setDeafened(deafened: deafened);
    } on CoreError catch (error) {
      state = state.copyWith(voiceNotice: describeCoreError(error));
    }
  }

  Future<void> setAway(bool away) async {
    try {
      await ref.read(coreSessionProvider).setAway(away: away);
    } on CoreError catch (error) {
      state = state.copyWith(voiceNotice: describeCoreError(error));
    }
  }

  Future<void> setPttMode(bool enabled) async {
    try {
      await ref.read(coreSessionProvider).setPttMode(enabled: enabled);
    } on CoreError catch (error) {
      state = state.copyWith(voiceNotice: describeCoreError(error));
    }
  }

  Future<void> setPttActive(bool active) async {
    if (!state.pttMode) {
      return;
    }
    try {
      await ref.read(coreSessionProvider).setPttActive(active: active);
    } on CoreError catch (error) {
      state = state.copyWith(voiceNotice: describeCoreError(error));
    }
  }

  Future<void> cancelIdentityUpgrade() async {
    try {
      await ref.read(coreSessionProvider).cancelIdentityUpgrade();
    } on CoreError catch (error) {
      state = state.copyWith(voiceNotice: describeCoreError(error));
    }
  }

  /// 掉线后是否自动重连。策略在 Rust 侧，这里只转发开关。
  Future<void> setAutoReconnect(bool enabled) async {
    await _run(
      () => ref.read(coreSessionProvider).setAutoReconnect(enabled: enabled),
    );
  }

  void dismissVoiceNotice() {
    state = state.copyWith(voiceNotice: null);
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

  /// 让 Rust 重新协调频道与成员；两路数据可独立降级，由 CoreEvent 统一更新界面。
  Future<void> refresh() async {
    try {
      await ref.read(coreSessionProvider).requestSnapshot();
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
            speaking: const {},
            selfSpeaking: false,
            identityUpgradeTarget: null,
            busy: false,
          ),
          _ => current.copyWith(state: next),
        };
      case CoreEvent_Servers(:final profiles):
        state = current.copyWith(servers: profiles);
      case CoreEvent_Snapshot(:final channels, :final clients):
        state = current.copyWith(channels: channels, clients: clients);
      case CoreEvent_History(:final messages):
        state = current.copyWith(
          messages: messages.map(ChatMessage.fromCore).toList(),
        );
      case CoreEvent_TextMessage(
        :final from,
        :final fromUid,
        :final message,
        :final targetMode,
        :final targetId,
        :final at,
      ):
        final appended = [
          ...current.messages,
          ChatMessage(
            from: from,
            fromUid: fromUid,
            text: message,
            at: DateTime.fromMillisecondsSinceEpoch(at),
            scope: ChatScope.fromProtocol(targetMode),
            targetId: targetId,
          ),
        ];
        state = current.copyWith(
          messages: appended.length > _messageLimit
              ? appended.sublist(appended.length - _messageLimit)
              : appended,
        );
      case CoreEvent_ClientJoined(
        :final id,
        :final nickname,
        :final uid,
        :final channelId,
      ):
        final others = current.clients.where((client) => client.id != id);
        state = current.copyWith(
          clients: [
            ...others,
            ClientView(
              id: id,
              nickname: nickname,
              uid: uid,
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
                  // 移动事件不带任何标志，沿用移动前的已知值。
                  inputMuted: client.inputMuted,
                  outputMuted: client.outputMuted,
                  away: client.away,
                  awayMessage: client.awayMessage,
                )
              else
                client,
          ],
        );
      case CoreEvent_ClientUpdated(
        :final id,
        :final inputMuted,
        :final outputMuted,
        :final away,
        :final awayMessage,
      ):
        // 事件只带变化字段，null 表示本次没提，不清除已知值。
        state = current.copyWith(
          clients: [
            for (final client in current.clients)
              if (client.id == id)
                ClientView(
                  id: client.id,
                  nickname: client.nickname,
                  uid: client.uid,
                  channelId: client.channelId,
                  inputMuted: inputMuted ?? client.inputMuted,
                  outputMuted: outputMuted ?? client.outputMuted,
                  away: away ?? client.away,
                  awayMessage: awayMessage ?? client.awayMessage,
                )
              else
                client,
          ],
        );
      case CoreEvent_Voice(state: final voice):
        state = current.copyWith(
          muted: voice.muted,
          deafened: voice.deafened,
          away: voice.away,
          pttMode: voice.pttMode,
          voiceInputReady: voice.inputReady,
          voiceOutputReady: voice.outputReady,
          voiceNotice: voice.message,
        );
      case CoreEvent_Speaking(:final clientIds):
        state = current.copyWith(speaking: clientIds.toSet());
      case CoreEvent_SelfSpeaking(:final speaking):
        state = current.copyWith(selfSpeaking: speaking);
      case CoreEvent_IdentityUpgrade(:final to):
        state = current.copyWith(
          identityUpgradeTarget: to,
          notice: '身份等级不足，正在提升到 $to…',
        );
      case CoreEvent_IdentityUpgraded(:final level):
        state = current.copyWith(
          identityUpgradeTarget: null,
          notice: '身份等级已提升到 $level，正在重连…',
        );
      case CoreEvent_TransferStarted():
      case CoreEvent_TransferProgress():
      case CoreEvent_TransferFinished():
        // 传输进度暂时没有界面入口；后端事件先保留，避免以后加 UI 时改协议。
        break;
      case CoreEvent_Log():
        // 协议日志不进界面，避免刷屏。
        break;
      case CoreEvent_Denied(:final message):
        state = current.copyWith(notice: message);
      case CoreEvent_Failed(:final message):
        // 保留 activeServerId：掉线重连期间服务器栏仍然标着原服务器；
        // 用户主动断开由 State(Disconnected) 负责清空。
        state = current.copyWith(
          notice: message,
          channels: const [],
          clients: const [],
          speaking: const {},
          identityUpgradeTarget: null,
        );
    }
  }
}

/// 读写昵称与最近连接时间。`main()` 里覆盖成文件实现；测试里默认是内存实现。
final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => PreferencesStore.inMemory(),
);

final preferencesProvider =
    NotifierProvider<PreferencesController, SessionPreferences>(
      PreferencesController.new,
    );

class PreferencesController extends Notifier<SessionPreferences> {
  @override
  SessionPreferences build() => ref.watch(preferencesStoreProvider).current;

  void setNickname(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == state.nickname) {
      return;
    }
    _update(state.copyWith(nickname: trimmed));
  }

  /// `null` 表示跟随系统。
  void setLocale(String? code) {
    if (code == state.locale) {
      return;
    }
    _update(state.copyWith(locale: code));
  }

  void setTheme(AppThemePreference theme) {
    if (theme == state.theme) {
      return;
    }
    _update(state.copyWith(theme: theme));
  }

  /// `null` 表示清除按住说话快捷键。
  void setPttHotkey(int? keyId) {
    if (keyId == state.pttHotkey) {
      return;
    }
    _update(state.copyWith(pttHotkey: keyId));
  }

  void markConnected(String serverId, DateTime at) {
    _update(
      state.copyWith(lastConnected: {...state.lastConnected, serverId: at}),
    );
  }

  void _update(SessionPreferences next) {
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _persist(SessionPreferences next) async {
    try {
      await ref.read(preferencesStoreProvider).save(next);
    } on Object catch (error) {
      debugPrint('保存 preferences 失败：$error');
    }
  }
}
