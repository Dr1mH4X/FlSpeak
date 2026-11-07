// ignore_for_file: depend_on_referenced_packages

import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/stream_publisher.dart';
import 'package:flspeak/core/stream_viewer.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/features/workspace/widgets/chat_pane.dart';
import 'package:flspeak/features/workspace/workspace_page.dart';
import 'package:flspeak/features/workspace/workspace_state.dart';

class _Core extends Fake implements CoreSession {
  final joined = <({String streamId, int sourceClid})>[];
  final left = <String>[];
  final startedShares =
      <({String name, bool audio, int bitrate, int viewerLimit})>[];
  int stoppedShares = 0;

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

  @override
  Future<void> startScreenShare({
    required String name,
    required bool audio,
    required int bitrate,
    required int viewerLimit,
  }) async {
    startedShares.add((
      name: name,
      audio: audio,
      bitrate: bitrate,
      viewerLimit: viewerLimit,
    ));
  }

  @override
  Future<void> stopScreenShare() async {
    stoppedShares++;
  }

  @override
  Future<void> respondStreamJoinRequest({
    required int viewerClid,
    required bool accept,
    required String offerSdp,
  }) async {}

  @override
  Future<Uint8List> fetchAvatar({required String uid}) async => Uint8List(0);
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

class _FakeWidgetVideoTrack extends Fake implements MediaStreamTrack {
  @override
  StreamTrackCallback? onEnded;

  @override
  String? get id => 'widget-video-track';

  @override
  String? get kind => 'video';

  @override
  Future<void> applyConstraints([Map<String, dynamic>? constraints]) async {}

  @override
  Future<void> stop() async {}
}

class _FakeWidgetMediaStream extends Fake implements MediaStream {
  final _videoTrack = _FakeWidgetVideoTrack();

  @override
  String get id => 'widget-stream';

  @override
  List<MediaStreamTrack> getAudioTracks() => const [];

  @override
  List<MediaStreamTrack> getVideoTracks() => [_videoTrack];

  @override
  List<MediaStreamTrack> getTracks() => [_videoTrack];

  @override
  Future<void> dispose() async {}
}

class _FakeWidgetWebRtcBindings extends WebRtcBindings {
  final renderers = <_FakeWidgetRenderer>[];
  final peers = <_FakeWidgetPeer>[];

  @override
  Future<List<DesktopCapturerSource>> getDesktopSources({
    List<SourceType> types = const [SourceType.Screen, SourceType.Window],
    ThumbnailSize? thumbnailSize,
  }) async => [
    DesktopSourceEntry(
      id: 'screen:1',
      name: 'Display 1',
      type: SourceType.Screen,
    ),
  ];

