import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../l10n/app_localizations.dart';
import 'models.dart';
import 'file_export.dart';
import 'image_host.dart';
import 'notices.dart';
import 'preferences.dart';
import 'server_icon.dart';
import 'voice_levels.dart';

final _localizationsProvider = Provider<AppLocalizations>((ref) {
  final code =
      ref.watch(preferencesProvider).locale ??
      PlatformDispatcher.instance.locale.languageCode;
  return lookupAppLocalizations(Locale(code == 'zh' ? 'zh' : 'en'));
});

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

final sessionAccessProvider = FutureProvider.autoDispose<AccessView>((
  ref,
) async {
  final target = ref.watch(
    sessionViewProvider.select(
      (v) => (v.connected, v.connectionEpoch, v.selfChannelId),
    ),
  );
  if (!target.$1) return const AccessView();
  return ref.read(coreSessionProvider).access();
});

final memberGroupsProvider = FutureProvider.autoDispose
    .family<List<MemberGroupView>, String>((ref, uid) {
      ref.watch(
        sessionViewProvider.select(
          (v) => (v.connectionEpoch, v.selfChannelId, v.connected),
        ),
      );
      return ref.read(coreSessionProvider).memberGroups(uid: uid);
    });

class SessionController extends Notifier<SessionView> {
  /// 只保留本次会话的消息；上限防止长时间挂着时无限增长。
  static const _messageLimit = 500;

