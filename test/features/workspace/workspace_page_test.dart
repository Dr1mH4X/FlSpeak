// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/stream_viewer.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/features/workspace/widgets/chat_pane.dart';
import 'package:flspeak/features/workspace/workspace_page.dart';
import 'package:flspeak/features/workspace/workspace_state.dart';

class _Core extends Fake implements CoreSession {
  final joined = <({String streamId, int sourceClid})>[];
  final left = <String>[];

  @override
  Future<AccessView> access() async => const AccessView();

  @override
  Future<void> joinStream({
    required String streamId,
    required int sourceClid,
  }) async {
    joined.add((streamId: streamId, sourceClid: sourceClid));
  }

  @override
  Future<void> leaveStream({required String streamId}) async {
    left.add(streamId);
  }

  @override
  Future<void> sendStreamAnswer({
    required String streamId,
    required int targetClid,
    required String sdp,
  }) async {}
}

class _FakeWidgetRenderer extends RTCVideoRenderer {
  bool disposed = false;
  MediaStream? attached;

  @override
  int? get textureId => disposed ? null : 7;

  @override
  bool get renderVideo => !disposed && attached != null;

  @override
  MediaStream? get srcObject => attached;

  @override
  set srcObject(MediaStream? stream) {
    attached = stream;
    value = stream == null
        ? RTCVideoValue.empty
        : value.copyWith(width: 1280, height: 720, renderVideo: true);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    attached = null;
    await super.dispose();
  }
}

class _FakeWidgetTransceiver extends Fake implements RTCRtpTransceiver {
  @override
  String get mid => '0';

  @override
  Future<void> setCodecPreferences(List<RTCRtpCodecCapability> codecs) async {}
}

class _FakeWidgetPeer extends Fake implements RTCPeerConnection {
  bool closed = false;
  bool disposed = false;

  @override
  void Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  void Function(RTCTrackEvent event)? onTrack;

  @override
  void Function(MediaStream stream)? onAddStream;

  @override
  void Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  void Function(RTCIceConnectionState state)? onIceConnectionState;

  @override
  Future<RTCRtpTransceiver> addTransceiver({
    MediaStreamTrack? track,
    RTCRtpMediaType? kind,
    RTCRtpTransceiverInit? init,
  }) async => _FakeWidgetTransceiver();

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {}

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription(
    'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\na=rtpmap:96 VP8/90000\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:1\r\na=rtpmap:111 opus/48000/2\r\n',
    'answer',
  );

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {}

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeWidgetMediaStream extends Fake implements MediaStream {
  @override
  String get id => 'widget-stream';

  @override
  List<MediaStreamTrack> getAudioTracks() => const [];

  @override
  List<MediaStreamTrack> getTracks() => const [];

  @override
  Future<void> dispose() async {}
}

class _FakeWidgetWebRtcBindings implements WebRtcBindings {
  final renderers = <_FakeWidgetRenderer>[];
  final peers = <_FakeWidgetPeer>[];

  @override
  Future<RTCPeerConnection> createPeer(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) async {
    final peer = _FakeWidgetPeer();
    peers.add(peer);
    return peer;
  }

  @override
  RTCVideoRenderer createVideoRenderer() {
    final renderer = _FakeWidgetRenderer();
    renderers.add(renderer);
    return renderer;
  }

  @override
  Future<MediaStream> createMediaStream(String label) async =>
      _FakeWidgetMediaStream();

  @override
  Future<RTCRtpCapabilities?> getVideoReceiverCapabilities() async => null;

  @override
  Future<void> setTrackVolume(double volume, MediaStreamTrack track) async {}
}

class _Session extends SessionController {
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
    activeServerId: 'test',
    connectionEpoch: 1,
    channels: [
      ChannelView(
        id: 5,
        parentId: 0,
        name: 'Lounge',
        description: '',
        order: 0,
      ),
      ChannelView(
        id: 6,
        parentId: 0,
        name: 'Studio',
        description: '',
        order: 0,
      ),
    ],
    clients: [
      ClientView(id: 1, nickname: 'Me', uid: 'uid-me', channelId: 5),
      ClientView(id: 2, nickname: 'Alice', uid: 'uid-alice', channelId: 5),
    ],
  );

