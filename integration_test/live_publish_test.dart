// Live publisher smoke test: runs on the real macOS app bundle, so the real
// flutter_webrtc stack and the real TeamSpeak client talk to each other.
//
//   flutter test integration_test/live_publish_test.dart -d macos --timeout none
//
// It connects with the stored server profile, joins the channel that holds the
// client named on the command line (x414 by default), starts a screen share from
// the first screen source, and prints the offer/answer/ICE evidence while a
// human clicks "watch" in the official client.

import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/store_path.dart';
import 'package:flspeak/core/stream_publisher.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';

const _targetNickname = String.fromEnvironment(
  'LIVE_TARGET',
  defaultValue: 'x414',
);
Future<void> _waitFor(
  bool Function() done,
  Duration timeout,
  String what,
) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('publishes a screen share to the live server and reports negotiation', () async {
    await RustLib.init();
    final storePath = await resolveStorePath();
    final session = CoreSession(storePath: storePath);
    final preferences = await PreferencesStore.load(
      PreferencesStore.pathFor(storePath),
    );
    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(session),
        preferencesStoreProvider.overrideWithValue(preferences),
        storePathProvider.overrideWithValue(storePath),
      ],
    );
    addTearDown(() async {
      await container.read(streamPublisherProvider.notifier).stopScreenShare();
      await container.read(sessionViewProvider.notifier).disconnect();
      container.dispose();
    });

    // Keep the session event subscription alive for the whole run.
    container.read(sessionViewProvider);
    final controller = container.read(sessionViewProvider.notifier);

    final servers = await container.read(coreSessionProvider).listServers();
    if (servers.isEmpty) {
      fail('no stored server profile; add one in the app first');
    }
    final server = servers.firstWhere(
      (candidate) => candidate.host.contains('dreamhax'),
      orElse: () => servers.first,
    );
    // ignore: avoid_print
    print('LIVE server=${server.host}:${server.port} label=${server.label}');

    final connected = await controller.connect(
      id: server.id,
      nickname: 'flspeak-pub',
    );
    // ignore: avoid_print
    print('LIVE connect returned $connected');
    await _waitFor(
      () => container.read(sessionViewProvider).connected,
      const Duration(seconds: 30),
      'session to connect',
    );
    // ignore: avoid_print
    print(
      'LIVE connected as ${container.read(sessionViewProvider).selfClientId}',
    );

    final view = container.read(sessionViewProvider);
    final target = view.clients
        .where(
          (client) =>
              client.nickname.toLowerCase().contains(
                _targetNickname.toLowerCase(),
              ) &&
              client.id != view.selfClientId,
        )
        .firstOrNull;
    if (target != null && target.channelId != view.selfChannelId) {
      // ignore: avoid_print
      print('LIVE joining channel ${target.channelId} of ${target.nickname}');
      await controller.joinChannel(target.channelId);
      await Future<void>.delayed(const Duration(seconds: 1));
    } else if (target != null) {
      // ignore: avoid_print
      print('LIVE already in the channel of ${target.nickname}');
    } else {
      // ignore: avoid_print
      print(
        'LIVE target $_targetNickname not found; staying in current channel '
        '(clients: ${view.clients.map((c) => '${c.id}:${c.nickname}').join(', ')})',
      );
    }

    final publisher = container.read(streamPublisherProvider.notifier);
    final sources = await publisher.getDesktopSources(
      types: const [SourceType.Screen],
    );
    if (sources.isEmpty) {
      fail('no desktop sources: check Screen Recording permission');
    }
    final source = sources.first;
    // ignore: avoid_print
    print('LIVE sharing source ${source.id} ${source.name}');
    final started = await publisher.startScreenShare(
      sourceId: source.id,
      sourceName: source.name,
    );
    // ignore: avoid_print
    print('LIVE startScreenShare=$started');

    StreamPublisherState publisherState() =>
        container.read(streamPublisherProvider);
    await _waitFor(
      () => publisherState().streamId != null,
      const Duration(seconds: 30),
      'server to announce the stream',
    );
    // ignore: avoid_print
    print('LIVE stream id=${publisherState().streamId}');

    // Keep publishing and report every attempt, so a retry after a failed
    // negotiation needs no restart.
    final deadline = DateTime.now().add(const Duration(minutes: 28));
    var round = 0;
    while (DateTime.now().isBefore(deadline)) {
      try {
        await _waitFor(
          () => publisherState().viewerIds.isNotEmpty,
          const Duration(minutes: 3),
          'a viewer to ask for the stream',
        );
      } catch (_) {
        continue;
      }
      round += 1;
      // ignore: avoid_print
      print('LIVE round $round viewers=${publisherState().viewerIds}');
      try {
        await _waitFor(
          () =>
              publisherState().viewerIds.isEmpty ||
              publisherState().viewerFailure != null,
          const Duration(seconds: 40),
          'viewer answer/connection result',
        );
      } catch (_) {
        // The viewer stayed connected: that is the success case.
      }
      // ignore: avoid_print
      print(
        'LIVE round $round result viewers=${publisherState().viewerIds} '
        'failure=${publisherState().viewerFailure?.reason.name}',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }, timeout: const Timeout(Duration(minutes: 35)));
}
