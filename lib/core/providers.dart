import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../l10n/app_localizations.dart';
import 'audio_selection.dart';
import 'channel_display.dart';
import 'identity/identity.dart';
import 'image_host.dart';
import 'models.dart';
import 'notices.dart';
import 'platform/android_app_lifecycle.dart';
import 'platform/android_audio_permission.dart';
import 'platform/android_session_service.dart';
import 'platform/file_export.dart';
import 'platform/global_hotkey.dart';
import 'preferences.dart';
import 'stream_publisher.dart';
import 'stream_viewer.dart';

final appLocalizationsProvider = Provider<AppLocalizations>((ref) {
  final code =
      ref.watch(preferencesProvider).locale ??
      PlatformDispatcher.instance.locale.languageCode;
  return lookupAppLocalizations(Locale(code == 'zh' ? 'zh' : 'en'));
});

/// 在 `main()` 里用真实句柄覆盖；测试里用假的实现覆盖。
final coreSessionProvider = Provider<CoreSession>(
  (ref) => throw StateError(
    'coreSessionProvider must be overridden in ProviderScope',
  ),
);

final microphonePermissionProvider = Provider<MicrophonePermissionGateway>(
  (ref) => const AndroidAudioPermission(),
);

final androidAppLifecycleProvider = Provider<AndroidAppLifecycleGateway>(
  (ref) => const AndroidAppLifecycle(),
);

final androidSessionServiceProvider = Provider<AndroidSessionServiceGateway>(
  (ref) => const AndroidSessionService(),
);

