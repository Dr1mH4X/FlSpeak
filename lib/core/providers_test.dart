// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'models.dart';
import 'providers.dart';
import 'notices.dart';
import 'preferences.dart';
import 'voice_levels.dart';

class _Core extends Fake implements CoreSession {
  _Core(this.eventsController);

  final StreamController<CoreEvent> eventsController;
  final sent = <({int mode, int target, String text})>[];
  bool fail = false;
  final kicks =
      <
        ({
          String uid,
          int clientId,
          int channelId,
          KickTarget target,
          String reason,
          int epoch,
        })
      >[];
  @override
  Future<void> kick({
    required String uid,
    required int clientId,
    required int channelId,
    required KickTarget target,
    required String reason,
    required int connectionEpoch,
  }) async {
    if (fail) throw const CoreError.connection(message: 'kick rejected');
    kicks.add((
      uid: uid,
      clientId: clientId,
      channelId: channelId,
      target: target,
      reason: reason,
      epoch: connectionEpoch,
    ));
  }

  final pokes = <({int id, String message})>[];
  final groupUpdates =
      <
        ({
          String uid,
          int clientId,
          int groupId,
          int channelId,
          GroupKind kind,
          bool enabled,
        })
      >[];
  @override
  Future<void> setMemberGroup({
    required String uid,
    required int clientId,
    required int groupId,
    required int channelId,
    required GroupKind kind,
    required bool enabled,
  }) async {
    if (fail) throw const CoreError.connection(message: 'group rejected');
    groupUpdates.add((
      uid: uid,
      clientId: clientId,
      groupId: groupId,
      channelId: channelId,
      kind: kind,
      enabled: enabled,
    ));
  }

  @override
  Future<int> downloadFile({
    required String remotePath,
    required String localPath,
    required int channelId,
    String? password,
  }) async {
    eventsController.add(const CoreEvent.transferFinished(id: 55));
    return 55;
  }

  @override
  Future<void> poke({required int clientId, required String message}) async {
    if (fail) throw const CoreError.connection(message: 'poke rejected');
    pokes.add((id: clientId, message: message));
  }

  int accessCalls = 0;
  int memberGroupsCalls = 0;

  @override
  Future<AccessView> access() async {
    accessCalls++;
    return const AccessView(kickChannelPower: 10, kickServerPower: 10);
  }

  @override
  Future<List<MemberGroupView>> memberGroups({
    required String uid,
    int? clientId,
  }) async {
    memberGroupsCalls++;
    return const [];
  }

  @override
  Stream<CoreEvent> events() => eventsController.stream;
  @override
  Future<List<ServerProfileView>> listServers() async => [];
  @override
  Future<void> sendText({
    required int targetMode,
    required int targetId,
    required String message,
  }) async {
    if (fail) throw const CoreError.connection(message: 'rejected');
    sent.add((mode: targetMode, target: targetId, text: message));
  }
}

class _ConcurrentCore extends _Core {
  _ConcurrentCore(super.eventsController);
  final disconnected = Completer<void>();
  final configured = Completer<void>();
  final muted = Completer<void>();
  @override
  Future<void> disconnect() => disconnected.future;
  @override
  Future<void> setAutoReconnect({required bool enabled}) => configured.future;
  @override
  Future<void> setMuted({required bool muted}) => this.muted.future;
}

class _SwitchCore extends _Core {
  _SwitchCore(super.eventsController) {
    disconnectReply.future.ignore();
  }
  final calls = <String>[];
  final disconnectReply = Completer<void>();
  final connectReply = Completer<void>();
  @override
  Future<void> disconnect() {
    calls.add('disconnect');
    return disconnectReply.future;
  }

  @override
  Future<void> connect({required String id, required String nickname}) {
    calls.add('connect:$id');
    if (calls.length == 1) {
      return Future.error(
        const CoreError.connection(message: 'already connected'),
      );
    }
    return connectReply.future;
  }
}

