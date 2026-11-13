import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/stream_publisher.dart';
import 'package:flspeak/core/stream_viewer.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class _FakeCoreSession extends Fake implements CoreSession {
  _FakeCoreSession(this.eventsController);

  final StreamController<CoreEvent> eventsController;
  final startedShares =
      <({String name, bool audio, int bitrate, int viewerLimit})>[];
  int stopShareCalls = 0;
  final joinResponses = <({int viewerClid, bool accept, String offerSdp})>[];
  final sentPublisherCandidates =
      <({int viewerClid, String sdp, String? mid, int? mLine})>[];
  Completer<void>? respondJoinRequestGate;
  Exception? sendPublisherCandidateError;
  final List<int> kickedViewers = [];

  @override
  Stream<CoreEvent> events() => eventsController.stream;

  @override
  Future<List<ServerProfileView>> listServers() async => const [];

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
    stopShareCalls++;
  }

  @override
  Future<void> respondStreamJoinRequest({
    required int viewerClid,
    required bool accept,
    required String offerSdp,
  }) async {
    if (respondJoinRequestGate != null) {
      await respondJoinRequestGate!.future;
    }
    joinResponses.add((
      viewerClid: viewerClid,
      accept: accept,
      offerSdp: offerSdp,
    ));
  }

  @override
  Future<void> sendPublisherIceCandidate({
    required int viewerClid,
    required String sdp,
    String? mid,
    int? mLine,
  }) async {
    if (sendPublisherCandidateError != null) {
      throw sendPublisherCandidateError!;
    }
    sentPublisherCandidates.add((
      viewerClid: viewerClid,
      sdp: sdp,
      mid: mid,
      mLine: mLine,
    ));
  }

  @override
  Future<void> kickStreamViewer({required int viewerClid}) async {
    kickedViewers.add(viewerClid);
  }
}

class _FakeRtpSender extends Fake implements RTCRtpSender {
  _FakeRtpSender({this.track});

  @override
  final MediaStreamTrack? track;

  RTCRtpParameters _parameters = RTCRtpParameters(
    encodings: [RTCRtpEncoding()],
  );
  RTCRtpParameters? updatedParameters;

  @override
  RTCRtpParameters get parameters => _parameters;

  @override
  Future<bool> setParameters(RTCRtpParameters parameters) async {
    _parameters = parameters;
    updatedParameters = parameters;
    return true;
  }
}

class _FakeTransceiver extends Fake implements RTCRtpTransceiver {
  _FakeTransceiver({
    required this.kind,
    required this.midValue,
    required this.directionValue,
  });

  final RTCRtpMediaType kind;
  final String midValue;
  TransceiverDirection directionValue;
  List<RTCRtpCodecCapability>? preferredCodecs;

  @override
  String get mid => midValue;

  @override
  Future<void> setDirection(TransceiverDirection direction) async {
    directionValue = direction;
  }

  @override
  Future<void> setCodecPreferences(List<RTCRtpCodecCapability> codecs) async {
    preferredCodecs = codecs;
  }
}

class _FakeMediaStreamTrack extends Fake implements MediaStreamTrack {
  _FakeMediaStreamTrack({required this.trackId, required this.trackKind});

  final String trackId;
  final String trackKind;
  bool isEnabled = true;
  bool isStopped = false;
  Map<String, dynamic>? appliedConstraints;

  @override
  StreamTrackCallback? onEnded;

  @override
  String? get id => trackId;

  @override
  String? get kind => trackKind;

  @override
  bool get enabled => isEnabled;

  @override
  set enabled(bool value) {
    isEnabled = value;
  }

  @override
  Future<void> applyConstraints([Map<String, dynamic>? constraints]) async {
    appliedConstraints = constraints;
  }

  @override
  Future<void> stop() async {
    isStopped = true;
  }
}

class _FakeMediaStream extends Fake implements MediaStream {
  _FakeMediaStream(
    this.streamId, {
    List<MediaStreamTrack> audioTracks = const [],
    List<MediaStreamTrack> videoTracks = const [],
  }) : _audioTracks = List<MediaStreamTrack>.of(audioTracks),
       _videoTracks = List<MediaStreamTrack>.of(videoTracks);

  final String streamId;
  final List<MediaStreamTrack> _audioTracks;
  final List<MediaStreamTrack> _videoTracks;
  bool disposed = false;

  @override
  String get id => streamId;

  @override
  String get ownerTag => 'local';

  @override
  List<MediaStreamTrack> getAudioTracks() => _audioTracks;

  @override
  List<MediaStreamTrack> getVideoTracks() => _videoTracks;

