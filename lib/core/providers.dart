import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../l10n/app_localizations.dart';
import 'logging/logger.dart';
import 'models.dart';
import 'global_hotkey.dart';
import 'file_export.dart';
import 'image_host.dart';
import 'notices.dart';
import 'preferences.dart';
import 'server_icon.dart';
import 'stream_publisher.dart';
import 'stream_viewer.dart';
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

/// `preferences.json` 的绝对路径，设置页展示与复制用。同样在 `main()` 里覆盖。
final storePathProvider = Provider<String>(
  (ref) => throw StateError('storePathProvider 必须在 ProviderScope 里覆盖'),
);

/// 日志初始化失败的原因；null 表示文件日志可用。启动后提示一次。
final loggingFailureProvider = Provider<Object?>((ref) => null);

/// 启动阶段是否允许触发自动检查更新；测试可覆盖此标志验证启动更新流程。
final startupUpdateCheckEnabledProvider = Provider<bool>(
  (ref) => isRustLibInitialized,
);

/// 当前构建的版本号。Cargo workspace 与 Flutter 包版本由
/// `tool/bump_version.dart` 同步，这里以 Rust 侧为唯一来源。
final appVersionProvider = Provider<String>((ref) => appVersion());

/// `CoreEvent` 流收敛成的界面状态。
final sessionViewProvider = NotifierProvider<SessionController, SessionView>(
  SessionController.new,
);

/// 电平独立成流：50Hz 的更新只让电平条重建，不碰整个 `SessionView`。
final voiceLevelsProvider = StreamProvider<VoiceLevels>((ref) {
  return ref.watch(sessionViewProvider.notifier).levels;
});

final activePttHotkeyProvider = Provider<int?>((ref) {
  if (ref.watch(pttHotkeyRecordingProvider)) return null;
  return ref.watch(preferencesProvider.select((value) => value.pttHotkey));
});

final sessionAccessProvider = FutureProvider.autoDispose<AccessView>((
  ref,
) async {
  final target = ref.watch(
    sessionViewProvider.select(
      (v) =>
          (v.connected, v.connectionEpoch, v.selfChannelId, v.accessRevision),
    ),
  );
  if (!target.$1) return const AccessView();
  return ref.read(coreSessionProvider).access();
});

typedef MemberGroupTarget = ({int clientId, String uid});

final memberGroupsProvider = FutureProvider.autoDispose
    .family<List<MemberGroupView>, MemberGroupTarget>((ref, target) {
      ref.watch(
        sessionViewProvider.select(
          (v) => (
            v.connectionEpoch,
            v.selfChannelId,
            v.connected,
            v.accessRevision,
          ),
        ),
      );
      return ref
          .read(coreSessionProvider)
          .memberGroups(uid: target.uid, clientId: target.clientId);
    });

/// 频道简介缓存；同一连接内共用，重连或切服销毁旧请求。
final channelDescriptionProvider = FutureProvider.autoDispose
    .family<String, int>((ref, channelId) async {
      final session = ref.watch(
        sessionViewProvider.select(
          (v) => (v.activeServerId, v.connectionEpoch, v.connected),
        ),
      );
      if (!session.$3 || session.$1 == null) {
        throw StateError('Channel description requires an active connection');
      }
      return ref
          .read(coreSessionProvider)
          .channelDescription(channelId: channelId);
    }, retry: (retryCount, error) => null);

class SessionController extends Notifier<SessionView> {
  /// 只保留本次会话的消息；上限防止长时间挂着时无限增长。
  static const _messageLimit = 500;

