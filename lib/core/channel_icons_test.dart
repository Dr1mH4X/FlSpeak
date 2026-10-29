// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'channel_icons.dart';
import 'models.dart';
import 'providers.dart';

class _Core extends Fake implements CoreSession {
  final requests = <Completer<Uint8List>>[];

  @override
  Future<Uint8List> fetchIcon({required int iconId}) {
    final response = Completer<Uint8List>();
    requests.add(response);
    return response.future;
  }
}

class _Controller extends SessionController {
  @override
  SessionView build() => const SessionView(
    activeServerId: 'a',
    connectionEpoch: 1,
    state: CoreSessionState.connected(clientId: 1, channelId: 1),
  );

  void switchServer() =>
      state = state.copyWith(activeServerId: 'b', connectionEpoch: 2);
}

void main() {
  test('same ID is shared within a connection; old transfer cannot replace new server data', () async {
    final core = _Core();
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(core),
        sessionViewProvider.overrideWith(_Controller.new),
      ],
    );
    addTearDown(container.dispose);
    final first = container.listen(
      channelIconProvider(42),
      (previous, next) {},
    );
    final second = container.listen(
      channelIconProvider(42),
      (previous, next) {},
    );
    addTearDown(first.close);
    addTearDown(second.close);
    await Future<void>.delayed(Duration.zero);
    expect(core.requests, hasLength(1));
    (container.read(sessionViewProvider.notifier) as _Controller)
        .switchServer();
    await Future<void>.delayed(Duration.zero);
    expect(core.requests, hasLength(2));
    core.requests[0].complete(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(channelIconProvider(42)).hasValue, isFalse);
    core.requests[1].complete(Uint8List.fromList([2]));
    expect(await container.read(channelIconProvider(42).future), [2]);
  });
}