  @override
  List<MediaStreamTrack> getTracks() => [..._videoTracks, ..._audioTracks];

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeVideoRenderer extends RTCVideoRenderer {
  bool initialized = false;
  bool isDisposed = false;
  MediaStream? attachedStream;

  @override
  int? get textureId => initialized && !isDisposed ? 1 : null;

  @override
  bool get renderVideo => initialized && !isDisposed && attachedStream != null;

  @override
  MediaStream? get srcObject => attachedStream;

  @override
  set srcObject(MediaStream? stream) {
    attachedStream = stream;
    value = stream == null
        ? RTCVideoValue.empty
        : value.copyWith(width: 1920, height: 1080, renderVideo: true);
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> dispose() async {
    if (isDisposed) return;
    isDisposed = true;
    attachedStream = null;
    await super.dispose();
  }
}

class _FakePeerConnection extends Fake implements RTCPeerConnection {
  _FakePeerConnection({
    required this.configuration,
    required this.offerSdp,
    this.remoteDescriptionGate,
  });

  final Map<String, dynamic> configuration;
  final String offerSdp;
  final Completer<void>? remoteDescriptionGate;
  bool throwOnModifiedSetLocalDescription = false;
  final List<String> mediaSetupOrder = [];
  final List<_FakeTransceiver> transceiversList = [];
  final List<_FakeRtpSender> sendersList = [];
  final List<RTCIceCandidate> addedCandidates = [];
  RTCSessionDescription? localDescription;
  RTCSessionDescription? remoteDescription;
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
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async {
    final kind = track.kind == 'audio'
        ? RTCRtpMediaType.RTCRtpMediaTypeAudio
        : RTCRtpMediaType.RTCRtpMediaTypeVideo;
    final mid = '${transceiversList.length}';
    mediaSetupOrder.add('addTrack:${track.kind}:mid=$mid');
    final transceiver = _FakeTransceiver(
      kind: kind,
      midValue: mid,
      directionValue: TransceiverDirection.SendRecv,
    );
    transceiversList.add(transceiver);
    final sender = _FakeRtpSender(track: track);
    sendersList.add(sender);
    return sender;
  }

  @override
  Future<RTCRtpTransceiver> addTransceiver({
    MediaStreamTrack? track,
    RTCRtpMediaType? kind,
    RTCRtpTransceiverInit? init,
  }) async {
    final resolvedKind = kind ?? RTCRtpMediaType.RTCRtpMediaTypeAudio;
    final mid = '${transceiversList.length}';
    final label = resolvedKind == RTCRtpMediaType.RTCRtpMediaTypeAudio
        ? 'audio'
        : 'video';
    final direction = init?.direction ?? TransceiverDirection.SendOnly;
    mediaSetupOrder.add('addTransceiver:$label:mid=$mid:${direction.name}');
    final transceiver = _FakeTransceiver(
      kind: resolvedKind,
      midValue: mid,
      directionValue: direction,
    );
    transceiversList.add(transceiver);
    return transceiver;
  }

  @override
  Future<List<RTCRtpTransceiver>> getTransceivers() async => transceiversList;

  @override
  Future<List<RTCRtpSender>> getSenders() async => sendersList;

  Map<String, dynamic>? createOfferConstraints;

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    createOfferConstraints = constraints;
    mediaSetupOrder.add('createOffer');
    return RTCSessionDescription(offerSdp, 'offer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    if (throwOnModifiedSetLocalDescription && description.sdp != offerSdp) {
      throw Exception('INVALID_MODIFICATION: modified local description');
    }
    localDescription = description;
    mediaSetupOrder.add('setLocalDescription');
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (remoteDescriptionGate != null) {
      await remoteDescriptionGate!.future;
    }
    remoteDescription = description;
    mediaSetupOrder.add('setRemoteDescription');
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    addedCandidates.add(candidate);
    mediaSetupOrder.add('addCandidate:${candidate.candidate}');
  }

  @override
  Future<void> close() async {
    closed = true;
    mediaSetupOrder.add('close');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    mediaSetupOrder.add('dispose');
  }
}

class _FakePublisherWebRtcBindings extends WebRtcBindings {
  _FakePublisherWebRtcBindings({
    List<DesktopCapturerSource>? sources,
    _FakeMediaStream? displayStream,
    this.remoteDescriptionGate,
    this.offerSdp,
  }) : sources =
           sources ??
           [
             DesktopSourceEntry(
               id: 'screen:0',
               name: 'Entire Screen',
               type: SourceType.Screen,
             ),
             DesktopSourceEntry(
               id: 'window:42',
               name: 'Code Editor',
               type: SourceType.Window,
             ),
           ],
       displayStream =
           displayStream ??
           _FakeMediaStream(
             'local-display-stream',
             videoTracks: [
               _FakeMediaStreamTrack(trackId: 'video-0', trackKind: 'video'),
             ],
           );