  final _transferReplies = <int, Completer<bool>>{};
  final _levels = StreamController<VoiceLevels>.broadcast();
  VoiceLevels _latestLevels = VoiceLevels.silent;
  int _pendingActions = 0;
  int _serversRevision = 0;
  String? _connectingServerId;
  bool _awaitingDisconnect = false;
  bool _samplingNetwork = false;

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
    final revision = _serversRevision;
    try {
      final servers = await session.listServers();
      if (ref.mounted && revision == _serversRevision) {
        state = state.copyWith(servers: servers);
      }
    } on CoreError catch (error) {
      if (ref.mounted && revision == _serversRevision) {
        _notifyCoreError(error);
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

  Future<ServerProfileView> updateServer({
    required String id,
    required String label,
    required String address,
  }) async {
    final profile = await ref
        .read(coreSessionProvider)
        .updateServer(id: id, label: label, address: address);
    if (ref.mounted && profile.id != id) {
      if (state.activeServerId == id) {
        state = state.copyWith(activeServerId: profile.id);
      }
      ref
          .read(preferencesProvider.notifier)
          .moveServerPreferences(id, profile.id);
    }
    return profile;
  }

  Future<bool> connect({required String id, required String nickname}) async {
    if (!ref.mounted || state.busy || state.connecting) return false;
    if (state.connected && state.activeServerId == id) return true;
    _connectingServerId = id;
    _awaitingDisconnect = true;
    var attempted = false;
    final connected = await _run(() async {
      final session = ref.read(coreSessionProvider);
      // 核心可能已进入界面尚未收到的重连流程，显式重置句柄再连接。
      await session.disconnect();
      if (!ref.mounted || _connectingServerId != id) return;
      attempted = true;
      await session.connect(id: id, nickname: nickname);
    }, recordFailure: true);
    return connected && attempted;
  }

  Future<bool> disconnect() {
    _connectingServerId = null;
    return _run(() => ref.read(coreSessionProvider).disconnect());
  }

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
    }, passwordPrompt: true);
  }

  void selectChatScope(ChatScope scope) {
    state = state.copyWith(
      chatScope: scope,
      unreadScopes: scope == ChatScope.direct
          ? state.unreadScopes
          : ({...state.unreadScopes}..remove(scope)),
      unreadPeers: scope == ChatScope.direct
          ? _clearPeerUnread(state.unreadPeers, state.directRecipientUid)
          : state.unreadPeers,
    );
  }

  void selectDirectRecipient(String uid, {int? clientId}) {
    state = state.copyWith(
      chatScope: ChatScope.direct,
      directRecipientUid: uid,
      directRecipientId: clientId,
      unreadPeers: _clearPeerUnread(state.unreadPeers, uid),
    );
    _probeDirectRecipient();
  }

  void _probeDirectRecipient() {
    if (!state.connected || state.chatScope != ChatScope.direct) return;
    final recipient = state.directRecipient;
    if (recipient == null) return;
    if (recipient.clientType == ClientType.standard) {
      unawaited(queryPeerIdentity(recipient.id));
    } else if (recipient.capabilities.contains('chat:slash_commands') &&
        recipient.botCommands == null) {
      unawaited(fetchBotCommands(recipient.id, recipient.uid));
    }
  }

  static Set<String> _clearPeerUnread(Set<String> peers, String? uid) {
    if (uid == null || !peers.contains(uid)) return peers;
    return {...peers}..remove(uid);
  }

  /// 新消息落在当前查看范围之外时，记录来源给输入框范围按钮显示红点。
  static ({Set<ChatScope> scopes, Set<String> peers}) _unreadFor(
    SessionView view,
    ChatMessage message,
  ) {
    if (view.isOwnMessage(message)) {
      return (scopes: view.unreadScopes, peers: view.unreadPeers);
    }
    switch (message.scope) {
      case ChatScope.channel:
        if (view.chatScope == ChatScope.channel) {
          return (scopes: view.unreadScopes, peers: view.unreadPeers);
        }
        return (
          scopes: {...view.unreadScopes, ChatScope.channel},
          peers: view.unreadPeers,
        );
      case ChatScope.server:
        if (view.chatScope == ChatScope.server) {
          return (scopes: view.unreadScopes, peers: view.unreadPeers);
        }
        return (
          scopes: {...view.unreadScopes, ChatScope.server},
          peers: view.unreadPeers,
        );
      case ChatScope.direct:
        final peer = message.peerUid;
        if (peer.isEmpty ||
            (view.chatScope == ChatScope.direct &&
                peer == view.directRecipientUid)) {
          return (scopes: view.unreadScopes, peers: view.unreadPeers);
        }
        return (scopes: view.unreadScopes, peers: {...view.unreadPeers, peer});
    }
  }

  void replyToMessage(ChatMessage message) {
    if (message.scope != ChatScope.direct || state.isOwnMessage(message)) {
      return;
    }
    ClientView? peer;
    if (message.fromId > 0) {
      peer = state.clients
          .where(
            (client) =>
                client.id == message.fromId &&
                client.uid == message.fromUid &&
                client.id != state.selfClientId,
          )
          .firstOrNull;
    }
    if (peer == null) {
      final matches = state.clients
          .where(
            (client) =>
                client.uid == message.fromUid &&
                client.id != state.selfClientId,
          )
          .toList();
      if (matches.length == 1) {
        peer = matches.first;
      }
    }
    if (peer == null) {
      _notify(ref.read(_localizationsProvider).chatRecipientUnavailable);
      return;
    }
    selectDirectRecipient(
      peer.uid,
      clientId: message.fromId > 0 ? peer.id : null,
    );
  }

  Future<bool> pokeClient(String uid, String message, {int? clientId}) async {
    if (!state.connected || state.busy) return false;
    final matches = state.clients
        .where(
          (client) =>
              client.uid == uid &&
              client.id != state.selfClientId &&
              (clientId == null || client.id == clientId),
        )
        .toList();
    final peer = matches.length == 1 ? matches.first : null;
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

  Future<bool> kickClient(
    ClientView recipient,
    KickTarget target,
    String reason,
    int connectionEpoch,
  ) async {
    if (!state.connected || state.busy) return false;
    final peer = state.clients
        .where(
          (client) =>
              client.id == recipient.id &&
              client.uid == recipient.uid &&
              client.id != state.selfClientId,
        )
        .firstOrNull;
    final l10n = ref.read(_localizationsProvider);
    if (peer == null ||
        (target == KickTarget.channel &&
            peer.channelId != recipient.channelId)) {
      _notify(l10n.kickTargetUnavailable);
      return false;
    }
    final sent = await _run(
      () => ref
          .read(coreSessionProvider)
          .kick(
            uid: recipient.uid,
            clientId: recipient.id,
            channelId: recipient.channelId,
            target: target,
            reason: reason.trim(),
            connectionEpoch: connectionEpoch,
          ),
    );
    if (sent && ref.mounted) {
      _notify(l10n.kickSent(peer.nickname), tone: NoticeTone.info);
    }
    return sent;
  }

  /// 静音只停发送；deafen 同时停发送并静音播放。状态以 Rust 的 Voice 事件为准。
  Future<void> setMuted(bool muted) async {
    try {
      await ref.read(coreSessionProvider).setMuted(muted: muted);
    } on CoreError catch (error) {
      _notifyCoreError(error);
    }
  }

  Future<void> setDeafened(bool deafened) async {
    try {
      await ref.read(coreSessionProvider).setDeafened(deafened: deafened);
    } on CoreError catch (error) {
      _notifyCoreError(error);
    }
  }

  Future<void> setAway(bool away) async {
    try {
      await ref.read(coreSessionProvider).setAway(away: away);
    } on CoreError catch (error) {
      _notifyCoreError(error);
    }
  }

  Future<void> setPttMode(bool enabled) async {
    try {
      await ref.read(coreSessionProvider).setPttMode(enabled: enabled);
    } on CoreError catch (error) {
      _notifyCoreError(error);
    }
  }

  Future<void> setPttActive(bool active) async {
    if (!ref.mounted || !state.pttMode) {
      return;
    }
    try {
      await ref.read(coreSessionProvider).setPttActive(active: active);
    } on CoreError catch (error) {
      _notifyCoreError(error);
    }
  }

  Future<void> cancelIdentityUpgrade() async {
    try {
      await ref.read(coreSessionProvider).cancelIdentityUpgrade();
    } on CoreError catch (error) {
      _notifyCoreError(error);
    }
  }

  /// 掉线后是否自动重连。策略在 Rust 侧，这里只转发开关。
  Future<void> setAutoReconnect(bool enabled) async {
    await _run(
      () => ref.read(coreSessionProvider).setAutoReconnect(enabled: enabled),
    );
  }

  /// 加入指定成员正在共享的屏幕流并准备 WebRTC 观看会话。
  Future<bool> watchStream(StreamView stream) async {
    if (!state.connected) return false;
    final previousId = state.watchingStreamId;
    if (previousId != null && previousId != stream.id) {
      try {
        await ref.read(coreSessionProvider).leaveStream(streamId: previousId);
      } on CoreError catch (_) {
        // 切换观看流时旧流退出失败不阻塞新流加入。
      }
    }
    await ref
        .read(streamViewerProvider.notifier)
        .prepareWatch(streamId: stream.id, sourceClientId: stream.clientId);
    if (!ref.mounted) return false;
    state = state.copyWith(watchingStreamId: stream.id);
    try {
      await ref
          .read(coreSessionProvider)
          .joinStream(streamId: stream.id, sourceClid: stream.clientId);
      return ref.mounted;
    } on CoreError catch (error) {
      if (ref.mounted) {
        state = state.copyWith(watchingStreamId: null);
        await ref.read(streamViewerProvider.notifier).closeSession();
        _notifyCoreError(error);
      }
      return false;
    }
  }

  /// 关闭当前正在观看的屏幕流并销毁 WebRTC 与渲染器资源。
  Future<void> leaveStream([String? streamId]) async {
    final targetId =
        streamId ??
        state.watchingStreamId ??
        ref.read(streamViewerProvider).streamId;
    if (state.watchingStreamId != null) {
      state = state.copyWith(watchingStreamId: null);
    }
    await ref.read(streamViewerProvider.notifier).closeSession();
    if (targetId == null || !ref.mounted) return;
    try {
      await ref.read(coreSessionProvider).leaveStream(streamId: targetId);
    } on CoreError catch (error) {
      _notifyCoreError(error);
    }
  }

  /// 开启桌面屏幕或窗口共享。
  Future<bool> startScreenShare({
    required String sourceId,
    required String sourceName,
    ScreenShareResolutionPreset? resolution,
    ScreenShareFrameRatePreset? frameRate,
    bool audio = false,
  }) async {
    if (!state.connected) return false;
    try {
      return await ref
          .read(streamPublisherProvider.notifier)
          .startScreenShare(
            sourceId: sourceId,
            sourceName: sourceName,
            resolution: resolution,
            frameRate: frameRate,
            audio: audio,
          );
    } on CoreError catch (error) {
      if (ref.mounted) {
        _notifyCoreError(error);
      }
      return false;
    } on Object {
      if (ref.mounted) {
        _notify(ref.read(_localizationsProvider).streamPublishFailed);
      }
      return false;
    }
  }

  /// 停止当前屏幕共享并释放全部推流 WebRTC 资源。
  Future<void> stopScreenShare() async {
    await ref.read(streamPublisherProvider.notifier).stopScreenShare();
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
        ? (state.directRecipientUid, state.directRecipient?.id)
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
      if (ref.mounted) {
        _notifyCoreError(error);
      }
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
    bool enabled, {
    int? clientId,
  }) async {
    final matches = state.clients
        .where(
          (client) =>
              client.uid == uid && (clientId == null || client.id == clientId),
        )
        .toList();
    if (matches.length != 1) {
      _notify(ref.read(_localizationsProvider).kickTargetUnavailable);
      return false;
    }
    final target = (clientId: matches.single.id, uid: uid);
    final sent = await _run(
      () => ref
          .read(coreSessionProvider)
          .setMemberGroup(
            uid: uid,
            clientId: target.clientId,
            groupId: group.id,
            channelId: group.channelId,
            kind: group.kind,
            enabled: enabled,
          ),
    );
    if (sent && ref.mounted) {
      state = state.copyWith(accessRevision: state.accessRevision + 1);
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
    final key = (state.connectionEpoch, channelId);
    if (state.activeFileDownloads.containsKey(key)) return false;
    final target = (state.activeServerId, state.connectionEpoch);
    final export = ref.read(fileExportProvider);
    state = state.copyWith(
      activeFileDownloads: {...state.activeFileDownloads, key: null},
    );
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
        onStarted: (id) {
          if (ref.mounted && state.activeFileDownloads.containsKey(key)) {
            state = state.copyWith(
              activeFileDownloads: {...state.activeFileDownloads, key: id},
            );
          }
          onStarted?.call(id);
        },
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
      if (ref.mounted && state.activeFileDownloads.containsKey(key)) {
        final next = {...state.activeFileDownloads}..remove(key);
        state = state.copyWith(activeFileDownloads: next);
      }
      try {
        if (directory != null && await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } on FileSystemException {
        if (ref.mounted) _notify(l10n.fileCleanupFailed);
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
      _notifyCoreError(error);
    }
  }

  /// 遥测面板打开期间的按需采样。失败时保留现有探测数据，不打断连接。
  Future<void> sampleNetwork() async {
    if (!state.connected || _samplingNetwork) return;
    _samplingNetwork = true;
    try {
      await ref.read(coreSessionProvider).sampleNetwork();
    } on CoreError {
      // 服务器不允许查询连接信息时，面板继续显示已有的探测统计。
    } finally {
      _samplingNetwork = false;
    }
  }

  void setNetworkPanelPinned(bool pinned) {
    state = state.copyWith(networkPanelPinned: pinned);
  }

  /// 对未识别身份的私聊节点发起单播身份查询。
  Future<void> queryPeerIdentity(int targetClid) async {
    if (!state.connected) return;
    try {
      await ref
          .read(coreSessionProvider)
          .queryPeerIdentity(targetClid: targetClid);
    } on CoreError {
      // 对端不支持或服务器禁用 plugincmd 时静默降级为普通客户端。
    }
  }

  /// 按需向声明支持 `chat:slash_commands` 的节点拉取命令清单。
  Future<void> fetchBotCommands(int targetClid, String targetUid) async {
    if (!state.connected || targetUid.isEmpty) return;
    try {
      await ref
          .read(coreSessionProvider)
          .fetchBotCommands(targetClid: targetClid, targetUid: targetUid);
    } on CoreError {
      // 拉取失败不阻塞输入框。
    }
  }

  void _notifyCoreError(CoreError error) {
    if (ref.mounted) {
      _notify(describeCoreError(error, ref.read(_localizationsProvider)));
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
    bool recordFailure = false,
  }) async {
    if (!ref.mounted) return false;
    _pendingActions++;
    state = state.copyWith(busy: true);
    try {
      await action();
      return ref.mounted;
    } on CoreError catch (error) {
      if (passwordPrompt && error is CoreError_ChannelPasswordRequired) rethrow;
      if (ref.mounted) {
        if (recordFailure) {
          _notifyFailure(
            describeCoreError(error, ref.read(_localizationsProvider)),
          );
        } else {
          _notifyCoreError(error);
        }
      }
      return false;
    } finally {
      _pendingActions--;
      if (ref.mounted) state = state.copyWith(busy: _pendingActions != 0);
    }
  }

  void _onEvent(CoreEvent event) {
    final current = state;
    switch (event) {
      case CoreEvent_Network(:final telemetry):
        if (current.connected) state = current.copyWith(network: telemetry);
      case CoreEvent_AccessChanged():
        state = current.copyWith(accessRevision: current.accessRevision + 1);
      case CoreEvent_State(state: final next):
        if (next is CoreSessionState_Disconnected) _awaitingDisconnect = false;
        if (next is! CoreSessionState_Connected) {
          _latestLevels = VoiceLevels.silent;
          _levels.add(_latestLevels);
          unawaited(ref.read(streamViewerProvider.notifier).closeSession());
          unawaited(
            ref
                .read(streamPublisherProvider.notifier)
                .stopScreenShare(notifyServer: false),
          );
        } else if (current.selfChannelId != null &&
            next.channelId != current.selfChannelId) {
          unawaited(ref.read(streamViewerProvider.notifier).closeSession());
          unawaited(
            ref
                .read(streamPublisherProvider.notifier)
                .stopScreenShare(notifyServer: false),
          );
        }
        state = switch (next) {
          CoreSessionState_Disconnected() => current.copyWith(
            network: null,
            networkPanelPinned: false,
            state: next,
            activeServerId: null,
            channels: const [],
            clients: const [],
            streams: const [],
            watchingStreamId: null,
            speaking: const {},
            selfSpeaking: false,
            identityUpgradeTarget: null,
            chatScope: ChatScope.channel,
            directRecipientUid: null,
            directRecipientId: null,
            activeFileDownloads: const {},
            busy: _pendingActions != 0,
          ),
          CoreSessionState_Connecting() => current.copyWith(
            network: null,
            networkPanelPinned: false,
            state: next,
            activeServerId: _awaitingDisconnect
                ? current.activeServerId
                : _connectingServerId,
            channels: const [],
            clients: const [],
            streams: const [],
            watchingStreamId: null,
            messages: const [],
            chatScope: ChatScope.channel,
            directRecipientUid: null,
            directRecipientId: null,
            unreadScopes: const {},
            unreadPeers: const {},
            speaking: const {},
            selfSpeaking: false,
          ),
          CoreSessionState_Reconnecting() => current.copyWith(
            network: null,
            networkPanelPinned: false,
            state: next,
            activeServerId:
                current.activeServerId ??
                (_awaitingDisconnect ? null : _connectingServerId),
            channels: const [],
            clients: const [],
            streams: const [],
            watchingStreamId: null,
            speaking: const {},
            selfSpeaking: false,
          ),
          _ => current.copyWith(
            state: next,
            activeServerId: _awaitingDisconnect || current.connected
                ? current.activeServerId
                : _connectingServerId ?? current.activeServerId,
            connectionEpoch:
                next is CoreSessionState_Connected && !current.connected
                ? current.connectionEpoch + 1
                : current.connectionEpoch,
          ),
        };
        if (next is CoreSessionState_Connected && !_awaitingDisconnect) {
          _connectingServerId = null;
        }
      case CoreEvent_Servers(:final profiles):
        _serversRevision++;
        state = current.copyWith(servers: profiles);
      case CoreEvent_Snapshot(:final channels, :final clients):
        state = current.copyWith(
          channels: channels,
          clients: clients,
          accessRevision: current.accessRevision + 1,
        );
        final recipient = state.directRecipient;
        if (state.chatScope == ChatScope.direct &&
            recipient != null &&
            recipient.capabilities.contains('chat:slash_commands') &&
            recipient.botCommands == null) {
          unawaited(fetchBotCommands(recipient.id, recipient.uid));
        }
      case CoreEvent_History(:final messages):
        state = current.copyWith(
          messages: messages.map(ChatMessage.fromCore).toList(),
          unreadScopes: const {},
          unreadPeers: const {},
        );
      case CoreEvent_TextMessage(
        :final from,
        :final fromUid,
        :final fromId,
        :final message,
        :final targetMode,
        :final targetId,
        :final peerUid,
        :final at,
      ):
        final received = ChatMessage(
          from: from,
          fromUid: fromUid,
          fromId: fromId,
          text: message,
          at: DateTime.fromMillisecondsSinceEpoch(at),
          scope: ChatScope.fromProtocol(targetMode),
          targetId: targetId,
          peerUid: peerUid,
        );
        final unread = _unreadFor(current, received);
        final appended = [...current.messages, received];
        state = current.copyWith(
          messages: appended.length > _messageLimit
              ? appended.sublist(appended.length - _messageLimit)
              : appended,
          unreadScopes: unread.scopes,
          unreadPeers: unread.peers,
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
        final existing = current.clients
            .where(
              (client) =>
                  client.id == id || (uid.isNotEmpty && client.uid == uid),
            )
            .firstOrNull;
        final others = current.clients.where((client) => client.id != id);
        state = current.copyWith(
          clients: [
            ...others,
            ClientView(
              id: id,
              nickname: nickname,
              uid: uid,
              channelId: channelId,
              clientType: existing?.clientType ?? ClientType.standard,
              appName: existing?.appName,
              appVersion: existing?.appVersion,
              capabilities: existing?.capabilities ?? const [],
              botCommands: existing?.botCommands,
            ),
          ],
        );
      case CoreEvent_ClientLeft(:final id):
        state = current.copyWith(
          clients: current.clients.where((client) => client.id != id).toList(),
        );
      case CoreEvent_ClientMoved(:final id, :final channelId):
        if (id == current.selfClientId && channelId != current.selfChannelId) {
          unawaited(ref.read(streamViewerProvider.notifier).closeSession());
          unawaited(
            ref
                .read(streamPublisherProvider.notifier)
                .stopScreenShare(notifyServer: false),
          );
        }
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
                  clientType: client.clientType,
                  appName: client.appName,
                  appVersion: client.appVersion,
                  capabilities: client.capabilities,
                  botCommands: client.botCommands,
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
                  clientType: client.clientType,
                  appName: client.appName,
                  appVersion: client.appVersion,
                  capabilities: client.capabilities,
                  botCommands: client.botCommands,
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
        // 断开后可能仍有在途的轻量指标，不能让它重新点亮电平条。
        if (!current.connected) return;
        _latestLevels = VoiceLevels(mic: mic, received: received);
        _levels.add(_latestLevels);
      case CoreEvent_IdentityUpgrade(:final to):
        state = current.copyWith(identityUpgradeTarget: to);
        _notify(
          ref.read(_localizationsProvider).identityUpgrading(to),
          tone: NoticeTone.info,
        );
      case CoreEvent_IdentityUpgraded(:final level):
        state = current.copyWith(identityUpgradeTarget: null);
        _notify(
          ref.read(_localizationsProvider).identityUpgraded(level),
          tone: NoticeTone.info,
        );
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
      case CoreEvent_Streams(:final streams, :final watching):
        state = current.copyWith(streams: streams, watchingStreamId: watching);
        unawaited(
          ref
              .read(streamViewerProvider.notifier)
              .syncStreams(streams: streams, watchingStreamId: watching),
        );
      case CoreEvent_StreamOffer(
        :final streamId,
        :final sourceClientId,
        :final sdp,
      ):
        if (current.watchingStreamId == null ||
            current.watchingStreamId == streamId) {
          state = current.copyWith(watchingStreamId: streamId);
          unawaited(
            ref
                .read(streamViewerProvider.notifier)
                .handleOffer(
                  streamId: streamId,
                  sourceClientId: sourceClientId,
                  sdp: sdp,
                ),
          );
        }
      case CoreEvent_StreamIceCandidate(
        :final streamId,
        :final sourceClientId,
        :final sdp,
        :final mid,
        :final mLine,
      ):
        unawaited(
          ref
              .read(streamViewerProvider.notifier)
              .handleRemoteIceCandidate(
                streamId: streamId,
                sourceClientId: sourceClientId,
                sdp: sdp,
                mid: mid,
                mLine: mLine,
              ),
        );
      case CoreEvent_StreamEnded(:final streamId, :final reason):
        if (current.watchingStreamId == streamId) {
          state = current.copyWith(watchingStreamId: null);
        }
        unawaited(
          ref
              .read(streamViewerProvider.notifier)
              .handleStreamEnded(streamId: streamId, reason: reason),
        );
        final l10n = ref.read(_localizationsProvider);
        switch (reason) {
          case StreamEndReason.sourceStopped:
            _notify(l10n.streamEndedStopped, tone: NoticeTone.info);
          case StreamEndReason.rejected:
            _notify(l10n.streamEndedRejected);
          case StreamEndReason.removed:
            _notify(l10n.streamEndedRemoved, tone: NoticeTone.info);
          case StreamEndReason.sourceLeft:
          case StreamEndReason.sourceMoved:
          case StreamEndReason.selfMoved:
          case StreamEndReason.disconnected:
          case StreamEndReason.left:
            break;
        }
      case CoreEvent_ScreenSharePublished(:final streamId):
        ref
            .read(streamPublisherProvider.notifier)
            .handlePublished(streamId: streamId);
      case CoreEvent_ScreenShareStopped():
        unawaited(ref.read(streamPublisherProvider.notifier).handleStopped());
      case CoreEvent_StreamViewerJoinRequested(
        :final streamId,
        :final viewerClid,
      ):
        unawaited(
          ref
              .read(streamPublisherProvider.notifier)
              .handleViewerJoinRequested(
                streamId: streamId,
                viewerClid: viewerClid,
              ),
        );
      case CoreEvent_PublisherSignalReceived(
        :final streamId,
        :final viewerClid,
        :final signal,
      ):
        unawaited(
          ref
              .read(streamPublisherProvider.notifier)
              .handlePublisherSignal(
                streamId: streamId,
                viewerClid: viewerClid,
                signal: signal,
              ),
        );
      case CoreEvent_StreamViewerLeft(:final streamId, :final viewerClid):
        unawaited(
          ref
              .read(streamPublisherProvider.notifier)
              .handleViewerLeft(streamId: streamId, viewerClid: viewerClid),
        );
      case CoreEvent_Log(:final level, :final message):
        // 协议日志不进界面，避免刷屏；调试模式输出以便排查。
        if (kDebugMode) {
          debugPrint('[Backend/$level] $message');
        }
        break;
      case CoreEvent_Denied(:final message):
        _notifyFailure(message);
      case CoreEvent_Failed(:final message):
        if (current.connected) {
          _notify(message);
        } else {
          state = current.copyWith(identityUpgradeTarget: null);
          _notifyFailure(message);
        }
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
    if (value == state.nickname) {
      return;
    }
    _update(state.copyWith(nickname: value));
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

  /// `null` 表示回到默认自适应高度。
  void setStreamViewerHeight(double? height) {
    if (height == state.streamViewerHeight) {
      return;
    }
    _update(state.copyWith(streamViewerHeight: height));
  }

  void setVoiceMeterSource(VoiceMeterSource source) {
    if (source == state.voiceMeterSource) {
      return;
    }
    _update(state.copyWith(voiceMeterSource: source));
  }

  void setScreenShareResolution(ScreenShareResolutionPreset preset) {
    if (preset == state.screenShareResolution) {
      return;
    }
    _update(state.copyWith(screenShareResolution: preset));
  }

  void setScreenShareFrameRate(ScreenShareFrameRatePreset preset) {
    if (preset == state.screenShareFrameRate) {
      return;
    }
    _update(state.copyWith(screenShareFrameRate: preset));
  }

  void setScreenShareCodec(ScreenShareCodecPreference codec) {
    if (codec == state.screenShareCodec) {
      return;
    }
    _update(state.copyWith(screenShareCodec: codec));
  }

  void setScreenShareDegradation(ScreenShareDegradationPreference degradation) {
    if (degradation == state.screenShareDegradation) {
      return;
    }
    _update(state.copyWith(screenShareDegradation: degradation));
  }

  void setAutoCheckUpdate(bool enabled) {
    if (enabled == state.autoCheckUpdate) {
      return;
    }
    _update(state.copyWith(autoCheckUpdate: enabled));
  }

  void setLogLevel(AppLogLevel level) {
    if (level == state.logLevel) {
      return;
    }
    _update(state.copyWith(logLevel: level));
    unawaited(syncLogLevel(level.talkerLevel, rustLevelId: level.id));
  }

  void setServerIcon(String serverId, ServerIcon icon) {
    _update(
      state.copyWith(
        serverIcons: Map.unmodifiable({...state.serverIcons, serverId: icon}),
      ),
    );
  }

  void moveServerPreferences(String oldId, String newId) {
    final icons = {...state.serverIcons};
    final icon = icons.remove(oldId);
    if (icon != null) icons[newId] = icon;
    final connected = {...state.lastConnected};
    final at = connected.remove(oldId);
    if (at != null) connected[newId] = at;
    _update(state.copyWith(serverIcons: icons, lastConnected: connected));
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
      final normalized = await ref.read(preferencesStoreProvider).save(next);
      state = state.copyWith(nickname: normalized.nickname);
    } on Object catch (error) {
      logError('保存 preferences 失败', error: error);
    }
  }
}
