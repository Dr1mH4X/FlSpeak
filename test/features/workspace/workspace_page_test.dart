// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:material_ui/material_ui.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton,
        TextField;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/notices.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/stream_publisher.dart';
import 'package:flspeak/core/stream_viewer.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/localization.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/features/workspace/widgets/chat_pane.dart';
import 'package:flspeak/features/workspace/workspace_page.dart';
import 'package:flspeak/features/workspace/workspace_shell.dart';
import 'package:flspeak/features/workspace/workspace_state.dart';
import 'package:flspeak/widgets/app_navigation_sidebar.dart';
import 'package:flspeak/widgets/glyph_segmented_control.dart';
import 'package:flspeak/widgets/monogram.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flspeak/widgets/scaffold/scaffold.dart' as app_scaffold;

class _Core extends Fake implements CoreSession {
  final joined = <({String streamId, int sourceClid})>[];
  final left = <String>[];
  final startedShares =
      <({String name, bool audio, int bitrate, int viewerLimit})>[];
  int stoppedShares = 0;

  @override
  Future<AccessView> access() async => const AccessView();

  @override
  Future<void> queryPeerIdentity({required int targetClid}) async {}

  @override
  Future<void> fetchBotCommands({
    required int targetClid,
    required String targetUid,
  }) async {}

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
  bool failDesktopSources = false;

  @override
  Future<List<DesktopCapturerSource>> getDesktopSources({
    List<SourceType> types = const [SourceType.Screen, SourceType.Window],
    ThumbnailSize? thumbnailSize,
  }) async {
    if (failDesktopSources) {
      throw StateError('desktop source enumeration failed');
    }
    return [
      DesktopSourceEntry(
        id: 'screen:1',
        name: 'Display 1',
        type: SourceType.Screen,
      ),
    ];
  }

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