  final List<DesktopCapturerSource> sources;
  final _FakeMediaStream displayStream;
  final Completer<void>? remoteDescriptionGate;
  final String? offerSdp;
  bool throwOnModifiedSetLocalDescription = false;
  final List<_FakePeerConnection> createdPeers = [];
  final List<_FakeVideoRenderer> createdRenderers = [];
  Map<String, dynamic>? lastDisplayMediaConstraints;

  @override
  Future<List<DesktopCapturerSource>> getDesktopSources({
    List<SourceType> types = const [SourceType.Screen, SourceType.Window],
    ThumbnailSize? thumbnailSize,
  }) async {
    return sources.where((s) => types.contains(s.type)).toList();
  }

  @override
  Future<MediaStream> getDisplayMedia(
    Map<String, dynamic> mediaConstraints,
  ) async {
    lastDisplayMediaConstraints = mediaConstraints;
    return displayStream;
  }

  @override
  Future<RTCPeerConnection> createPeer(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) async {
    final peer = _FakePeerConnection(
      configuration: configuration,
      offerSdp: offerSdp ?? _samplePublisherRawOfferSdp,
      remoteDescriptionGate: remoteDescriptionGate,
    )..throwOnModifiedSetLocalDescription = throwOnModifiedSetLocalDescription;
    createdPeers.add(peer);
    return peer;
  }

  @override
  RTCVideoRenderer createVideoRenderer() {
    final renderer = _FakeVideoRenderer();
    createdRenderers.add(renderer);
    return renderer;
  }

  @override
  Future<MediaStream> createMediaStream(String label) async {
    return _FakeMediaStream(label);
  }

  @override
  Future<RTCRtpCapabilities?> getVideoReceiverCapabilities() async => null;

  @override
  Future<RTCRtpCapabilities?> getVideoSenderCapabilities() async {
    return RTCRtpCapabilities(
      codecs: [
        RTCRtpCodecCapability(
          clockRate: 90000,
          mimeType: 'video/H264',
          sdpFmtpLine: 'profile-level-id=42e01f',
        ),
        RTCRtpCodecCapability(clockRate: 90000, mimeType: 'video/VP8'),
      ],
      headerExtensions: const [],
      fecMechanisms: const [],
    );
  }