  final _transferReplies = <int, Completer<bool>>{};
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
    ref.onDispose(() {
      for (final reply in _transferReplies.values) {
        if (!reply.isCompleted) reply.complete(false);
      }
    });
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
        channels: const [],
        clients: const [],
        messages: const [],
        chatScope: ChatScope.channel,
        directRecipientUid: null,
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
    }, passwordPrompt: true);
  }

  void selectChatScope(ChatScope scope) {
    state = state.copyWith(chatScope: scope);
  }

  void selectDirectRecipient(String uid) {
    state = state.copyWith(
      chatScope: ChatScope.direct,
      directRecipientUid: uid,
    );
  }

  void replyToMessage(ChatMessage message) {
    if (message.scope != ChatScope.direct || message.fromUid == state.selfUid) {
      return;
    }
    final peer = state.clients
        .where(
          (peer) =>
              peer.uid == message.fromUid && peer.id != state.selfClientId,
        )
        .firstOrNull;
    if (peer == null) {
      _notify(ref.read(_localizationsProvider).chatRecipientUnavailable);
      return;
    }
    selectDirectRecipient(peer.uid);
  }

  Future<bool> pokeClient(String uid, String message) async {
    if (!state.connected || state.busy) return false;
    final peer = state.clients
        .where((client) => client.uid == uid && client.id != state.selfClientId)
        .firstOrNull;
    final l10n = ref.read(_localizationsProvider);
    if (peer == null) {
      _notify(l10n.chatRecipientUnavailable);
      return false;
    }
    final sent = await _run(
      () => ref
          .read(coreSessionProvider)
          .poke(clientId: peer.id, message: message),
    );
    if (sent && ref.mounted) {
      _notify(l10n.pokeSent(peer.nickname), tone: NoticeTone.info);
    }
    return sent;
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

  /// 上传可能跨越服务器/频道切换；发送闭包绑定用户发起操作时的目标。
  Future<bool> Function(String) prepareMessageSender() {
    final target = _messageDestination;
    return (text) {
      if (!ref.mounted) return Future.value(false);
      if (target != _messageDestination) {
        _notify(ref.read(_localizationsProvider).chatDestinationChanged);
        return Future.value(false);
      }
      return sendMessage(text);
    };
  }

  Object get _messageDestination => (
    state.activeServerId,
    state.connectionEpoch,
    state.chatScope,
    state.chatScope == ChatScope.direct
        ? state.directRecipientUid
        : state.chatScope == ChatScope.channel
        ? state.selfChannelId
        : null,
  );

  Future<String?> uploadChatImage(Uint8List bytes) async {
    final l10n = ref.read(_localizationsProvider);
    try {
      final config = await ref.read(imageHostProvider.future);
      if (!ref.mounted) return null;
      if (config == null) {
        _notify(l10n.imageHostRequired);
        return null;
      }
      return await uploadImage(
        uploadBase: config.uploadBase,
        publicBase: config.publicBase,
        token: config.token.isEmpty ? null : config.token,
        bytes: bytes,
      );
    } on CoreError catch (error) {
      if (ref.mounted) _notify(describeCoreError(error));
      return null;
    } on Exception {
      if (ref.mounted) _notify(l10n.imageHostStorageFailed);
      return null;
    }
  }

  Future<PickedChatImage?> pickChatImage({required bool paste}) async {
    final l10n = ref.read(_localizationsProvider);
    try {
      final input = ref.read(imageInputProvider);
      return paste ? await input.paste() : await input.pick();
    } on ImageInputException catch (error) {
      if (ref.mounted) {
        _notify(switch (error.failure) {
          ImageInputFailure.tooLarge => l10n.chatImageTooLarge,
          ImageInputFailure.clipboardEmpty => l10n.chatClipboardEmpty,
        });
      }
    } on Exception {
      if (ref.mounted) _notify(l10n.chatImageInputFailed);
    }
    return null;
  }

  Future<bool> setMemberGroup(
    String uid,
    MemberGroupView group,
    bool enabled,
  ) async {
    final sent = await _run(
      () => ref
          .read(coreSessionProvider)
          .setMemberGroup(
            uid: uid,
            groupId: group.id,
            channelId: group.channelId,
            kind: group.kind,
            enabled: enabled,
          ),
    );
    if (ref.mounted) {
      ref.invalidate(memberGroupsProvider(uid));
      ref.invalidate(sessionAccessProvider);
    }
    return sent;
  }

  Future<bool> saveChannelFile(
    int channelId,
    String remotePath,
    String name, {
    String? password,
    ValueChanged<int>? onStarted,
  }) async {
    final l10n = ref.read(_localizationsProvider);
    final target = (state.activeServerId, state.connectionEpoch);
    final export = ref.read(fileExportProvider);
    Directory? directory;
    try {
      final root = await getTemporaryDirectory();
      directory = await Directory(root.path).createTemp('flspeak-download-');
      if (!ref.mounted) return false;
      if (!state.connected ||
          target != (state.activeServerId, state.connectionEpoch)) {
        _notify(l10n.fileConnectionChanged);
        return false;
      }
      final path = '${directory.path}/download';
      final downloaded = await downloadChannelFile(
        channelId,
        remotePath,
        path,
        password: password,
        onStarted: onStarted,
      );
      if (!downloaded || !ref.mounted) return false;
      final saved = await export(path, name);
      if (saved && ref.mounted) {
        _notify(l10n.fileDownloadSaved, tone: NoticeTone.info);
      }
      return saved;
    } on CoreError_ChannelPasswordRequired {
      rethrow;
    } on Exception {
      if (ref.mounted) _notify(l10n.fileDownloadFailed);
      return false;
    } finally {
      try {
        if (directory != null && await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } on FileSystemException {
        if (ref.mounted) _notify(l10n.fileDownloadFailed);
      }
    }
  }

  Future<bool> downloadChannelFile(
    int channelId,
    String path,
    String localPath, {
    String? password,
    ValueChanged<int>? onStarted,
  }) async {
    int? transferId;
    final started = await _run(() async {
      transferId = await ref
          .read(coreSessionProvider)
          .downloadFile(
            remotePath: path,
            localPath: localPath,
            channelId: channelId,
            password: password,
          );
    }, passwordPrompt: true);
    if (!started || !ref.mounted) return false;
    final id = transferId!;
    onStarted?.call(id);
    final transfer = state.transfers[id];
    final success = transfer?.finished == true
        ? transfer!.error == null
        : await _transferReplies.putIfAbsent(id, Completer<bool>.new).future;
    if (!success && ref.mounted) {
      _notify(
        state.transfers[id]?.error ??
            ref.read(_localizationsProvider).fileDownloadFailed,
      );
    }
    return success;
  }

  /// 按当前范围发送。频道范围要求已进入某个频道，否则拒绝发送而不是发错地方。
  Future<bool> sendMessage(String text) async {
    final message = text.trim();
    if (message.isEmpty) {
      return false;
    }

    if (!state.connected || state.busy) return false;

    final scope = state.chatScope;
    final targetId = switch (scope) {
      ChatScope.channel => state.selfChannelId,
      ChatScope.server => 0,
      ChatScope.direct => state.directRecipient?.id,
    };
    if (targetId == null) {
      final l10n = ref.read(_localizationsProvider);
      _notify(
        scope == ChatScope.direct
            ? l10n.chatRecipientUnavailable
            : l10n.chatChannelUnavailable,
      );
      return false;
    }

    return _run(
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
  Future<bool> _run(
    Future<void> Function() action, {
    bool passwordPrompt = false,
  }) async {
    state = state.copyWith(busy: true);
    try {
      await action();
      return true;
    } on CoreError catch (error) {
      if (passwordPrompt && error is CoreError_ChannelPasswordRequired) rethrow;
      if (ref.mounted) _notify(describeCoreError(error));
      return false;
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  void _onEvent(CoreEvent event) {
    final current = state;
    switch (event) {
      case CoreEvent_AccessChanged():
        ref.invalidate(sessionAccessProvider);
        ref.invalidate(memberGroupsProvider);
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
            chatScope: ChatScope.channel,
            directRecipientUid: null,
            busy: false,
          ),
          _ => current.copyWith(
            state: next,
            connectionEpoch:
                next is CoreSessionState_Connected && !current.connected
                ? current.connectionEpoch + 1
                : current.connectionEpoch,
          ),
        };
      case CoreEvent_Servers(:final profiles):
        state = current.copyWith(servers: profiles);
      case CoreEvent_Snapshot(:final channels, :final clients):
        ref.invalidate(sessionAccessProvider);
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
      case CoreEvent_Poked(:final from, :final message):
        _notify(
          ref.read(_localizationsProvider).pokeReceived(from, message),
          tone: NoticeTone.info,
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
      case CoreEvent_TransferStarted(
        :final id,
        :final remotePath,
        :final total,
      ):
        final transfers = {...current.transfers};
        if (transfers.length >= 32) {
          final old = transfers.keys
              .where((key) => transfers[key]!.finished)
              .firstOrNull;
          if (old != null) transfers.remove(old);
        }
        transfers[id] = FileTransfer(remotePath: remotePath, total: total);
        state = current.copyWith(transfers: transfers);
      case CoreEvent_TransferProgress(:final id, :final transferred):
        final transfer = current.transfers[id];
        if (transfer != null) {
          state = current.copyWith(
            transfers: {
              ...current.transfers,
              id: FileTransfer(
                remotePath: transfer.remotePath,
                total: transfer.total,
                transferred: transferred,
              ),
            },
          );
        }
      case CoreEvent_TransferFinished(:final id, :final error):
        final transfer =
            current.transfers[id] ??
            const FileTransfer(remotePath: '', total: 0);
        state = current.copyWith(
          transfers: {
            ...current.transfers,
            id: FileTransfer(
              remotePath: transfer.remotePath,
              total: transfer.total,
              transferred: error == null
                  ? transfer.total
                  : transfer.transferred,
              finished: true,
              error: error,
            ),
          },
        );
        _transferReplies.remove(id)?.complete(error == null);
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

  void setServerIcon(String serverId, ServerIcon icon) {
    _update(
      state.copyWith(
        serverIcons: Map.unmodifiable({...state.serverIcons, serverId: icon}),
      ),
    );
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