  void publishMessages(List<ChatMessage> messages) {
    state = state.copyWith(messages: messages);
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
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            PrismRootScope(brightness: Brightness.light, child: child!),
        home: const Scaffold(body: WorkspacePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<ProviderContainer> _mountChannelPanel(
  WidgetTester tester, {
  required _Core core,
  required _FakeWidgetWebRtcBindings bindings,
}) async {
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
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            PrismRootScope(brightness: Brightness.light, child: child!),
        home: const Scaffold(body: SizedBox(width: 288, child: ChannelPanel())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'channel switch cross-fades and the exiting input area cannot receive focus or taps',
    (tester) async {
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
    },
  );

  testWidgets(
    'shows the screen share entry and supports watching, mute toggling, and closing',
    (tester) async {
      final core = _Core();
      final bindings = _FakeWidgetWebRtcBindings();
      final container = await _mount(tester, core: core, bindings: bindings);

      const stream = StreamView(
        id: 'stream-1',
        clientId: 2,
        name: 'Alice Screen',
        hasAudio: true,
      );
      (container.read(sessionViewProvider.notifier) as _Session).publishStreams(
        [stream],
      );
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
      await tester.tap(
        find.byKey(const ValueKey('stream-viewer-resize-handle')),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(
        find.byKey(const ValueKey('stream-viewer-resize-handle')),
      );
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
      expect(
        find.byKey(const ValueKey('stream-fullscreen-stage')),
        findsNothing,
      );

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
    },
  );

  testWidgets('viewer negotiation timeout is reported through NoticeCenter', (
    tester,
  ) async {
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

    await tester.tap(find.byKey(const ValueKey('stream-watch-stream-1')));
    await tester.pump();

    await container
        .read(streamViewerProvider.notifier)
        .handleOffer(
          streamId: 'stream-1',
          sourceClientId: 2,
          sdp: 'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\na=rtpmap:96 VP8/90000\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:1\r\na=rtpmap:111 opus/48000/2\r\n',
        );
    await tester.pump(
      defaultStreamNegotiationTimeout + const Duration(seconds: 1),
    );

    final notices = container.read(noticeCenterProvider);
    expect(notices, hasLength(1));
    expect(notices.single.message, '屏幕共享直连失败，请重试');
    expect(notices.single.tone, NoticeTone.error);
    expect(container.read(streamViewerProvider).endNotice, isNull);
    expect(core.left, ['stream-1']);
  });

  testWidgets(
    'multiple concurrent screen shares reuse one banner and switch smoothly between shares',
    (tester) async {
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
      (container.read(sessionViewProvider.notifier) as _Session).publishStreams(
        [stream1, stream2],
      );
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
    },
  );

  testWidgets(
    'publisher bar shows the current source and local preview toggle and can stop sharing through the controller',
    (tester) async {
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
      expect(
        find.byKey(const ValueKey('stream-publisher-banner')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'expanding the local preview in a short window with other share banners does not overflow vertically',
    (tester) async {
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
    },
  );

  testWidgets(
    'the screen share button opens the source picker and starts with the selected resolution and frame rate',
    (tester) async {
      final core = _Core();
      final bindings = _FakeWidgetWebRtcBindings();
      final container = await _mountChannelPanel(
        tester,
        core: core,
        bindings: bindings,
      );

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
      await tester.tap(
        find.byKey(const ValueKey('screen-share-confirm-start')),
      );
      await tester.pumpAndSettle();

      expect(core.startedShares, [
        (
          name: 'Display 1',
          audio: false,
          bitrate: 5000,
          viewerLimit: defaultMaxStreamViewers(),
        ),
      ]);
      expect(container.read(streamPublisherProvider).isActive, isTrue);

      // Tap the highlighted voice control bar button again to stop sharing.
      await tester.tap(shareBtn);
      await tester.pumpAndSettle();
      expect(core.stoppedShares, 1);
      expect(container.read(streamPublisherProvider).isActive, isFalse);
    },
  );

  testWidgets(
    'source enumeration failure is reported through NoticeCenter and keeps the empty state',
    (tester) async {
      final core = _Core();
      final bindings = _FakeWidgetWebRtcBindings()..failDesktopSources = true;
      final container = await _mountChannelPanel(
        tester,
        core: core,
        bindings: bindings,
      );

      await tester.tap(find.byKey(const ValueKey('voice-screen-share-toggle')));
      await tester.pumpAndSettle();

      expect(find.text('选择共享内容'), findsOneWidget);
      expect(find.text('未检测到可共享的屏幕或窗口'), findsOneWidget);
      final notices = container.read(noticeCenterProvider);
      expect(notices, hasLength(1));
      expect(notices.single.message, '无法读取屏幕和窗口列表，请检查屏幕录制权限后重试');
      expect(notices.single.tone, NoticeTone.error);
    },
  );

  testWidgets(
    'server chat starts with a welcome message containing ServerBadge and switches to channel chat after selecting a channel',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
        ],
      );
      addTearDown(container.dispose);

      // 给 _Session 注入一条服务器欢迎消息
      (container.read(sessionViewProvider.notifier) as _Session)
          .publishMessages([
            ChatMessage(
              from: 'My Community',
              fromUid: '',
              fromId: 0,
              text: 'Welcome to the server',
              at: DateTime(2026, 1, 1, 12, 0),
              scope: ChatScope.server,
              targetId: 0,
            ),
          ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            locale: const Locale('zh'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.light, child: child!),
            home: const Scaffold(
              body: Row(
                children: [
                  SizedBox(width: 280, child: ChannelPanel()),
                  Expanded(child: WorkspacePage()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(sessionViewProvider).chatScope, ChatScope.server);
      expect(find.text('Welcome to the server'), findsOneWidget);
      expect(find.text('My Community'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatPane),
          matching: find.byType(ServerBadge),
        ),
        findsOneWidget,
      );

      // 点击频道树中的频道，聊天范围应切换到频道视图
      await tester.tap(find.text('Studio'));
      await tester.pumpAndSettle();
      expect(container.read(sessionViewProvider).chatScope, ChatScope.channel);
    },
  );

  testWidgets(
    'wide channel view switches through GlyphSegmentedControl and replaces content immediately',
    (tester) async {
      await _mount(tester);
      final control = find.byWidgetPredicate(
        (widget) => widget is GlyphSegmentedControl,
      );
      expect(control, findsOneWidget);
      expect(find.byType(ChatPane), findsOneWidget);

      Finder segment(String label) =>
          find.descendant(of: control, matching: find.bySemanticsLabel(label));

      await tester.tap(segment('媒体'));
      await tester.pump();
      expect(find.byType(ChatPane), findsNothing);

      await tester.tap(segment('详情'));
      await tester.pump();
      expect(find.byType(ChatPane), findsNothing);

      await tester.tap(segment('消息'));
      await tester.pump();
      expect(find.byType(ChatPane), findsOneWidget);
    },
  );

  testWidgets('workspace view icons do not start window dragging', (
    tester,
  ) async {
    const channel = MethodChannel('flspeak/window');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _mount(tester);
    calls.clear();

    // 标题区域继续承担窗口拖动。
    final titleGesture = await tester.startGesture(
      tester.getCenter(find.text('Lounge')),
    );
    await titleGesture.moveBy(const Offset(30, 0));
    await titleGesture.up();
    await tester.pump();
    expect(calls.where((call) => call.method == 'startDragging'), isNotEmpty);
    // 双击识别器的判定窗口。
    await tester.pump(const Duration(milliseconds: 50));

    calls.clear();
    // 视图图标不在 WindowDragRegion 内，按住滑动不会开始窗口拖动。
    final segment = find.descendant(
      of: find.byWidgetPredicate((widget) => widget is GlyphSegmentedControl),
      matching: find.bySemanticsLabel('媒体'),
    );
    final segmentGesture = await tester.startGesture(tester.getCenter(segment));
    await segmentGesture.moveBy(const Offset(30, 0));
    await segmentGesture.up();
    await tester.pump();
    expect(calls.where((call) => call.method == 'startDragging'), isEmpty);
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('workspace detail pane titles use glyph icons', (tester) async {
    await _mount(tester);
    unawaited(
      showWorkspaceDetailSheet(
        tester.element(find.byType(WorkspacePage)),
        title: '频道详情',
        glyph: AppGlyphs.info,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ScaffoldBar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is GlyphIcon && identical(widget.glyph, AppGlyphs.info),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'workspace clears the status bar in narrow and tablet-wide layouts',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1.0;

      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(_Core()),
          sessionViewProvider.overrideWith(_Session.new),
        ],
      );
      addTearDown(container.dispose);

      Future<void> mount(Size size) async {
        // 先卸掉上一轮页面，避免窄屏推入的频道路由盖住宽屏外壳。
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildAppTheme(Brightness.light),
              locale: const Locale('zh'),
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(padding: const EdgeInsets.only(top: 40, bottom: 24)),
                child: PrismRootScope(
                  brightness: Brightness.light,
                  child: child!,
                ),
              ),
              home: const WorkspaceShell(
                location: '/workspace',
                child: WorkspacePage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // 窄屏一级频道总览使用 FlClash Scaffold，顶栏语音/断开操作退避状态栏
      await mount(const Size(390, 844));
      expect(find.byType(app_scaffold.Scaffold), findsOneWidget);
      expect(find.byType(ChannelPanel), findsOneWidget);
      expect(find.byType(WorkspacePage), findsNothing);
      expect(
        tester.getTopLeft(find.byIcon(Icons.mic_rounded)).dy,
        greaterThanOrEqualTo(40.0),
      );
      expect(
        tester.getTopLeft(find.byIcon(Icons.call_end_rounded)).dy,
        greaterThanOrEqualTo(40.0),
      );

      // 点按频道推入二级频道页：无视图切换条，返回键与溢出菜单均退避状态栏
      await tester.tap(find.text('Lounge'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is GlyphSegmentedControl),
        findsNothing,
      );
      final backFinder = find.bySemanticsLabel(
        MaterialLocalizations.of(tester.element(find.byType(WorkspacePage)))
            .backButtonTooltip,
      );
      expect(tester.getTopLeft(backFinder).dy, greaterThanOrEqualTo(40.0));
      expect(
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(WorkspacePage),
                matching: find.byWidgetPredicate(
                  (w) => w is GlyphIcon && w.glyph == Glyphs.more,
                ),
              ),
            )
            .dy,
        greaterThanOrEqualTo(40.0),
      );

      // 宽屏（Android 平板）：全局侧栏、频道栏顶栏、主区域顶栏全部退避状态栏
      await mount(const Size(900, 800));
      expect(
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(AppNavigationSidebar),
                matching: find.byType(GlyphIcon),
              ),
            )
            .dy,
        greaterThanOrEqualTo(40.0),
      );
      expect(
        tester.getTopLeft(find.byIcon(Icons.dns_outlined)).dy,
        greaterThanOrEqualTo(40.0),
      );
      expect(
        tester
            .getTopLeft(
              find.byWidgetPredicate(
                (widget) => widget is GlyphSegmentedControl,
              ),
            )
            .dy,
        greaterThanOrEqualTo(40.0),
      );
    },
  );
}