AndroidSessionNotificationState buildAndroidSessionNotificationState({
  required SessionView view,
  required AppLocalizations l10n,
  required bool isSharingScreen,
  bool includeMediaProjection = false,
}) {
  final activeServer = view.activeServer;
  final rawLabel = activeServer?.label.trim() ?? '';
  final rawHost = activeServer?.host.trim() ?? '';
  final fallbackAddress = activeServer == null || rawHost.isEmpty
      ? ''
      : (rawHost.contains(':')
            ? '[$rawHost]:${activeServer.port}'
            : '$rawHost:${activeServer.port}');
  final serverName = rawLabel.isNotEmpty
      ? rawLabel
      : (fallbackAddress.isNotEmpty ? fallbackAddress : l10n.appName);

  final channelId = view.selfChannelId;
  final channel = channelId == null ? null : view.channelById(channelId);
  final channelName = channel == null ? null : channelDisplayName(channel);
  final title = channelName != null && channelName.isNotEmpty
      ? l10n.sessionNotificationTitle(serverName, channelName)
      : serverName;

  final String subtitle;
  if (view.reconnecting) {
    subtitle = l10n.sessionNotificationStatusReconnecting;
  } else {
    final voiceStatus = view.deafened
        ? l10n.sessionNotificationStatusDeafened
        : (view.muted
              ? l10n.sessionNotificationStatusMuted
              : l10n.sessionNotificationStatusInVoice);
    if (isSharingScreen) {
      subtitle = !view.deafened && !view.muted
          ? l10n.sessionNotificationStatusSharingScreen
          : l10n.sessionNotificationStatusCombined(
              l10n.sessionNotificationStatusSharingScreen,
              voiceStatus,
            );
    } else {
      subtitle = voiceStatus;
    }
  }

  return AndroidSessionNotificationState(
    title: title,
    subtitle: subtitle,
    channelName: l10n.sessionNotificationChannelName,
    muteActionLabel: view.muted ? l10n.voiceUnmute : l10n.voiceMute,
    stopScreenShareActionLabel: l10n.streamStopShare,
    disconnectActionLabel: l10n.sessionNotificationDisconnect,
    isMuted: view.muted,
    isSharingScreen: isSharingScreen,
    includeMediaProjection: includeMediaProjection,
    sessionEpoch: view.connectionEpoch,
  );
}

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// `preferences.json` 的绝对路径，设置页展示与复制用。同样在 `main()` 里覆盖。
final storePathProvider = Provider<String>(
  (ref) =>
      throw StateError('storePathProvider must be overridden in ProviderScope'),
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

/// 电平独立成流：50Hz 的更新只让电平条重建，并在无活跃订阅时自动释放底层监听。
final voiceLevelsProvider = StreamProvider.autoDispose<VoiceLevels>((ref) {
  return ref.watch(sessionViewProvider.notifier).levels;
});

final activePttHotkeyProvider = Provider<int?>((ref) {
  if (ref.watch(pttHotkeyRecordingProvider)) return null;
  final pttMode = ref.watch(sessionViewProvider.select((v) => v.pttMode));
  if (!pttMode) return null;
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

extension AccessViewCapabilities on AccessView {
  bool canKick(KickTarget target) => switch (target) {
    KickTarget.channel => canKickChannel,
    KickTarget.server => canKickServer,
  };
}

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

/// 同一连接内共用图标；重连或切换服务器会销毁旧请求的缓存。
final channelIconProvider = FutureProvider.autoDispose.family<Uint8List, int>((
  ref,
  iconId,
) async {
  final session = ref.watch(
    sessionViewProvider.select(
      (view) => (view.activeServerId, view.connectionEpoch, view.connected),
    ),
  );
  if (!session.$3 || session.$1 == null) {
    throw StateError('Channel icon requires an active connection');
  }
  return ref.read(coreSessionProvider).fetchIcon(iconId: iconId);
}, retry: (retryCount, error) => null);

class SessionController extends Notifier<SessionView> {
  final _transferReplies = <int, Completer<bool>>{};
  final _levels = StreamController<VoiceLevels>.broadcast();
  final _avatarUpdates = StreamController<String>.broadcast(sync: true);
  VoiceLevels _latestLevels = VoiceLevels.silent;
  int _pendingActions = 0;
  int _serversRevision = 0;
  int _serverIconsRevision = 0;
  String? _connectingServerId;
  bool _awaitingDisconnect = false;
  bool _samplingNetwork = false;
  bool _notificationPermissionRequested = false;
  bool _androidSessionServiceActive = false;
  bool _androidSessionServiceStarted = false;
  bool _androidMediaProjectionActive = false;
  AndroidSessionNotificationState? _lastAndroidNotificationState;
  int _androidSessionServiceOpGen = 0;
  Future<bool>? _inFlightAndroidSync;

  /// 最近一次已提示的语音错误；Voice 事件重复带同一句时不再刷新提示。
  String? _lastVoiceNotice;

  Stream<VoiceLevels> get levels => _levels.stream;
  Stream<String> get avatarUpdates => _avatarUpdates.stream;

  @override
  SessionView build() {
    _notificationPermissionRequested = false;
    _androidSessionServiceActive = false;
    _androidSessionServiceStarted = false;
    _androidMediaProjectionActive = false;
    _lastAndroidNotificationState = null;
    _androidSessionServiceOpGen = 0;
    _inFlightAndroidSync = null;

    final session = ref.watch(coreSessionProvider);
    final subscription = session.events().listen(_onEvent);
    ref.onDispose(subscription.cancel);
    ref.onDispose(_levels.close);
    ref.onDispose(_avatarUpdates.close);
    ref.onDispose(() {
      for (final reply in _transferReplies.values) {
        if (!reply.isCompleted) reply.complete(false);
      }
    });

    final androidSessionService = ref.watch(androidSessionServiceProvider);
    if (androidSessionService.isSupported) {
      final actionSub = androidSessionService.actions.listen(
        _handleAndroidSessionServiceAction,
      );
      ref.onDispose(actionSub.cancel);
      listenSelf((_, next) {
        _syncAndroidSessionService(androidSessionService, view: next);
      });
      ref.listen<bool>(streamPublisherProvider.select((s) => s.isSharing), (
        previous,
        isSharing,
      ) {
        if (previous == true && !isSharing && _androidMediaProjectionActive) {
          return;
        }
        _syncAndroidSessionService(
          androidSessionService,
          isSharingScreen: isSharing,
        );
      });
      ref.listen<AppLocalizations>(appLocalizationsProvider, (_, l10n) {
        _syncAndroidSessionService(androidSessionService, l10n: l10n);
      });
      ref.onDispose(() {
        _stopAndroidSessionServiceIfNeeded(androidSessionService);
      });
    }

    // 初始档案在 spawn 时就广播过一次，广播通道不补发给订阅者；订阅后主动拉一遍，
    // 否则打开应用时已保存的服务器列表要等下一次增删才会出现。
    unawaited(_loadServers(session));
    unawaited(_loadServerIcons(session));
    return const SessionView();
  }

  void _syncAndroidSessionService(
    AndroidSessionServiceGateway service, {
    SessionView? view,
    bool? isSharingScreen,
    AppLocalizations? l10n,
  }) {
    unawaited(
      _syncAndroidSessionServiceAsync(
        service,
        view: view,
        isSharingScreen: isSharingScreen,
        l10n: l10n,
      ),
    );
  }

  Future<bool> _syncAndroidSessionServiceAsync(
    AndroidSessionServiceGateway service, {
    SessionView? view,
    bool? isSharingScreen,
    AppLocalizations? l10n,
  }) {
    if (!ref.mounted) return Future<bool>.value(false);
    final currentView = view ?? state;
    final shouldBeActive =
        currentView.connected ||
        (currentView.reconnecting && _androidSessionServiceActive);
    if (!shouldBeActive) {
      _stopAndroidSessionServiceIfNeeded(service);
      return Future<bool>.value(false);
    }

    final sharing =
        isSharingScreen ?? ref.read(streamPublisherProvider).isSharing;
    final AppLocalizations localizations =
        l10n ?? ref.read<AppLocalizations>(appLocalizationsProvider);
    final desired = buildAndroidSessionNotificationState(
      view: currentView,
      l10n: localizations,
      isSharingScreen: sharing,
      includeMediaProjection: _androidMediaProjectionActive,
    );
    if (desired == _lastAndroidNotificationState) {
      return _inFlightAndroidSync ??
          Future<bool>.value(_androidSessionServiceStarted);
    }
    _lastAndroidNotificationState = desired;
    _androidSessionServiceActive = true;
    final generation = ++_androidSessionServiceOpGen;
    final syncFuture = _applyAndroidSessionServiceSync(
      service,
      desired,
      generation,
    );
    _inFlightAndroidSync = syncFuture;
    syncFuture.whenComplete(() {
      if (identical(_inFlightAndroidSync, syncFuture)) {
        _inFlightAndroidSync = null;
      }
    });
    return syncFuture;
  }

  Future<bool> _applyAndroidSessionServiceSync(
    AndroidSessionServiceGateway service,
    AndroidSessionNotificationState desired,
    int generation,
  ) async {
    final ok = await service.syncSession(desired);
    if (!ref.mounted) {
      return false;
    }
    if (generation == _androidSessionServiceOpGen) {
      if (ok) {
        _androidSessionServiceStarted = true;
      } else {
        _lastAndroidNotificationState = null;
        if (!_androidSessionServiceStarted) {
          _androidSessionServiceActive = false;
        }
      }
    } else if (ok) {
      _androidSessionServiceStarted = true;
    }
    return ok;
  }

  void _stopAndroidSessionServiceIfNeeded(
    AndroidSessionServiceGateway service,
  ) {
    final hadState =
        _androidSessionServiceActive ||
        _androidMediaProjectionActive ||
        _lastAndroidNotificationState != null;
    _androidMediaProjectionActive = false;
    _inFlightAndroidSync = null;
    if (!hadState) {
      return;
    }
    _androidSessionServiceActive = false;
    _androidSessionServiceStarted = false;
    _lastAndroidNotificationState = null;
    _androidSessionServiceOpGen++;
    unawaited(service.stopSession());
  }

  /// 同步调整 Android 会话前台服务的 `mediaProjection` 类型位，并等待原生 `startForeground` 完成。
  Future<bool> setAndroidMediaProjectionActive(bool active) async {
    if (!ref.mounted) return false;
    final service = ref.read(androidSessionServiceProvider);
    if (!service.isSupported) return true;

    if (active) {
      if (!state.connected) return false;
      _androidMediaProjectionActive = true;
      final ok = await _syncAndroidSessionServiceAsync(service);
      if (!ref.mounted || !_androidMediaProjectionActive || !state.connected) {
        return false;
      }
      if (!ok) {
        _androidMediaProjectionActive = false;
        _lastAndroidNotificationState = null;
        return false;
      }
      return true;
    }

    if (!_androidMediaProjectionActive &&
        _lastAndroidNotificationState?.includeMediaProjection != true) {
      return true;
    }
    _androidMediaProjectionActive = false;
    if (!(state.connected ||
        (state.reconnecting && _androidSessionServiceActive))) {
      _stopAndroidSessionServiceIfNeeded(service);
      return true;
    }
    return _syncAndroidSessionServiceAsync(service, isSharingScreen: false);
  }

  void _handleAndroidSessionServiceAction(AndroidSessionServiceAction action) {
    if (!ref.mounted) return;
    switch (action) {
      case AndroidSessionServiceAction.toggleMute:
        if (state.connected) {
          unawaited(setMuted(!state.muted));
        }
      case AndroidSessionServiceAction.stopScreenShare:
        unawaited(stopScreenShare());
      case AndroidSessionServiceAction.disconnect:
        unawaited(disconnect());
    }
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

  Future<void> _loadServerIcons(CoreSession session) async {
    final revision = _serverIconsRevision;
    try {
      final icons = await session.listServerIcons();
      if (ref.mounted && revision == _serverIconsRevision) {
        state = state.copyWith(
          serverIconBytes: Map.unmodifiable({
            for (final icon in icons) icon.serverId: icon.bytes,
          }),
        );
      }
    } on CoreError catch (error) {
      if (ref.mounted && revision == _serverIconsRevision) {
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
      final permission = ref.read(microphonePermissionProvider);
      if (permission.enforcesRuntimePermission) {
        final status = await permission.request();
        if (!ref.mounted || _connectingServerId != id) return;
        final granted = status == MicrophonePermissionStatus.granted;
        await session.setMicrophonePermission(granted: granted);
        if (!granted) {
          await session.setMuted(muted: true);
          if (ref.mounted) {
            _notify(
              ref.read(appLocalizationsProvider).voiceMicPermissionDenied,
              tone: NoticeTone.info,
            );
          }
        }
      }
      if (!ref.mounted || _connectingServerId != id) return;
      final sessionService = ref.read(androidSessionServiceProvider);
      if (sessionService.isSupported && !_notificationPermissionRequested) {
        _notificationPermissionRequested = true;
        await sessionService.requestNotificationPermission();
        if (!ref.mounted || _connectingServerId != id) return;
      }
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
    if (message.fromSelf) {
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
    final l10n = ref.read(appLocalizationsProvider);
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
    final peer = state.findKickablePeer(recipient, target);
    final l10n = ref.read(appLocalizationsProvider);
    if (peer == null) {
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
      final session = ref.read(coreSessionProvider);
      final permission = ref.read(microphonePermissionProvider);
      if (!muted && permission.enforcesRuntimePermission) {
        final status = await permission.request();
        if (!ref.mounted) return;
        switch (status) {
          case MicrophonePermissionStatus.granted:
            await session.setMicrophonePermission(granted: true);
          case MicrophonePermissionStatus.denied:
            _notify(
              ref.read(appLocalizationsProvider).voiceMicPermissionDenied,
              tone: NoticeTone.info,
            );
            return;
          case MicrophonePermissionStatus.permanentlyDenied:
            _notify(
              ref.read(appLocalizationsProvider).voiceMicPermissionSettings,
              tone: NoticeTone.info,
            );
            await permission.openSettings();
            return;
        }
      }
      await session.setMuted(muted: muted);
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
    if (!ref.mounted || (active && (!state.connected || !state.pttMode))) {
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

  /// 开启屏幕或窗口共享。
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
            onAndroidMediaProjectionChanged: setAndroidMediaProjectionActive,
          );
    } on CoreError catch (error) {
      if (ref.mounted) {
        _notifyCoreError(error);
      }
      return false;
    } on Object {
      if (ref.mounted) {
        _notify(ref.read(appLocalizationsProvider).streamPublishFailed);
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
        _notify(ref.read(appLocalizationsProvider).chatDestinationChanged);
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
    final l10n = ref.read(appLocalizationsProvider);
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

  /// 上传当前服务器上的自己的头像；错误由 `_run` 统一转成 NoticeCenter 文案。
  Future<bool> uploadAvatar(Uint8List bytes) async {
    final saved = await _run(
      () => ref.read(coreSessionProvider).uploadAvatar(bytes: bytes),
    );
    if (saved && ref.mounted) {
      await ref.read(identityAvatarPreviewProvider.notifier).refresh();
    }
    return saved;
  }

  /// 删除当前服务器上的自己的头像。
  Future<bool> deleteAvatar() async {
    final deleted = await _run(
      () => ref.read(coreSessionProvider).deleteAvatar(),
    );
    if (deleted && ref.mounted) {
      await ref.read(identityAvatarPreviewProvider.notifier).refresh();
    }
    return deleted;
  }

  Future<bool> _ensureImageHostConfigured(AppLocalizations l10n) async {
    try {
      final config = await ref.read(imageHostProvider.future);
      if (!ref.mounted) return false;
      if (config == null) {
        _notify(l10n.imageHostRequired);
        return false;
      }
      return true;
    } on Exception {
      if (ref.mounted) _notify(l10n.imageHostStorageFailed);
      return false;
    }
  }

  Future<PickedChatImage?> pickChatImage() async {
    final l10n = ref.read(appLocalizationsProvider);
    if (!await _ensureImageHostConfigured(l10n)) {
      return null;
    }
    try {
      return await ref.read(imageInputProvider).pick();
    } on ImageInputException catch (error) {
      if (ref.mounted) {
        _notify(switch (error.failure) {
          ImageInputFailure.tooLarge => l10n.chatImageTooLargeWithLimit(
            formatByteSize(maxChatImageBytes()),
          ),
        });
      }
    } on Exception {
      if (ref.mounted) _notify(l10n.chatImageInputFailed);
    }
    return null;
  }

  /// 聊天输入框快捷键粘贴：剪贴板无图时返回 `handled: false` 让文本粘贴继续；
  /// 有图时先校验图床配置和大小限制，再决定附带预览或报错拦截。
  Future<ChatImagePasteResult> pasteChatImage() async {
    final l10n = ref.read(appLocalizationsProvider);
    Uint8List? bytes;
    try {
      bytes = await ref.read(imageInputProvider).readClipboardImageBytes();
    } on Exception {
      return (handled: false, image: null);
    }
    if (!ref.mounted || bytes == null || bytes.isEmpty) {
      return (handled: false, image: null);
    }
    if (!await _ensureImageHostConfigured(l10n)) {
      return (handled: true, image: null);
    }
    if (bytes.length > maxChatImageBytes()) {
      if (ref.mounted) {
        _notify(
          l10n.chatImageTooLargeWithLimit(formatByteSize(maxChatImageBytes())),
        );
      }
      return (handled: true, image: null);
    }
    return (
      handled: true,
      image: PickedChatImage(bytes: bytes, name: 'clipboard.png'),
    );
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
      _notify(ref.read(appLocalizationsProvider).kickTargetUnavailable);
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
    final l10n = ref.read(appLocalizationsProvider);
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
      _notify(ref.read(appLocalizationsProvider).fileDownloadFailed);
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
      final l10n = ref.read(appLocalizationsProvider);
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
      _notify(describeCoreError(error, ref.read(appLocalizationsProvider)));
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
            describeCoreError(error, ref.read(appLocalizationsProvider)),
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
            chatScope: ChatScope.server,
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
            chatScope: ChatScope.server,
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
            chatScope: next is CoreSessionState_Connected && !current.connected
                ? ChatScope.server
                : current.chatScope,
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
      case CoreEvent_ServerIconUpdated(:final serverId, :final bytes):
        _serverIconsRevision++;
        final next = {...current.serverIconBytes};
        if (bytes != null) {
          next[serverId] = bytes;
        } else {
          next.remove(serverId);
        }
        state = current.copyWith(serverIconBytes: Map.unmodifiable(next));
      case CoreEvent_AvatarUpdated(:final uid):
        if (current.connected && uid.isNotEmpty) {
          _avatarUpdates.add(uid);
        }
      case CoreEvent_Snapshot(:final channels, :final clients):
        state = current.copyWith(
          channels: channels,
          clients: clients,
          accessRevision: current.accessRevision + 1,
        );
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
        :final fromSelf,
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
          fromSelf: fromSelf,
        );
        final unread = _unreadFor(current, received);
        final appended = [...current.messages, received];
        final limit = historyLimit();
        state = current.copyWith(
          messages: appended.length > limit
              ? appended.sublist(appended.length - limit)
              : appended,
          unreadScopes: unread.scopes,
          unreadPeers: unread.peers,
        );
      case CoreEvent_Poked(:final from, :final message):
        _notify(
          ref.read(appLocalizationsProvider).pokeReceived(from, message),
          tone: NoticeTone.info,
        );
      case CoreEvent_ClientJoined(:final client):
        state = current.copyWith(
          clients: [
            ...current.clients.where((existing) => existing.id != client.id),
            client,
          ],
        );
      case CoreEvent_ClientLeft(:final id):
        state = current.copyWith(
          clients: current.clients.where((client) => client.id != id).toList(),
        );
      case CoreEvent_ClientMoved(:final client):
        if (client.id == current.selfClientId &&
            client.channelId != current.selfChannelId) {
          unawaited(ref.read(streamViewerProvider.notifier).closeSession());
          unawaited(
            ref
                .read(streamPublisherProvider.notifier)
                .stopScreenShare(notifyServer: false),
          );
        }
        state = current.copyWith(
          clients: [
            for (final existing in current.clients)
              if (existing.id == client.id) client else existing,
          ],
        );
      case CoreEvent_ClientUpdated(
        :final id,
        :final inputMuted,
        :final outputMuted,
        :final away,
        :final awayMessage,
      ):
        // 事件只带变化字段，null 表示本次没提，不清除已知值；自身标志由 Rust 在事件里算好。
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
                  isStreaming: client.isStreaming,
                  clientType: client.clientType,
                  appName: client.appName,
                  appVersion: client.appVersion,
                  capabilities: client.capabilities,
                  botCommands: client.botCommands,
                  botCommandsLoaded: client.botCommandsLoaded,
                  botCommandPrefix: client.botCommandPrefix,
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
          _notify(
            describeBackendNotice(message, ref.read(appLocalizationsProvider)),
          );
        }
      case CoreEvent_AudioDevicesReset(:final input, :final output):
        ref.read(audioDeviceResetBusProvider).add((
          input: input,
          output: output,
        ));
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
          ref.read(appLocalizationsProvider).identityUpgrading(to),
          tone: NoticeTone.info,
        );
      case CoreEvent_IdentityUpgraded(:final level):
        state = current.copyWith(identityUpgradeTarget: null);
        _notify(
          ref.read(appLocalizationsProvider).identityUpgraded(level),
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
        final l10n = ref.read(appLocalizationsProvider);
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
        _notifyFailure(
          describeBackendNotice(message, ref.read(appLocalizationsProvider)),
        );
      case CoreEvent_Failed(:final message):
        final text = describeBackendNotice(
          message,
          ref.read(appLocalizationsProvider),
        );
        if (current.connected) {
          _notify(text);
        } else {
          state = current.copyWith(identityUpgradeTarget: null);
          _notifyFailure(text);
        }
    }
  }
}