class _ConnectedSession extends SessionController {
  @override
  SessionView build() => super.build().copyWith(
    state: const CoreSessionState.connected(clientId: 1, channelId: 5),
    activeServerId: 'server-a',
    connectionEpoch: 1,
    channels: const [
      ChannelView(id: 5, parentId: 0, name: 'A', description: ''),
    ],
    clients: const [ClientView(id: 1, nickname: 'Me', uid: 'me', channelId: 5)],
  );
}

class _LateServersCore extends _Core {
  _LateServersCore(super.eventsController);
  final initialServers = Completer<List<ServerProfileView>>();
  @override
  Future<List<ServerProfileView>> listServers() => initialServers.future;
}

void main() {
  test(
    'events queued before the reset cannot adopt the pending server profile',
    () async {
      final events = StreamController<CoreEvent>.broadcast(sync: true);
      final core = _SwitchCore(events);
      final container = ProviderContainer(
        overrides: [coreSessionProvider.overrideWithValue(core)],
      );
      addTearDown(() async {
        container.dispose();
        await events.close();
      });
      final attempt = container
          .read(sessionViewProvider.notifier)
          .connect(id: 'server-b', nickname: 'Me');
      events.add(const CoreEvent.state(state: CoreSessionState.connecting()));
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.reconnecting(attempt: 1, delayMs: 1000),
        ),
      );
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 1, channelId: 5),
        ),
      );
      expect(container.read(sessionViewProvider).activeServerId, isNull);
      core.disconnectReply.complete();
      events.add(const CoreEvent.state(state: CoreSessionState.disconnected()));
      await Future<void>.value();
      events.add(const CoreEvent.state(state: CoreSessionState.connecting()));
      core.connectReply.complete();
      expect(await attempt, isTrue);
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 2, channelId: 9),
        ),
      );
      expect(container.read(sessionViewProvider).activeServerId, 'server-b');
    },
  );

  test(
    'startup retries retain their requested server after the first API failure',
    () async {
      final events = StreamController<CoreEvent>.broadcast(sync: true);
      final core = _SwitchCore(events);
      final container = ProviderContainer(
        overrides: [coreSessionProvider.overrideWithValue(core)],
      );
      addTearDown(() async {
        container.dispose();
        await events.close();
      });
      final attempt = container
          .read(sessionViewProvider.notifier)
          .connect(id: 'server-b', nickname: 'Me');
      expect(core.calls, ['disconnect']);
      core.disconnectReply.complete();
      events.add(const CoreEvent.state(state: CoreSessionState.disconnected()));
      await Future<void>.value();
      events.add(const CoreEvent.state(state: CoreSessionState.connecting()));
      events.add(const CoreEvent.state(state: CoreSessionState.disconnected()));
      core.connectReply.completeError(
        const CoreError.connection(message: 'first attempt timed out'),
      );
      expect(await attempt, isFalse);
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.reconnecting(attempt: 1, delayMs: 1000),
        ),
      );
      expect(container.read(sessionViewProvider).activeServerId, 'server-b');
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 1, channelId: 5),
        ),
      );
      expect(container.read(sessionViewProvider).activeServerId, 'server-b');
    },
  );

  test('identity notices follow the selected English locale', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(_Core(events)),
        preferencesStoreProvider.overrideWithValue(
          PreferencesStore.inMemory(
            preferences: const SessionPreferences(
              nickname: 'Test',
              locale: 'en',
            ),
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    container.read(sessionViewProvider);
    events.add(const CoreEvent.identityUpgrade(from: 8, to: 13));
    expect(
      container.read(noticeCenterProvider).first.message,
      'Upgrading identity level to 13…',
    );
    events.add(const CoreEvent.identityUpgraded(level: 13));
    expect(
      container.read(noticeCenterProvider).first.message,
      'Identity upgraded to level 13. Reconnecting…',
    );
  });

  test(
    'choosing the live server preserves its snapshot and does not reconnect',
    () async {
      final events = StreamController<CoreEvent>.broadcast(sync: true);
      final core = _SwitchCore(events);
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          sessionViewProvider.overrideWith(_ConnectedSession.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await events.close();
      });
      expect(
        await container
            .read(sessionViewProvider.notifier)
            .connect(id: 'server-a', nickname: 'Me'),
        isTrue,
      );
      expect(core.calls, isEmpty);
      expect(container.read(sessionViewProvider).channels, hasLength(1));
    },
  );

  test(
    'a failed replacement connection does not retain a live server label',
    () async {
      final events = StreamController<CoreEvent>.broadcast(sync: true);
      final core = _SwitchCore(events);
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          sessionViewProvider.overrideWith(_ConnectedSession.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await events.close();
      });
      final switching = container
          .read(sessionViewProvider.notifier)
          .connect(id: 'server-b', nickname: 'Me');
      core.disconnectReply.complete();
      events.add(const CoreEvent.state(state: CoreSessionState.disconnected()));
      await Future<void>.value();
      core.connectReply.completeError(
        const CoreError.connection(message: 'replacement rejected'),
      );
      expect(await switching, isFalse);
      expect(container.read(sessionViewProvider).connected, isFalse);
      expect(container.read(sessionViewProvider).activeServerId, isNull);
    },
  );

  test('server switching disconnects first and uses ordered state events for the active profile', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final core = _SwitchCore(events);
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(core),
        sessionViewProvider.overrideWith(_ConnectedSession.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    final controller = container.read(sessionViewProvider.notifier);
    final switching = controller.connect(id: 'server-b', nickname: 'Me');
    expect(core.calls, ['disconnect']);
    expect(container.read(sessionViewProvider).activeServerId, 'server-a');
    expect(container.read(sessionViewProvider).channels, hasLength(1));
    expect(await controller.connect(id: 'server-c', nickname: 'Me'), isFalse);
    core.disconnectReply.complete();
    await Future<void>.value();
    expect(core.calls, ['disconnect', 'connect:server-b']);
    events.add(
      const CoreEvent.state(
        state: CoreSessionState.reconnecting(attempt: 1, delayMs: 1000),
      ),
    );
    events.add(
      const CoreEvent.state(
        state: CoreSessionState.connected(clientId: 1, channelId: 6),
      ),
    );
    expect(container.read(sessionViewProvider).activeServerId, 'server-a');
    events.add(const CoreEvent.state(state: CoreSessionState.disconnected()));
    expect(container.read(sessionViewProvider).activeServerId, isNull);
    expect(container.read(sessionViewProvider).busy, isTrue);
    events.add(const CoreEvent.state(state: CoreSessionState.connecting()));
    expect(container.read(sessionViewProvider).activeServerId, 'server-b');
    core.connectReply.complete();
    expect(await switching, isTrue);
    events.add(
      const CoreEvent.state(
        state: CoreSessionState.connected(clientId: 2, channelId: 9),
      ),
    );
    expect(container.read(sessionViewProvider).activeServerId, 'server-b');
    expect(container.read(sessionViewProvider).connectionEpoch, 3);
  });

  test('failed disconnect aborts a server switch without relabelling the live connection', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final core = _SwitchCore(events);
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(core),
        sessionViewProvider.overrideWith(_ConnectedSession.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    final switching = container
        .read(sessionViewProvider.notifier)
        .connect(id: 'server-b', nickname: 'Me');
    core.disconnectReply.completeError(
      const CoreError.connection(message: 'disconnect failed'),
    );
    expect(await switching, isFalse);
    expect(core.calls, ['disconnect']);
    expect(container.read(sessionViewProvider).activeServerId, 'server-a');
  });

  test('an operation failure preserves a connected snapshot and does not report a connection failure', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(_Core(events)),
        sessionViewProvider.overrideWith(_ConnectedSession.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    container.read(sessionViewProvider);
    events.add(const CoreEvent.failed(message: 'history could not be saved'));
    final view = container.read(sessionViewProvider);
    expect(view.connected, isTrue);
    expect(view.channels, hasLength(1));
    expect(view.clients, hasLength(1));
    expect(view.failureSeq, 0);
    expect(
      container.read(noticeCenterProvider).single.message,
      'history could not be saved',
    );
  });

  test(
    'an old initial server list cannot overwrite a newer server event',
    () async {
      final events = StreamController<CoreEvent>.broadcast(sync: true);
      final core = _LateServersCore(events);
      final container = ProviderContainer(
        overrides: [coreSessionProvider.overrideWithValue(core)],
      );
      addTearDown(() async {
        container.dispose();
        await events.close();
      });
      container.read(sessionViewProvider);
      events.add(
        const CoreEvent.servers(
          profiles: [
            ServerProfileView(
              id: 'new',
              label: 'New',
              host: 'new.example.com',
              port: 9987,
            ),
          ],
        ),
      );
      core.initialServers.complete([]);
      await Future<void>.value();
      expect(container.read(sessionViewProvider).servers.single.id, 'new');
    },
  );

  test('reconnecting clears speaking indicators and levels without dropping the server target', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(_Core(events)),
        sessionViewProvider.overrideWith(_ConnectedSession.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    final controller = container.read(sessionViewProvider.notifier);
    final levels = <VoiceLevels>[];
    final subscription = controller.levels.listen(levels.add);
    addTearDown(subscription.cancel);
    events.add(const CoreEvent.levels(mic: 1, received: 1));
    events.add(const CoreEvent.selfSpeaking(speaking: true));
    events.add(CoreEvent.speaking(clientIds: Int32List.fromList([1])));
    events.add(
      const CoreEvent.state(
        state: CoreSessionState.reconnecting(attempt: 1, delayMs: 1000),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final view = container.read(sessionViewProvider);
    expect(view.activeServerId, 'server-a');
    expect(view.selfSpeaking, isFalse);
    expect(view.speaking, isEmpty);
    expect(levels.last, VoiceLevels.silent);
  });

  test('late voice failures do not read a disposed provider', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final core = _ConcurrentCore(events);
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(core)],
    );
    final command = container.read(sessionViewProvider.notifier).setMuted(true);
    container.dispose();
    core.muted.completeError(
      const CoreError.connection(message: 'late failure'),
    );
    await command;
    await events.close();
  });

  test('busy stays set until all concurrent commands have finished', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final core = _ConcurrentCore(events);
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(core)],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    final controller = container.read(sessionViewProvider.notifier);
    final disconnect = controller.disconnect();
    final configure = controller.setAutoReconnect(false);
    core.configured.complete();
    await configure;
    expect(container.read(sessionViewProvider).busy, isTrue);
    core.disconnected.complete();
    await disconnect;
    expect(container.read(sessionViewProvider).busy, isFalse);
  });

  test('电平不改变会话快照，断开后丢弃在途指标', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(_Core(events))],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    final controller = container.read(sessionViewProvider.notifier);
    final received = <VoiceLevels>[];
    final subscription = controller.levels.listen(received.add);
    addTearDown(subscription.cancel);
    events.add(
      const CoreEvent.state(
        state: CoreSessionState.connected(clientId: 1, channelId: 5),
      ),
    );
    final before = container.read(sessionViewProvider);
    events.add(const CoreEvent.levels(mic: 0.9, received: 0.6));
    expect(identical(container.read(sessionViewProvider), before), isTrue);
    await Future<void>.value();
    expect(received.last.mic, 0.9);
    events.add(const CoreEvent.state(state: CoreSessionState.disconnected()));
    await Future<void>.value();
    expect(received.last, VoiceLevels.silent);
    final count = received.length;
    events.add(const CoreEvent.levels(mic: 1, received: 1));
    await Future<void>.value();
    expect(received.length, count);
  });

  test('kick preserves UID and native epoch, rejects moved/offline/self targets and retains members on refusal', () async {
    const peer = ClientView(id: 2, nickname: 'Peer', uid: 'peer', channelId: 5);
    const myself = ClientView(id: 1, nickname: 'Me', uid: 'self', channelId: 5);
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final core = _Core(events);
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(core)],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    final controller = container.read(sessionViewProvider.notifier);
    events.add(
      const CoreEvent.state(
        state: CoreSessionState.connected(clientId: 1, channelId: 5),
      ),
    );
    events.add(
      const CoreEvent.snapshot(
        channels: [],
        clients: [
          ClientView(id: 1, nickname: 'Me', uid: 'self', channelId: 5),
          ClientView(id: 2, nickname: 'Peer', uid: 'peer', channelId: 5),
        ],
      ),
    );
    expect(
      await controller.kickClient(myself, KickTarget.server, '', 42),
      isFalse,
    );
    expect(
      await controller.kickClient(
        peer,
        KickTarget.channel,
        '  reason | test  ',
        42,
      ),
      isTrue,
    );
    expect(core.kicks.single, (
      uid: 'peer',
      clientId: 2,
      channelId: 5,
      target: KickTarget.channel,
      reason: 'reason | test',
      epoch: 42,
    ));
    events.add(const CoreEvent.clientMoved(id: 2, channelId: 9));
    expect(
      await controller.kickClient(peer, KickTarget.channel, '', 42),
      isFalse,
    );
    core.fail = true;
    expect(
      await controller.kickClient(peer, KickTarget.server, '', 42),
      isFalse,
    );
    expect(
      container
          .read(sessionViewProvider)
          .clients
          .any((peer) => peer.uid == 'peer'),
      isTrue,
    );
    expect(
      container
          .read(noticeCenterProvider)
          .any((notice) => notice.message.contains('kick rejected')),
      isTrue,
    );
    core.fail = false;
    expect(
      await controller.kickClient(peer, KickTarget.server, '', 42),
      isTrue,
    );
    expect(core.kicks.last.target, KickTarget.server);
    events.add(const CoreEvent.clientLeft(id: 2));
    expect(
      await controller.kickClient(peer, KickTarget.server, '', 42),
      isFalse,
    );
    expect(core.kicks, hasLength(2));
  });

  test(
    'kick selects the exact connection when an identity has multiple clients',
    () async {
      const first = ClientView(
        id: 2,
        nickname: 'First',
        uid: 'shared',
        channelId: 5,
      );
      const selected = ClientView(
        id: 3,
        nickname: 'Selected',
        uid: 'shared',
        channelId: 9,
      );
      final events = StreamController<CoreEvent>.broadcast(sync: true);
      final core = _Core(events);
      final container = ProviderContainer(
        overrides: [coreSessionProvider.overrideWithValue(core)],
      );
      addTearDown(() async {
        container.dispose();
        await events.close();
      });
      final controller = container.read(sessionViewProvider.notifier);
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 1, channelId: 5),
        ),
      );
      events.add(
        const CoreEvent.snapshot(channels: [], clients: [first, selected]),
      );
      expect(
        await controller.kickClient(selected, KickTarget.server, '', 42),
        isTrue,
      );
      expect(core.kicks.single.clientId, 3);
      events.add(const CoreEvent.clientLeft(id: 3));
      events.add(
        const CoreEvent.clientJoined(
          id: 3,
          nickname: 'Other',
          uid: 'other',
          channelId: 9,
        ),
      );
      expect(
        await controller.kickClient(selected, KickTarget.server, '', 42),
        isFalse,
      );
      expect(core.kicks, hasLength(1));
    },
  );

  test('download completion arriving before the API reply is retained even without a start event', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(_Core(events))],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    final result = await container
        .read(sessionViewProvider.notifier)
        .downloadChannelFile(5, '/fixture', '/tmp/fixture')
        .timeout(const Duration(seconds: 1));
    expect(result, isTrue);
    expect(container.read(sessionViewProvider).transfers[55]!.finished, isTrue);
  });

  test('private recipient uses current UID mapping and cannot fall back to another client', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final core = _Core(events);
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(core)],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    final controller = container.read(sessionViewProvider.notifier);
    core.eventsController.add(
      const CoreEvent.state(
        state: CoreSessionState.connected(clientId: 1, channelId: 7),
      ),
    );
    core.eventsController.add(
      const CoreEvent.snapshot(
        channels: [],
        clients: [
          ClientView(id: 1, nickname: 'Self', uid: 'self', channelId: 7),
          ClientView(id: 2, nickname: 'Peer', uid: 'peer', channelId: 7),
        ],
      ),
    );
    controller.replyToMessage(
      ChatMessage(
        from: 'Peer',
        fromUid: 'peer',
        text: 'incoming',
        at: DateTime(2026),
        scope: ChatScope.direct,
        targetId: 1,
      ),
    );
    expect(container.read(sessionViewProvider).directRecipientUid, 'peer');
    expect(await controller.sendMessage('hello'), isTrue);
    expect(core.sent.single, (mode: 1, target: 2, text: 'hello'));
    expect(await controller.pokeClient('peer', 'poke body'), isTrue);
    expect(core.pokes.single, (id: 2, message: 'poke body'));
    events.add(const CoreEvent.poked(from: 'Peer', message: 'incoming poke'));
    expect(
      container
          .read(noticeCenterProvider)
          .any(
            (notice) =>
                notice.message.contains('incoming poke') &&
                notice.message.contains('Peer'),
          ),
      isTrue,
    );
    final oldSender = controller.prepareMessageSender();
    controller.selectChatScope(ChatScope.channel);
    expect(await oldSender('must not become a channel message'), isFalse);
    expect(core.sent, hasLength(1));
    controller.selectDirectRecipient('peer');
    core.eventsController.add(const CoreEvent.clientLeft(id: 2));
    core.eventsController.add(
      const CoreEvent.clientJoined(
        id: 2,
        nickname: 'Other',
        uid: 'other',
        channelId: 7,
      ),
    );
    expect(await controller.sendMessage('must not reach Other'), isFalse);
    expect(await controller.pokeClient('peer', 'must not poke Other'), isFalse);
    expect(core.pokes, hasLength(1));
    expect(core.sent, hasLength(1));
    core.eventsController.add(
      const CoreEvent.clientJoined(
        id: 3,
        nickname: 'Peer',
        uid: 'peer',
        channelId: 7,
      ),
    );
    expect(await controller.sendMessage('new client id'), isTrue);
    expect(core.sent.last.target, 3);
    core.fail = true;
    expect(await controller.pokeClient('peer', 'rejected'), isFalse);
    expect(core.pokes, hasLength(1));
    expect(await controller.sendMessage('rejected'), isFalse);
    core.eventsController.add(
      const CoreEvent.state(state: CoreSessionState.disconnected()),
    );
    final view = container.read(sessionViewProvider);
    expect(view.directRecipientUid, isNull);
    expect(view.chatScope, ChatScope.channel);
    expect(await controller.sendMessage('offline'), isFalse);
  });

  test('shared-identity clones target the exact client id for direct messages, pokes, and group updates', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final core = _Core(events);
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(core)],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });
    final controller = container.read(sessionViewProvider.notifier);
    events.add(
      const CoreEvent.state(
        state: CoreSessionState.connected(clientId: 1, channelId: 7),
      ),
    );
    events.add(
      const CoreEvent.snapshot(
        channels: [],
        clients: [
          ClientView(id: 1, nickname: 'Self', uid: 'self', channelId: 7),
          ClientView(id: 2, nickname: 'CloneA', uid: 'shared', channelId: 7),
          ClientView(id: 3, nickname: 'CloneB', uid: 'shared', channelId: 7),
          ClientView(id: 4, nickname: 'SelfClone', uid: 'self', channelId: 7),
        ],
      ),
    );
    controller.replyToMessage(
      ChatMessage(
        from: 'CloneB',
        fromUid: 'shared',
        fromId: 3,
        text: 'from second clone',
        at: DateTime(2026),
        scope: ChatScope.direct,
        targetId: 1,
      ),
    );
    expect(container.read(sessionViewProvider).directRecipient?.id, 3);
    expect(await controller.sendMessage('reply to B'), isTrue);
    expect(core.sent.last, (mode: 1, target: 3, text: 'reply to B'));

    controller.replyToMessage(
      ChatMessage(
        from: 'SelfClone',
        fromUid: 'self',
        fromId: 4,
        text: 'from my other device',
        at: DateTime(2026),
        scope: ChatScope.direct,
        targetId: 1,
      ),
    );
    expect(container.read(sessionViewProvider).directRecipient?.id, 4);
    expect(await controller.sendMessage('reply to self clone'), isTrue);
    expect(core.sent.last, (mode: 1, target: 4, text: 'reply to self clone'));

    expect(
      await controller.pokeClient('shared', 'poke B', clientId: 3),
      isTrue,
    );
    expect(core.pokes.single, (id: 3, message: 'poke B'));

    const group = MemberGroupView(
      channelId: 7,
      id: 9,
      name: 'Voice',
      kind: GroupKind.channel,
      member: false,
      canAdd: true,
      canRemove: true,
    );
    expect(
      await controller.setMemberGroup('shared', group, true, clientId: 3),
      isTrue,
    );
    expect(core.groupUpdates.single.clientId, 3);
  });

  test('sessionAccessProvider and memberGroupsProvider update via accessRevision without circular dependency', () async {
    final events = StreamController<CoreEvent>.broadcast(sync: true);
    final core = _Core(events);
    final container = ProviderContainer(
      overrides: [coreSessionProvider.overrideWithValue(core)],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });

    final controller = container.read(sessionViewProvider.notifier);
    final accessSub = container.listen(sessionAccessProvider, (_, _) {});
    final groupsSub = container.listen(
      memberGroupsProvider((clientId: 2, uid: 'peer')),
      (_, _) {},
    );
    addTearDown(() {
      accessSub.close();
      groupsSub.close();
    });

    expect(container.read(sessionViewProvider).accessRevision, 0);

    events.add(
      const CoreEvent.state(
        state: CoreSessionState.connected(clientId: 1, channelId: 5),
      ),
    );
    await pumpEventQueue();

    events.add(
      const CoreEvent.snapshot(
        channels: [],
        clients: [
          ClientView(id: 1, nickname: 'Me', uid: 'self', channelId: 5),
          ClientView(id: 2, nickname: 'Peer', uid: 'peer', channelId: 5),
        ],
      ),
    );
    await pumpEventQueue();
    expect(container.read(sessionViewProvider).accessRevision, 1);
    expect(core.accessCalls, greaterThanOrEqualTo(1));

    final previousAccessCalls = core.accessCalls;
    events.add(const CoreEvent.accessChanged());
    await pumpEventQueue();
    expect(container.read(sessionViewProvider).accessRevision, 2);
    expect(core.accessCalls, greaterThan(previousAccessCalls));

    const group = MemberGroupView(
      channelId: 5,
      id: 9,
      name: 'Voice',
      kind: GroupKind.channel,
      member: false,
      canAdd: true,
      canRemove: true,
    );
    expect(
      await controller.setMemberGroup('peer', group, true, clientId: 2),
      isTrue,
    );
    expect(container.read(sessionViewProvider).accessRevision, 3);

    events.add(const CoreEvent.state(state: CoreSessionState.disconnected()));
    await pumpEventQueue();
    expect(container.read(sessionViewProvider).accessRevision, 3);
  });
}