  @override
  Future<MediaStream> getDisplayMedia(
    Map<String, dynamic> mediaConstraints,
  ) async => _FakeWidgetMediaStream();

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
  Size size = const Size(1000, 800),
  _Core? core,
  _FakeWidgetWebRtcBindings? bindings,
}) async {
  tester.view.physicalSize = size;
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
    // Remote stream banner reuses compact icon button and does not use big button.
    expect(find.byType(FilledButton), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stream-banner-stream-1')),
        matching: find.byType(IconButton),
      ),
      findsOneWidget,
    );
    // When no video is expanded, resize handle is not shown.
    expect(
      find.byKey(const ValueKey('stream-viewer-resize-handle')),
      findsNothing,
    );

    // Click watch button in top banner -> triggers JoinStream.
    await tester.tap(find.byKey(const ValueKey('stream-watch-stream-1')));
    await tester.pump();
    expect(core.joined, [(streamId: 'stream-1', sourceClid: 2)]);
    expect(find.byKey(const ValueKey('stream-viewer-stage')), findsOneWidget);
    // Resize handle appears at the bottom of the expanded screen share section.
    expect(
      find.byKey(const ValueKey('stream-viewer-resize-handle')),
      findsOneWidget,
    );

    // Drag handle downwards to resize video area towards the bottom.
    await tester.drag(
      find.byKey(const ValueKey('stream-viewer-resize-handle')),
      const Offset(0, 300),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(preferencesProvider).streamViewerHeight, isNotNull);
    expect(
      container.read(preferencesProvider).streamViewerHeight!,
      greaterThan(250.0),
    );

    // Verify stage card is not clipped when pulled towards the bottom:
    // the card container's bottom edge plus bottom padding must remain above the resize handle.
    final stageRect = tester.getRect(
      find.byKey(const ValueKey('stream-viewer-stage')),
    );
    final handleRect = tester.getRect(
      find.byKey(const ValueKey('stream-viewer-resize-handle')),
    );
    expect(handleRect.top, greaterThanOrEqualTo(stageRect.bottom + 6.0));

    // Double-tap handle to reset height to default adaptive calculation.
    await tester.tap(find.byKey(const ValueKey('stream-viewer-resize-handle')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('stream-viewer-resize-handle')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(preferencesProvider).streamViewerHeight, isNull);

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

    // Enter fullscreen -> opens full-window stage with floating bottom bar.
    await tester.tap(find.byKey(const ValueKey('stream-fullscreen-toggle')));
    await tester.pump();
    await tester.pump();
    expect(container.read(streamViewerProvider).isFullScreen, isTrue);
    expect(
      find.byKey(const ValueKey('stream-fullscreen-stage')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stream-fullscreen-controls')),
      findsOneWidget,
    );

    // Exit fullscreen via floating bottom bar button.
    await tester.tap(
      find.byKey(const ValueKey('stream-fullscreen-exit-button')),
    );
    await tester.pump();
    await tester.pump();
    expect(container.read(streamViewerProvider).isFullScreen, isFalse);
    expect(find.byKey(const ValueKey('stream-fullscreen-stage')), findsNothing);

    // Click close button -> leaves stream and disposes renderer & peer.
    await tester.tap(find.byKey(const ValueKey('stream-close-button')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('stream-viewer-resize-handle')),
      findsNothing,
    );
    expect(core.left, ['stream-1']);
    expect(find.byType(RTCVideoView), findsNothing);
    expect(bindings.renderers.single.disposed, isTrue);
    expect(bindings.peers.single.closed, isTrue);
    expect(bindings.peers.single.disposed, isTrue);
  });

  testWidgets('多人同时屏幕共享时复用同一横幅组件且支持在多个屏幕共享间平滑切换', (tester) async {
    final core = _Core();
    final bindings = _FakeWidgetWebRtcBindings();
    final container = await _mount(tester, core: core, bindings: bindings);

    const stream1 = StreamView(
      id: 'stream-1',
      clientId: 2,
      name: 'Alice Screen',
      hasAudio: true,
    );
    const stream2 = StreamView(
      id: 'stream-2',
      clientId: 3,
      name: 'Bob Screen',
      hasAudio: true,
    );
    (container.read(sessionViewProvider.notifier) as _Session).publishStreams([
      stream1,
      stream2,
    ]);
    await tester.pump();

    // Both remote screen shares are rendered as banners using compact icon buttons.
    expect(
      find.byKey(const ValueKey('stream-banner-stream-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stream-banner-stream-2')),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);

    // Watch Alice's screen.
    await tester.tap(find.byKey(const ValueKey('stream-watch-stream-1')));
    await tester.pump();
    expect(core.joined, [(streamId: 'stream-1', sourceClid: 2)]);
    expect(find.byKey(const ValueKey('stream-viewer-stage')), findsOneWidget);
    // Bob's screen share remains available as a collapsed banner.
    expect(
      find.byKey(const ValueKey('stream-banner-stream-2')),
      findsOneWidget,
    );

    // Switch to watch Bob's screen.
    await tester.tap(find.byKey(const ValueKey('stream-watch-stream-2')));
    await tester.pump();
    expect(core.left, ['stream-1']);
    expect(core.joined, [
      (streamId: 'stream-1', sourceClid: 2),
      (streamId: 'stream-2', sourceClid: 3),
    ]);
    // Alice's screen share becomes a collapsed banner while Bob's is watching.
    expect(
      find.byKey(const ValueKey('stream-banner-stream-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('stream-viewer-stage')), findsOneWidget);
  });

  testWidgets('推流状态栏展示当前屏幕共享源与本地预览开关，并可通过控制器停止共享', (tester) async {
    final core = _Core();
    final bindings = _FakeWidgetWebRtcBindings();
    final container = await _mount(tester, core: core, bindings: bindings);

    final started = await container
        .read(sessionViewProvider.notifier)
        .startScreenShare(sourceId: 'screen:1', sourceName: 'Display 1');
    expect(started, isTrue);
    container
        .read(streamPublisherProvider.notifier)
        .handlePublished(streamId: 'pub-1');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('stream-publisher-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('Display 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stream-publisher-viewer-count')),
      findsOneWidget,
    );
    expect(find.text('0 人观看'), findsOneWidget);

    // Toggle local preview stage.
    await tester.tap(
      find.byKey(const ValueKey('stream-publisher-preview-toggle')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stream-publisher-preview-stage')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stream-viewer-resize-handle')),
      findsOneWidget,
    );

    // Drag handle downwards towards the bottom of the window.
    await tester.drag(
      find.byKey(const ValueKey('stream-viewer-resize-handle')),
      const Offset(0, 300),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // The publisher banner card container must not be truncated / clipped at the bottom.
    final publisherCardRect = tester.getRect(
      find.byKey(const ValueKey('stream-publisher-banner')),
    );
    final publisherHandleRect = tester.getRect(
      find.byKey(const ValueKey('stream-viewer-resize-handle')),
    );
    expect(
      publisherHandleRect.top,
      greaterThanOrEqualTo(publisherCardRect.bottom + 6.0),
    );

    // Stop sharing via session controller.
    await container.read(sessionViewProvider.notifier).stopScreenShare();
    await tester.pump();
    expect(core.stoppedShares, 1);
    expect(find.byKey(const ValueKey('stream-publisher-banner')), findsNothing);
  });

  testWidgets('矮窗口下展开推流本地预览并存在其他屏幕共享横幅时不会发生纵向溢出', (tester) async {
    final core = _Core();
    final bindings = _FakeWidgetWebRtcBindings();
    final container = await _mount(
      tester,
      size: const Size(900, 420),
      core: core,
      bindings: bindings,
    );
    (container.read(sessionViewProvider.notifier) as _Session).publishStreams(
      const [
        StreamView(
          id: 'remote-stream-1',
          clientId: 2,
          name: 'Bob Screen',
          hasAudio: true,
        ),
      ],
    );
    await tester.pump();

    final started = await container
        .read(sessionViewProvider.notifier)
        .startScreenShare(sourceId: 'screen:1', sourceName: 'Display 1');
    expect(started, isTrue);
    container
        .read(streamPublisherProvider.notifier)
        .handlePublished(streamId: 'pub-1');
    await tester.pump();

    // Expand local preview on a 420px tall window -> must not overflow.
    await tester.tap(
      find.byKey(const ValueKey('stream-publisher-preview-toggle')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('stream-publisher-preview-stage')),
      findsOneWidget,
    );
  });

  testWidgets('语音控制栏屏幕共享按钮呼出桌面源选择弹窗并可选择分辨率与帧率开播', (tester) async {
    final core = _Core();
    final bindings = _FakeWidgetWebRtcBindings();
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        coreSessionProvider.overrideWithValue(core),
        webRtcBindingsProvider.overrideWithValue(bindings),
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
          home: const Scaffold(
            body: SizedBox(width: 288, child: ChannelPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap "Share screen" toggle in voice footer -> opens picker modal.
    final shareBtn = find.byKey(const ValueKey('voice-screen-share-toggle'));
    expect(shareBtn, findsOneWidget);
    await tester.tap(shareBtn);
    await tester.pumpAndSettle();

    expect(find.text('选择共享内容'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('screen-source-screen:1')),
      findsOneWidget,
    );
    expect(find.byType(Tooltip), findsNothing);

    // Choose 720p and 60 FPS in the picker.
    await tester.tap(find.byKey(const ValueKey('screen-share-res-720p')));
    await tester.tap(find.byKey(const ValueKey('screen-share-fps-60')));
    await tester.pump();

    // Confirm start sharing.
    await tester.tap(find.byKey(const ValueKey('screen-share-confirm-start')));
    await tester.pumpAndSettle();

    expect(core.startedShares, [
      (
        name: 'Display 1',
        audio: false,
        bitrate: 5000,
        viewerLimit: defaultMaxStreamViewers,
      ),
    ]);
    expect(container.read(streamPublisherProvider).isActive, isTrue);

    // Tap the highlighted voice control bar button again to stop sharing.
    await tester.tap(shareBtn);
    await tester.pumpAndSettle();
    expect(core.stoppedShares, 1);
    expect(container.read(streamPublisherProvider).isActive, isFalse);
  });
}
