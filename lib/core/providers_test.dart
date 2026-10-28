// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'models.dart';
import 'providers.dart';
import 'notices.dart';

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

void main() {
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
}
