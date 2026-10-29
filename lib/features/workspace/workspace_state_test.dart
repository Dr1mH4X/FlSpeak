// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import 'workspace_state.dart';

class _Session extends SessionController {
  final joined = Completer<bool>();
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
    activeServerId: 'a',
    connectionEpoch: 1,
  );
  void changeServer() =>
      state = state.copyWith(activeServerId: 'b', connectionEpoch: 2);
  @override
  Future<bool> joinChannel(int channelId, {String? password}) => joined.future;
}

void main() {
  test(
    'an obsolete join cannot open a password prompt on another connection',
    () async {
      final session = _Session();
      final container = ProviderContainer(
        overrides: [sessionViewProvider.overrideWith(() => session)],
      );
      addTearDown(container.dispose);
      final selected = container.read(selectedChannelProvider.notifier);
      var prompts = 0;
      final joining = selected.join(
        6,
        serverId: 'a',
        fallback: (serverId: 'a', channelId: 5),
        requestPassword: () async {
          prompts++;
          return false;
        },
      );
      session.changeServer();
      selected.select(6, serverId: 'b');
      session.joined.completeError(
        const CoreError.channelPasswordRequired(message: 'old connection'),
      );
      await joining;
      expect(prompts, 0);
      expect(container.read(selectedChannelProvider), (
        serverId: 'b',
        channelId: 6,
      ));
    },
  );

  for (final password in [false, true]) {
    test(
      'a join finishing after disposal does not prompt or roll back, password=$password',
      () async {
        final session = _Session();
        final container = ProviderContainer(
          overrides: [sessionViewProvider.overrideWith(() => session)],
        );
        var prompts = 0;
        final joining = container
            .read(selectedChannelProvider.notifier)
            .join(
              6,
              serverId: 'a',
              fallback: (serverId: 'a', channelId: 5),
              requestPassword: () async {
                prompts++;
                return false;
              },
            );
        container.dispose();
        if (password) {
          session.joined.completeError(
            const CoreError.channelPasswordRequired(message: 'late failure'),
          );
        } else {
          session.joined.complete(false);
        }
        await joining;
        expect(prompts, 0);
      },
    );
  }
}