  @override
  Future<void> setTrackVolume(double volume, MediaStreamTrack track) async {}
}

/// The offer libwebrtc writes for a publisher: VP8 first (codec preferences),
/// then H.264, video MID 0 and a send-only audio section at MID 1.
const _samplePublisherRawOfferSdp =
    'v=0\r\n'
    'o=- 10 2 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'a=group:BUNDLE 0 1\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 96 97 102 103\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=mid:0\r\n'
    'a=sendonly\r\n'
    'a=rtpmap:96 VP8/90000\r\n'
    'a=rtcp-fb:96 nack\r\n'
    'a=rtpmap:97 rtx/90000\r\n'
    'a=fmtp:97 apt=96\r\n'
    'a=rtpmap:102 H264/90000\r\n'
    'a=fmtp:102 profile-level-id=42e01f\r\n'
    'a=rtpmap:103 rtx/90000\r\n'
    'a=fmtp:103 apt=102\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=mid:1\r\n'
    'a=sendonly\r\n'
    'a=rtpmap:111 opus/48000/2\r\n';

const _sampleViewerAnswerSdp =
    'v=0\r\n'
    'o=- 20 2 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'a=group:BUNDLE 0 1\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 96 97\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=mid:0\r\n'
    'a=recvonly\r\n'
    'a=rtpmap:96 VP8/90000\r\n'
    'a=rtpmap:97 rtx/90000\r\n'
    'a=fmtp:97 apt=96\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=mid:1\r\n'
    'a=recvonly\r\n'
    'a=rtpmap:111 opus/48000/2\r\n';

Future<void> _pumpEventQueue() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('StreamPublisherController', () {
    test('enumerates desktop sources, captures local display stream, and auto-stops when video track onEnded fires', () async {
      final events = StreamController<CoreEvent>.broadcast();
      final core = _FakeCoreSession(events);
      final bindings = _FakePublisherWebRtcBindings();

      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          webRtcBindingsProvider.overrideWithValue(bindings),
        ],
      );
      addTearDown(() async {
        await events.close();
        container.dispose();
      });

      container.read(sessionViewProvider);
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 1, channelId: 5),
        ),
      );
      await _pumpEventQueue();

      final publisher = container.read(streamPublisherProvider.notifier);
      final sources = await publisher.getDesktopSources();
      expect(sources, hasLength(2));
      expect(sources.first.id, 'screen:0');
      expect(sources.last.id, 'window:42');

      final started = await container
          .read(sessionViewProvider.notifier)
          .startScreenShare(
            sourceId: 'window:42',
            sourceName: 'Code Editor',
            resolution: ScreenShareResolutionPreset.p720,
            frameRate: ScreenShareFrameRatePreset.fps60,
          );
      expect(started, isTrue);
      expect(core.startedShares, [
        (
          name: 'Code Editor',
          audio: false,
          bitrate: 5000,
          viewerLimit: defaultMaxStreamViewers,
        ),
      ]);

      events.add(
        const CoreEvent.screenSharePublished(streamId: 'pub-stream-1'),
      );
      await _pumpEventQueue();

      final pubState = container.read(streamPublisherProvider);
      expect(pubState.isActive, isTrue);
      expect(pubState.streamId, 'pub-stream-1');
      expect(pubState.sourceName, 'Code Editor');
      expect(pubState.resolution, ScreenShareResolutionPreset.p720);
      expect(pubState.frameRate, ScreenShareFrameRatePreset.fps60);

      // Simulate user clicking "Stop sharing" in the native OS banner.
      final videoTrack =
          bindings.displayStream.getVideoTracks().single
              as _FakeMediaStreamTrack;
      expect(videoTrack.onEnded, isNotNull);
      videoTrack.onEnded!();
      await _pumpEventQueue();

      expect(core.stopShareCalls, 1);
      expect(container.read(streamPublisherProvider).isActive, isFalse);
      expect(bindings.displayStream.disposed, isTrue);
      expect(videoTrack.isStopped, isTrue);
    });

    test('manages 1-to-N viewer PeerConnections with strict MID 0=video, MID 1=audio, MAINTAIN_RESOLUTION, VP8 priority, and max viewer cap', () async {
      final events = StreamController<CoreEvent>.broadcast();
      final core = _FakeCoreSession(events);
      final remoteGate = Completer<void>();
      final bindings = _FakePublisherWebRtcBindings(
        remoteDescriptionGate: remoteGate,
      );

      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          webRtcBindingsProvider.overrideWithValue(bindings),
        ],
      );
      addTearDown(() async {
        await events.close();
        container.dispose();
      });

      container.read(sessionViewProvider);
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 1, channelId: 5),
        ),
      );
      await _pumpEventQueue();

      await container
          .read(sessionViewProvider.notifier)
          .startScreenShare(
            sourceId: 'screen:0',
            sourceName: 'Entire Screen',
            resolution: ScreenShareResolutionPreset.p1080,
            frameRate: ScreenShareFrameRatePreset.fps30,
          );
      events.add(
        const CoreEvent.screenSharePublished(streamId: 'pub-stream-2'),
      );
      await _pumpEventQueue();

      // 1. Viewer 101 joins.
      events.add(
        const CoreEvent.streamViewerJoinRequested(
          streamId: 'pub-stream-2',
          viewerClid: 101,
        ),
      );
      await _pumpEventQueue();

      expect(bindings.createdPeers, hasLength(1));
      final peer101 = bindings.createdPeers.first;

      // Verify strict MID order: video added first (MID 0), audio SendOnly transceiver second (MID 1).
      expect(peer101.mediaSetupOrder, [
        'addTrack:video:mid=0',
        'addTransceiver:audio:mid=1:SendOnly',
        'createOffer',
        'setLocalDescription',
      ]);

      // flutter_webrtc's default SDP constraints add recvonly audio/video
      // sections; the TS6 client does not answer such a four-section offer.
      final offerConstraints = peer101.createOfferConstraints;
      expect(offerConstraints?['mandatory'], isEmpty);
      expect(offerConstraints?['optional'], isEmpty);

      // Verify video RtpSender parameters: default degradationPreference = MAINTAIN_FRAMERATE.
      final sender101 = peer101.sendersList.single;
      expect(
        sender101.updatedParameters?.degradationPreference,
        RTCDegradationPreference.MAINTAIN_FRAMERATE,
      );
      expect(
        sender101.updatedParameters?.encodings?.single.maxBitrate,
        8000 * 1000,
      );
      expect(sender101.updatedParameters?.encodings?.single.maxFramerate, 30);
      expect(
        sender101.updatedParameters?.encodings?.single.scaleResolutionDownBy,
        1.0,
      );

      // The offer is libwebrtc's own, sent unchanged; codec preferences already
      // kept it to VP8/H.264 so no rewriting is needed.
      expect(core.joinResponses, hasLength(1));
      final response101 = core.joinResponses.single;
      expect(response101.viewerClid, 101);
      expect(response101.accept, isTrue);
      expect(response101.offerSdp, _samplePublisherRawOfferSdp);
      expect(
        inspectSdpMediaLayout(response101.offerSdp).isTs6Compatible,
        isTrue,
      );

      // 2. Early ICE candidate from viewer 101 arrives before Answer setRemoteDescription completes.
      events.add(
        const CoreEvent.publisherSignalReceived(
          streamId: 'pub-stream-2',
          viewerClid: 101,
          signal: PublisherSignal.iceCandidate(
            sdp: 'candidate:viewer101 1 UDP 2122252543 192.0.2.10 50000 typ host',
            mid: '0',
            mLine: 0,
          ),
        ),
      );
      events.add(
        const CoreEvent.publisherSignalReceived(
          streamId: 'pub-stream-2',
          viewerClid: 101,
          signal: PublisherSignal.answer(sdp: _sampleViewerAnswerSdp),
        ),
      );
      await _pumpEventQueue();
      expect(peer101.addedCandidates, isEmpty);

      remoteGate.complete();
      await _pumpEventQueue();
      expect(peer101.remoteDescription?.type, 'answer');
      expect(peer101.remoteDescription?.sdp, _sampleViewerAnswerSdp);
      expect(peer101.addedCandidates, hasLength(1));
      expect(
        peer101.addedCandidates.single.candidate,
        'candidate:viewer101 1 UDP 2122252543 192.0.2.10 50000 typ host',
      );

      // 3. Add 4 more viewers (102, 103, 104, 105) -> reaches maxViewers (5).
      for (final clid in [102, 103, 104, 105]) {
        events.add(
          CoreEvent.streamViewerJoinRequested(
            streamId: 'pub-stream-2',
            viewerClid: clid,
          ),
        );
      }
      await _pumpEventQueue();

      expect(container.read(streamPublisherProvider).viewerCount, 5);
      expect(container.read(streamPublisherProvider).viewerIds, {
        101,
        102,
        103,
        104,
        105,
      });
      expect(bindings.createdPeers, hasLength(5));

      // 4. 6th viewer (106) requests to join -> rejected with accept: false!
      events.add(
        const CoreEvent.streamViewerJoinRequested(
          streamId: 'pub-stream-2',
          viewerClid: 106,
        ),
      );
      await _pumpEventQueue();

      expect(bindings.createdPeers, hasLength(5));
      expect(core.joinResponses.last, (
        viewerClid: 106,
        accept: false,
        offerSdp: '',
      ));

      // 5. Viewer 102 leaves and viewer 103 ICE fails -> only 102 & 103 are closed; 101, 104, 105 stay active.
      final peer102 = bindings.createdPeers[1];
      final peer103 = bindings.createdPeers[2];
      events.add(
        const CoreEvent.streamViewerLeft(
          streamId: 'pub-stream-2',
          viewerClid: 102,
        ),
      );
      peer103.onIceConnectionState?.call(
        RTCIceConnectionState.RTCIceConnectionStateFailed,
      );
      await _pumpEventQueue();

      expect(peer102.closed, isTrue);
      expect(peer103.closed, isTrue);
      expect(peer101.closed, isFalse);
      expect(container.read(streamPublisherProvider).viewerIds, {
        101,
        104,
        105,
      });

      // 6. Channel move stops screen share and disposes all remaining viewer peers and local stream.
      events.add(const CoreEvent.clientMoved(id: 1, channelId: 9));
      await _pumpEventQueue();

      expect(container.read(streamPublisherProvider).isActive, isFalse);
      expect(container.read(streamPublisherProvider).viewerCount, 0);
      for (final peer in bindings.createdPeers) {
        expect(peer.closed, isTrue);
        expect(peer.disposed, isTrue);
      }
      expect(bindings.displayStream.disposed, isTrue);
    });

    test('holds local ICE candidates until the viewer Answer is applied and swallows server error id=5636', () async {
      final events = StreamController<CoreEvent>.broadcast();
      final core = _FakeCoreSession(events)
        ..respondJoinRequestGate = Completer<void>();
      final bindings = _FakePublisherWebRtcBindings();

      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          webRtcBindingsProvider.overrideWithValue(bindings),
        ],
      );
      addTearDown(() async {
        await events.close();
        container.dispose();
      });

      container.read(sessionViewProvider);
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 1, channelId: 5),
        ),
      );
      await _pumpEventQueue();

      await container
          .read(sessionViewProvider.notifier)
          .startScreenShare(sourceId: 'screen:0', sourceName: 'Entire Screen');
      events.add(
        const CoreEvent.screenSharePublished(streamId: 'pub-stream-ice'),
      );
      await _pumpEventQueue();

      // Viewer 201 requests to join; respondStreamJoinRequest is gated.
      events.add(
        const CoreEvent.streamViewerJoinRequested(
          streamId: 'pub-stream-ice',
          viewerClid: 201,
        ),
      );
      await _pumpEventQueue();

      final peer = bindings.createdPeers.single;
      // Native WebRTC fires onIceCandidate immediately after setLocalDescription,
      // before respondStreamJoinRequest has finished on the server.
      peer.onIceCandidate?.call(
        RTCIceCandidate(
          'candidate:early-local 1 UDP 2122252543 198.51.100.8 50000 typ host',
          '0',
          0,
        ),
      );
      await _pumpEventQueue();

      // Must NOT be sent before the viewer's Answer establishes the remote description!
      expect(core.joinResponses, isEmpty);
      expect(core.sentPublisherCandidates, isEmpty);

      // Completing respondStreamJoinRequest sends the offer but still keeps the
      // candidate buffered: the viewer has no peer for it yet.
      core.respondJoinRequestGate!.complete();
      await _pumpEventQueue();

      expect(core.joinResponses, hasLength(1));
      expect(core.sentPublisherCandidates, isEmpty);

      // The Answer arrives -> buffered candidate flushes in order.
      events.add(
        const CoreEvent.publisherSignalReceived(
          streamId: 'pub-stream-ice',
          viewerClid: 201,
          signal: PublisherSignal.answer(sdp: _sampleViewerAnswerSdp),
        ),
      );
      await _pumpEventQueue();

      expect(core.sentPublisherCandidates, [
        (
          viewerClid: 201,
          sdp: 'candidate:early-local 1 UDP 2122252543 198.51.100.8 50000 typ host',
          mid: '0',
          mLine: 0,
        ),
      ]);

      // Late ICE candidate when server returns id=5636 ("You are not participating in this stream")
      // must be caught gracefully and never throw an unhandled exception.
      core.sendPublisherCandidateError = const CoreError.connection(
        message: 'TeamSpeak server error: You are not participating in this stream (id=5636)',
      );
      peer.onIceCandidate?.call(
        RTCIceCandidate(
          'candidate:late-local 1 UDP 2122252543 198.51.100.8 50001 typ host',
          '0',
          0,
        ),
      );
      await _pumpEventQueue();
    });

    test('passes raw Answer SDP to setRemoteDescription without normalization or audio injection and reapplies video sender parameters', () async {
      final events = StreamController<CoreEvent>.broadcast();
      final coreSession = _FakeCoreSession(events);
      final bindings = _FakePublisherWebRtcBindings();
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(coreSession),
          webRtcBindingsProvider.overrideWithValue(bindings),
        ],
      );
      addTearDown(() async {
        await events.close();
        container.dispose();
      });

      container.read(sessionViewProvider);
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 1, channelId: 5),
        ),
      );
      await _pumpEventQueue();

      // 1. Start sharing and become active
      await container
          .read(sessionViewProvider.notifier)
          .startScreenShare(
            sourceId: 'screen:0',
            sourceName: 'Entire Screen',
            resolution: ScreenShareResolutionPreset.p1080,
            frameRate: ScreenShareFrameRatePreset.fps30,
          );
      events.add(
        const CoreEvent.screenSharePublished(streamId: 'pub-stream-4'),
      );
      await _pumpEventQueue();

      // 2. Viewer 301 requests join
      events.add(
        const CoreEvent.streamViewerJoinRequested(
          streamId: 'pub-stream-4',
          viewerClid: 301,
        ),
      );
      await _pumpEventQueue();

      expect(coreSession.joinResponses, hasLength(1));
      final joinResponse = coreSession.joinResponses.single;
      expect(joinResponse.viewerClid, 301);
      expect(joinResponse.accept, isTrue);

      // The offer is libwebrtc's own, with the TS6 media layout (MID 0 video, MID 1 audio).
      expect(joinResponse.offerSdp, _samplePublisherRawOfferSdp);
      final layout = inspectSdpMediaLayout(joinResponse.offerSdp);
      expect(layout.isTs6Compatible, isTrue);
      expect(layout.videoMid, '0');
      expect(layout.audioMid, '1');

      final peer301 = bindings.createdPeers.single;

      // 3. Raw Answer SDP without m=audio and non-VP8 payload order
      const rawVideoOnlyAnswerSdp =
          'v=0\r\n'
          'o=- 300 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 102 103 96 97\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=recvonly\r\n'
          'a=rtpmap:102 H264/90000\r\n'
          'a=rtpmap:103 rtx/90000\r\n'
          'a=fmtp:103 apt=102\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=rtpmap:97 rtx/90000\r\n'
          'a=fmtp:97 apt=96\r\n';

      events.add(
        const CoreEvent.publisherSignalReceived(
          streamId: 'pub-stream-4',
          viewerClid: 301,
          signal: PublisherSignal.answer(sdp: rawVideoOnlyAnswerSdp),
        ),
      );
      await _pumpEventQueue();

      // Must match raw Answer SDP byte-for-byte; MUST NOT inject m=audio or reorder codecs
      expect(peer301.remoteDescription?.type, 'answer');
      expect(peer301.remoteDescription?.sdp, rawVideoOnlyAnswerSdp);
      expect(peer301.remoteDescription?.sdp?.contains('m=audio'), isFalse);

      // Verify video sender parameters were reapplied after negotiation
      final videoSender = peer301.sendersList.first;
      expect(
        videoSender.updatedParameters?.degradationPreference,
        RTCDegradationPreference.MAINTAIN_FRAMERATE,
      );
      expect(
        videoSender.updatedParameters?.encodings?.single.maxBitrate,
        8000 * 1000,
      );
      expect(videoSender.updatedParameters?.encodings?.single.maxFramerate, 30);
    });

    test('prunes an over-long offer, and sends exactly the SDP that was applied locally', () async {
      final events = StreamController<CoreEvent>.broadcast();
      final core = _FakeCoreSession(events);
      // A raw offer far over the command line limit: the controller must rewrite
      // it first, and when the rewrite is rejected it must send the raw offer it
      // actually applied instead of a description the viewer never saw.
      final oversized = StringBuffer(_samplePublisherRawOfferSdp);
      for (var pt = 200; pt < 700; pt++) {
        oversized.write('a=rtpmap:$pt VP9/90000\r\n');
      }
      final bindings = _FakePublisherWebRtcBindings(
        offerSdp: oversized.toString(),
      )..throwOnModifiedSetLocalDescription = true;

      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          webRtcBindingsProvider.overrideWithValue(bindings),
        ],
      );
      addTearDown(() async {
        await events.close();
        container.dispose();
      });

      container.read(sessionViewProvider);
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 1, channelId: 5),
        ),
      );
      await _pumpEventQueue();

      await container
          .read(sessionViewProvider.notifier)
          .startScreenShare(sourceId: 'screen:0', sourceName: 'Entire Screen');
      events.add(
        const CoreEvent.screenSharePublished(streamId: 'pub-stream-fallback'),
      );
      await _pumpEventQueue();

      events.add(
        const CoreEvent.streamViewerJoinRequested(
          streamId: 'pub-stream-fallback',
          viewerClid: 202,
        ),
      );
      await _pumpEventQueue();

      final peer202 = bindings.createdPeers.single;
      expect(core.joinResponses, hasLength(1));
      expect(core.joinResponses.single.accept, isTrue);
      // The viewer must receive the SDP that is actually applied locally; sending
      // the rejected pruned offer would make its Answer describe another session.
      expect(peer202.localDescription?.sdp, oversized.toString());
      expect(core.joinResponses.single.offerSdp, oversized.toString());
      expect(peer202.localDescription?.sdp, core.joinResponses.single.offerSdp);
    });

    test('applies the Answer before adding ICE candidates, keeps their order, and clears a stale failure on connect', () async {
      final events = StreamController<CoreEvent>.broadcast();
      final core = _FakeCoreSession(events);
      final bindings = _FakePublisherWebRtcBindings();
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          webRtcBindingsProvider.overrideWithValue(bindings),
        ],
      );
      addTearDown(() async {
        await events.close();
        container.dispose();
      });

      container.read(sessionViewProvider);
      events.add(
        const CoreEvent.state(
          state: CoreSessionState.connected(clientId: 1, channelId: 5),
        ),
      );
      await _pumpEventQueue();
      await container
          .read(sessionViewProvider.notifier)
          .startScreenShare(sourceId: 'screen:0', sourceName: 'Entire Screen');
      events.add(
        const CoreEvent.screenSharePublished(streamId: 'pub-stream-order'),
      );
      await _pumpEventQueue();
      events.add(
        const CoreEvent.streamViewerJoinRequested(
          streamId: 'pub-stream-order',
          viewerClid: 404,
        ),
      );
      await _pumpEventQueue();

      const firstCandidate =
          'candidate:1 1 udp 2122260223 192.168.1.10 51000 typ host';
      const secondCandidate =
          'candidate:2 1 udp 2122260223 192.168.1.10 51001 typ host';

      // The official client's candidates may arrive before its Answer.
      events.add(
        const CoreEvent.publisherSignalReceived(
          streamId: 'pub-stream-order',
          viewerClid: 404,
          signal: PublisherSignal.iceCandidate(
            sdp: firstCandidate,
            mid: '0',
            mLine: 0,
          ),
        ),
      );
      events.add(
        const CoreEvent.publisherSignalReceived(
          streamId: 'pub-stream-order',
          viewerClid: 404,
          signal: PublisherSignal.iceCandidate(
            sdp: secondCandidate,
            mid: '1',
            mLine: 1,
          ),
        ),
      );
      await _pumpEventQueue();

      final peer = bindings.createdPeers.single;
      expect(peer.addedCandidates, isEmpty, reason: 'Answer 尚未应用');

      events.add(
        const CoreEvent.publisherSignalReceived(
          streamId: 'pub-stream-order',
          viewerClid: 404,
          signal: PublisherSignal.answer(sdp: _sampleViewerAnswerSdp),
        ),
      );
      await _pumpEventQueue();

      expect(peer.remoteDescription?.sdp, _sampleViewerAnswerSdp);
      expect(peer.addedCandidates.map((candidate) => candidate.candidate), [
        firstCandidate,
        secondCandidate,
      ]);
      expect(
        peer.mediaSetupOrder.indexOf('setRemoteDescription'),
        lessThan(peer.mediaSetupOrder.indexOf('addCandidate:$firstCandidate')),
      );

      peer.onConnectionState?.call(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await _pumpEventQueue();

      final state = container.read(streamPublisherProvider);
      expect(state.viewerFailure, isNull);
      expect(state.viewerIds, contains(404));
    });

    test('reports an explicit failure and releases the viewer when the Answer never arrives', () {
      fakeAsync((async) {
        final events = StreamController<CoreEvent>.broadcast();
        final core = _FakeCoreSession(events);
        final bindings = _FakePublisherWebRtcBindings();
        final container = ProviderContainer(
          overrides: [
            coreSessionProvider.overrideWithValue(core),
            webRtcBindingsProvider.overrideWithValue(bindings),
          ],
        );
        addTearDown(() async {
          await events.close();
          container.dispose();
        });

        void pump() {
          for (var i = 0; i < 6; i++) {
            async.elapse(const Duration(milliseconds: 1));
          }
        }

        container.read(sessionViewProvider);
        events.add(
          const CoreEvent.state(
            state: CoreSessionState.connected(clientId: 1, channelId: 5),
          ),
        );
        pump();
        container
            .read(sessionViewProvider.notifier)
            .startScreenShare(
              sourceId: 'screen:0',
              sourceName: 'Entire Screen',
            );
        pump();
        events.add(
          const CoreEvent.screenSharePublished(streamId: 'pub-stream-timeout'),
        );
        pump();
        events.add(
          const CoreEvent.streamViewerJoinRequested(
            streamId: 'pub-stream-timeout',
            viewerClid: 505,
          ),
        );
        pump();

        expect(
          container.read(streamPublisherProvider).viewerIds,
          contains(505),
        );

        async.elapse(defaultStreamNegotiationTimeout);
        pump();

        final state = container.read(streamPublisherProvider);
        expect(state.viewerFailure?.viewerClid, 505);
        expect(
          state.viewerFailure?.reason,
          StreamViewerFailureReason.answerTimeout,
        );
        expect(state.viewerIds, isEmpty);
        expect(bindings.createdPeers.single.closed, isTrue);
        expect(bindings.createdPeers.single.disposed, isTrue);
        expect(core.kickedViewers, [505]);
      });
    });

    test('orders H264 codecs first by default and VP8 codecs first when configured', () async {
      for (final configured in [null, ScreenShareCodecPreference.vp8]) {
        final events = StreamController<CoreEvent>.broadcast();
        final core = _FakeCoreSession(events);
        final bindings = _FakePublisherWebRtcBindings();

        final container = ProviderContainer(
          overrides: [
            coreSessionProvider.overrideWithValue(core),
            webRtcBindingsProvider.overrideWithValue(bindings),
            if (configured != null)
              preferencesStoreProvider.overrideWithValue(
                PreferencesStore.inMemory(
                  preferences: SessionPreferences(
                    nickname: 'TestUser',
                    screenShareCodec: configured,
                  ),
                ),
              ),
          ],
        );

        container.read(sessionViewProvider);
        events.add(
          const CoreEvent.state(
            state: CoreSessionState.connected(clientId: 1, channelId: 5),
          ),
        );
        await _pumpEventQueue();

        await container
            .read(sessionViewProvider.notifier)
            .startScreenShare(
              sourceId: 'screen:0',
              sourceName: 'Entire Screen',
            );
        events.add(
          const CoreEvent.screenSharePublished(streamId: 'pub-stream-codec'),
        );
        await _pumpEventQueue();

        events.add(
          const CoreEvent.streamViewerJoinRequested(
            streamId: 'pub-stream-codec',
            viewerClid: 606,
          ),
        );
        await _pumpEventQueue();

        final videoTransceiver =
            bindings.createdPeers.single.transceiversList.first;
        final expectedFirst = configured == ScreenShareCodecPreference.vp8
            ? 'video/VP8'
            : 'video/H264';
        expect(videoTransceiver.preferredCodecs?.first.mimeType, expectedFirst);

        await events.close();
        container.dispose();
      }
    });
  });
}