  void publishStreams(List<StreamView> streams, {String? watching}) {
    state = state.copyWith(streams: streams, watchingStreamId: watching);
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  _Core? core,
  _FakeWidgetWebRtcBindings? bindings,
}) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      coreSessionProvider.overrideWithValue(core ?? _Core()),
      if (bindings != null) webRtcBindingsProvider.overrideWithValue(bindings),
      sessionViewProvider.overrideWith(_Session.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: WorkspacePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('频道切换交叉淡入，退出中的输入区不能接收焦点或点击', (tester) async {
    final container = await _mount(tester);
    final field = find.descendant(
      of: find.byType(ChatPane),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.pump();
    final input = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(input.focusNode.hasFocus, isTrue);
    container
        .read(selectedChannelProvider.notifier)
        .select(6, serverId: 'test');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(ChatPane, skipOffstage: false), findsNWidgets(2));
    final outgoing = find.byWidgetPredicate(
      (widget) => widget is ChatPane && widget.channelName == 'Lounge',
      skipOffstage: false,
    );
    expect(
      find.ancestor(
        of: outgoing,
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsWidgets,
    );
    expect(input.focusNode.hasFocus, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(ChatPane), findsOneWidget);
    expect(
      tester.widget<ChatPane>(find.byType(ChatPane)).channelName,
      'Studio',
    );
  });

  testWidgets('展示屏幕共享入口并支持观看、静音切换与关闭', (tester) async {
    final core = _Core();
    final bindings = _FakeWidgetWebRtcBindings();
    final container = await _mount(tester, core: core, bindings: bindings);

    const stream = StreamView(
      id: 'stream-1',
      clientId: 2,
      name: 'Alice Screen',
      hasAudio: true,
    );
    (container.read(sessionViewProvider.notifier) as _Session).publishStreams([
      stream,
    ]);
    await tester.pump();

    // Top banner and member row indicator are both shown.
    expect(
      find.byKey(const ValueKey('stream-banner-stream-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('member-stream-2')), findsOneWidget);

    // Click watch button in top banner -> triggers JoinStream.
    await tester.tap(find.byKey(const ValueKey('stream-watch-stream-1')));
    await tester.pump();
    expect(core.joined, [(streamId: 'stream-1', sourceClid: 2)]);
    expect(find.byKey(const ValueKey('stream-viewer-stage')), findsOneWidget);

    // Receive Offer and attach remote stream -> renders RTCVideoView.
    await container
        .read(streamViewerProvider.notifier)
        .handleOffer(
          streamId: 'stream-1',
          sourceClientId: 2,
          sdp: 'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\na=rtpmap:96 VP8/90000\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:1\r\na=rtpmap:111 opus/48000/2\r\n',
        );
    bindings.peers.single.onAddStream?.call(_FakeWidgetMediaStream());
    await tester.pump();

    expect(find.byType(RTCVideoView), findsOneWidget);
    expect(container.read(streamViewerProvider).isMuted, isFalse);

    // Toggle mute button.
    await tester.tap(find.byKey(const ValueKey('stream-mute-toggle')));
    await tester.pump();
    expect(container.read(streamViewerProvider).isMuted, isTrue);

    // Click close button -> leaves stream and disposes renderer & peer.
    await tester.tap(find.byKey(const ValueKey('stream-close-button')));
    await tester.pump();

    expect(core.left, ['stream-1']);
    expect(find.byType(RTCVideoView), findsNothing);
    expect(bindings.renderers.single.disposed, isTrue);
    expect(bindings.peers.single.closed, isTrue);
    expect(bindings.peers.single.disposed, isTrue);
  });
}
