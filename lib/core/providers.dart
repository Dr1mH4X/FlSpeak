import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import 'models.dart';
import 'notices.dart';
import 'preferences.dart';
import 'voice_levels.dart';

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

/// 电平独立成流：10Hz 的更新只让电平条重建，不碰整个 `SessionView`。
final voiceLevelsProvider = StreamProvider<VoiceLevels>((ref) {
  return ref.watch(sessionViewProvider.notifier).levels;
});

class SessionController extends Notifier<SessionView> {
  /// 只保留本次会话的消息；上限防止长时间挂着时无限增长。
  static const _messageLimit = 500;

  final _levels = StreamController<VoiceLevels>.broadcast();
  VoiceLevels _latestLevels = VoiceLevels.silent;

  /// 最近一次已提示的语音错误；Voice 事件重复带同一句时不再刷新提示。
  String? _lastVoiceNotice;

  Stream<VoiceLevels> get levels => _levels.stream;

  @override
  SessionView build() {
    final session = ref.watch(coreSessionProvider);
    final subscription = session.events().listen(_onEvent);
    ref.onDispose(subscription.cancel);
    ref.onDispose(_levels.close);
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
        _notify(describeCoreError(error));
      }
    }
  }

  /// 录入服务器。地址被策略拒绝时把 `CoreError` 抛给调用方，由表单就地显示。
  Future<ServerProfileView> addServer({
    required String label,
    required String address,
  }) {
    return ref
        .read(coreSessionProvider)
        .registerServer(label: label, address: address);
  }

  Future<void> removeServer(String id) async {
    await _run(() => ref.read(coreSessionProvider).removeServer(id: id));
  }

  Future<bool> connect({required String id, required String nickname}) {
    return _run(() async {
      // 先记下目标档案：状态事件只带客户端 id，界面需要知道连的是哪台服务器。
      state = state.copyWith(
        activeServerId: id,
        messages: const [],
        speaking: const {},
      );
      // 频道/成员快照由 actor 在连接成功后主动推送，不再额外拉一遍。
      await ref.read(coreSessionProvider).connect(id: id, nickname: nickname);
    });
  }

  Future<bool> disconnect() =>
      _run(() => ref.read(coreSessionProvider).disconnect());

  /// 返回是否真的换了频道：调用方要按结果决定要不要把界面停在目标频道。
  Future<bool> joinChannel(int channelId, {String? password}) async {
    final clientId = state.selfClientId;
    if (clientId == null) {
      return false;
    }
    return _run(() async {
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
      _notify(describeCoreError(error));
    }
  }

  Future<void> setDeafened(bool deafened) async {
    try {
      await ref.read(coreSessionProvider).setDeafened(deafened: deafened);
    } on CoreError catch (error) {
      _notify(describeCoreError(error));
    }
  }

  Future<void> setAway(bool away) async {
    try {
      await ref.read(coreSessionProvider).setAway(away: away);
    } on CoreError catch (error) {
      _notify(describeCoreError(error));
    }
  }

  Future<void> setPttMode(bool enabled) async {
    try {
      await ref.read(coreSessionProvider).setPttMode(enabled: enabled);
    } on CoreError catch (error) {
      _notify(describeCoreError(error));
    }
  }

  Future<void> setPttActive(bool active) async {
    if (!state.pttMode) {
      return;
    }
    try {
      await ref.read(coreSessionProvider).setPttActive(active: active);
    } on CoreError catch (error) {
      _notify(describeCoreError(error));
    }
  }

  Future<void> cancelIdentityUpgrade() async {
    try {
      await ref.read(coreSessionProvider).cancelIdentityUpgrade();
    } on CoreError catch (error) {
      _notify(describeCoreError(error));
    }
  }

  /// 掉线后是否自动重连。策略在 Rust 侧，这里只转发开关。
  Future<void> setAutoReconnect(bool enabled) async {
    await _run(
      () => ref.read(coreSessionProvider).setAutoReconnect(enabled: enabled),
    );
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
      _notify('还没有进入任何频道，无法发送频道消息。');
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
      _notify(describeCoreError(error));
    }
  }

  void _notify(String message, {NoticeTone tone = NoticeTone.error}) {
    ref.read(noticeCenterProvider.notifier).show(message, tone: tone);
  }

  /// 连接失败或被拒：除了提示，还要给连接页一个可以监听的序号。
  void _notifyFailure(String message) {
    _notify(message);
    state = state.copyWith(failureSeq: state.failureSeq + 1);
  }

  /// 命令的统一外壳：置忙，把 `CoreError` 收敛成右上角提示。返回命令是否成功，
  /// 让需要的调用方（如加入频道）能据此回滚自己先做的界面假设。
  Future<bool> _run(Future<void> Function() action) async {
    state = state.copyWith(busy: true);
    try {
      await action();
      return true;
    } on CoreError catch (error) {
      _notify(describeCoreError(error));
      return false;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  void _onEvent(CoreEvent event) {
    final current = state;
    switch (event) {
      case CoreEvent_State(state: final next):
        if (next is CoreSessionState_Disconnected) {
          // 采集/播放随断开停止，电平流不会再来新样本；主动清零，
          // 避免重连前停留在最后一帧。
          _latestLevels = VoiceLevels.silent;
          _levels.add(_latestLevels);
        }
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
        );
        final message = voice.message;
        if (message == null) {
          _lastVoiceNotice = null;
        } else if (message != _lastVoiceNotice) {
          _lastVoiceNotice = message;
          _notify(message);
        }
      case CoreEvent_Speaking(:final clientIds):
        state = current.copyWith(speaking: clientIds.toSet());
      case CoreEvent_SelfSpeaking(:final speaking):
        state = current.copyWith(selfSpeaking: speaking);
      case CoreEvent_Levels(:final mic, :final received):
        _latestLevels = VoiceLevels(mic: mic, received: received);
        _levels.add(_latestLevels);
      case CoreEvent_IdentityUpgrade(:final to):
        state = current.copyWith(identityUpgradeTarget: to);
        _notify('身份等级不足，正在提升到 $to…', tone: NoticeTone.info);
      case CoreEvent_IdentityUpgraded(:final level):
        state = current.copyWith(identityUpgradeTarget: null);
        _notify('身份等级已提升到 $level，正在重连…', tone: NoticeTone.info);
      case CoreEvent_TransferStarted():
      case CoreEvent_TransferProgress():
      case CoreEvent_TransferFinished():
        // 传输进度暂时没有界面入口；后端事件先保留，避免以后加 UI 时改协议。
        break;
      case CoreEvent_Log():
        // 协议日志不进界面，避免刷屏。
        break;
      case CoreEvent_Denied(:final message):
        _notifyFailure(message);
      case CoreEvent_Failed(:final message):
        // 保留 activeServerId：掉线重连期间服务器栏仍然标着原服务器；
        // 用户主动断开由 State(Disconnected) 负责清空。
        state = current.copyWith(
          channels: const [],
          clients: const [],
          speaking: const {},
          identityUpgradeTarget: null,
        );
        _notifyFailure(message);
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

  /// `null` 表示回到默认宽度。
  void setChannelPanelWidth(double? width) {
    if (width == state.channelPanelWidth) {
      return;
    }
    _update(state.copyWith(channelPanelWidth: width));
  }

  void setVoiceMeterSource(VoiceMeterSource source) {
    if (source == state.voiceMeterSource) {
      return;
    }
    _update(state.copyWith(voiceMeterSource: source));
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
