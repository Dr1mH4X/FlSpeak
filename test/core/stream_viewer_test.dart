import 'dart:async';

import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/stream_viewer.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class _FakeCoreSession extends Fake implements CoreSession {
  _FakeCoreSession(this.eventsController);

  final StreamController<CoreEvent> eventsController;
  final joinedStreams = <({String streamId, int sourceClid})>[];
  final leftStreams = <String>[];
  final sentAnswers = <({String streamId, int targetClid, String sdp})>[];
  final sentIceCandidates =
      <
        ({String streamId, int targetClid, String sdp, String? mid, int? mLine})
      >[];

  @override
  Stream<CoreEvent> events() => eventsController.stream;

  @override
  Future<List<ServerProfileView>> listServers() async => const [];

  @override
  Future<void> joinStream({
    required String streamId,
    required int sourceClid,
  }) async {
    joinedStreams.add((streamId: streamId, sourceClid: sourceClid));
  }

  @override
  Future<void> leaveStream({required String streamId}) async {
    leftStreams.add(streamId);
  }

  @override
  Future<void> sendStreamAnswer({
    required String streamId,
    required int targetClid,
    required String sdp,
  }) async {
    sentAnswers.add((streamId: streamId, targetClid: targetClid, sdp: sdp));
  }

  @override
  Future<void> sendStreamIceCandidate({
    required String streamId,
    required int targetClid,
    required String sdp,
    String? mid,
    int? mLine,
  }) async {
    sentIceCandidates.add((
      streamId: streamId,
      targetClid: targetClid,
      sdp: sdp,
      mid: mid,
      mLine: mLine,
    ));
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
  final TransceiverDirection directionValue;
  List<RTCRtpCodecCapability>? preferredCodecs;

  @override
  String get mid => midValue;

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
  String get ownerTag => 'remote';

  @override
  List<MediaStreamTrack> getAudioTracks() => _audioTracks;

  @override
  List<MediaStreamTrack> getVideoTracks() => _videoTracks;

  @override
  List<MediaStreamTrack> getTracks() => [..._videoTracks, ..._audioTracks];

  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    if (track.kind == 'audio') {
      _audioTracks.add(track);
    } else {
      _videoTracks.add(track);
    }
  }

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

class _FakeRtpReceiver extends Fake implements RTCRtpReceiver {}

class _FakePeerConnection extends Fake implements RTCPeerConnection {
  _FakePeerConnection({
    required this.configuration,
    required this.answerSdp,
    this.remoteDescriptionGate,
  });

  final Map<String, dynamic> configuration;
  final String answerSdp;
  final Completer<void>? remoteDescriptionGate;

  final List<_FakeTransceiver> addedTransceivers = [];
  final List<String> callOrder = [];
  final List<RTCIceCandidate> addedCandidates = [];
  RTCSessionDescription? remoteDescription;
  RTCSessionDescription? localDescription;
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
  }) async {
    final transceiver = _FakeTransceiver(
      kind: kind ?? RTCRtpMediaType.RTCRtpMediaTypeVideo,
      midValue: '${addedTransceivers.length}',
      directionValue: init?.direction ?? TransceiverDirection.RecvOnly,
    );
    addedTransceivers.add(transceiver);
    return transceiver;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (remoteDescriptionGate != null) {
      await remoteDescriptionGate!.future;
    }
    remoteDescription = description;
    callOrder.add('setRemoteDescription');
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    addedCandidates.add(candidate);
    callOrder.add('addCandidate:${candidate.candidate}');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async {
    callOrder.add('createAnswer');
    return RTCSessionDescription(answerSdp, 'answer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    localDescription = description;
    callOrder.add('setLocalDescription');
  }

  @override
  Future<void> close() async {
    closed = true;
    callOrder.add('close');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    callOrder.add('dispose');
  }
}

class _FakeWebRtcBindings implements WebRtcBindings {
  _FakeWebRtcBindings({this.remoteDescriptionGate});

  final Completer<void>? remoteDescriptionGate;
  final List<_FakePeerConnection> createdPeers = [];
  final List<_FakeVideoRenderer> createdRenderers = [];
  final List<({double volume, String? trackId})> volumeUpdates = [];

  @override
  Future<RTCPeerConnection> createPeer(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) async {
    final peer = _FakePeerConnection(
      configuration: configuration,
      answerSdp: _sampleNonVp8FirstAnswerSdp,
      remoteDescriptionGate: remoteDescriptionGate,
    );
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
  Future<RTCRtpCapabilities?> getVideoReceiverCapabilities() async {
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
  Future<void> setTrackVolume(double volume, MediaStreamTrack track) async {
    volumeUpdates.add((volume: volume, trackId: track.id));
  }
}

const _sampleOfferSdp =
    'v=0\r\n'
    'o=- 1 2 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'a=group:BUNDLE 0 1\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 102 103 96 97\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=mid:0\r\n'
    'a=sendonly\r\n'
    'a=rtpmap:102 H264/90000\r\n'
    'a=rtpmap:103 rtx/90000\r\n'
    'a=fmtp:103 apt=102\r\n'
    'a=rtpmap:96 VP8/90000\r\n'
    'a=rtpmap:97 rtx/90000\r\n'
    'a=fmtp:97 apt=96\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=mid:1\r\n'
    'a=sendonly\r\n'
    'a=rtpmap:111 opus/48000/2\r\n';

const _sampleNonVp8FirstAnswerSdp =
    'v=0\r\n'
    'o=- 3 4 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'a=group:BUNDLE 0 1\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 102 103 96 97\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=mid:0\r\n'
    'a=recvonly\r\n'
    'a=rtpmap:102 H264/90000\r\n'
    'a=rtpmap:103 rtx/90000\r\n'
    'a=fmtp:103 apt=102\r\n'
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
  group('TS6 SDP compatibility helpers', () {
    test('preferVp8InSdp moves VP8 and its RTX payload types to the front while preserving m=audio', () {
      final result = preferVp8InSdp(_sampleOfferSdp);
      expect(result, contains('m=video 9 UDP/TLS/RTP/SAVPF 96 97 102 103\r\n'));
      final layout = inspectSdpMediaLayout(result);
      expect(layout.hasVideo, isTrue);
      expect(layout.hasAudio, isTrue);
      expect(layout.videoMid, '0');
      expect(layout.audioMid, '1');
      expect(layout.isTs6Compatible, isTrue);
    });

    test('normalizeSdpForTs6 appends a recvonly m=audio section if an SDP omitted audio', () {
      const videoOnlySdp =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 102 96\r\n'
          'a=mid:0\r\n'
          'a=rtpmap:102 H264/90000\r\n'
          'a=rtpmap:96 VP8/90000\r\n';
      final normalized = normalizeSdpForTs6(videoOnlySdp);
      expect(normalized, contains('m=video 9 UDP/TLS/RTP/SAVPF 96 102\r\n'));
      final layout = inspectSdpMediaLayout(normalized);
      expect(layout.hasVideo, isTrue);
      expect(layout.hasAudio, isTrue);
      expect(layout.videoMid, '0');
      expect(layout.audioMid, '1');
      expect(layout.isTs6Compatible, isTrue);
    });
  });

  group('StreamViewerController & SessionController integration', () {
    test('negotiates TS6 viewer offer/answer with MID 0=video, MID 1=audio, VP8 priority, and cached early ICE candidates', () async {
      final events = StreamController<CoreEvent>.broadcast();
      final core = _FakeCoreSession(events);
      final remoteGate = Completer<void>();
      final bindings = _FakeWebRtcBindings(remoteDescriptionGate: remoteGate);

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
          state: CoreSessionState.connected(clientId: 1, channelId: 10),
        ),
      );
      const stream = StreamView(
        id: 'stream-42',
        clientId: 7,
        name: 'Alice Screen',
        hasAudio: false,
      );
      events.add(const CoreEvent.streams(streams: [stream]));
      await _pumpEventQueue();

      expect(container.read(sessionViewProvider).streams, [stream]);

      // 1. User clicks watch -> triggers JoinStream.
      final joined = await container
          .read(sessionViewProvider.notifier)
          .watchStream(stream);
      expect(joined, isTrue);
      expect(core.joinedStreams, [(streamId: 'stream-42', sourceClid: 7)]);
      expect(container.read(sessionViewProvider).watchingStreamId, 'stream-42');
      expect(container.read(streamViewerProvider).isConnecting, isTrue);

      // 2. Receive StreamOffer -> creates RTCPeerConnection and starts setRemoteDescription.
      events.add(
        const CoreEvent.streamOffer(
          streamId: 'stream-42',
          sourceClientId: 7,
          sdp: _sampleOfferSdp,
        ),
      );
      await _pumpEventQueue();

      expect(bindings.createdPeers, hasLength(1));
      final peer = bindings.createdPeers.single;
      expect(peer.configuration['iceServers'], defaultStreamIceServers);

      // Verify TS6 constraints: MID 0 = video (RecvOnly), MID 1 = audio (RecvOnly)
      // even though stream.hasAudio is false!
      expect(peer.addedTransceivers, hasLength(2));
      expect(
        peer.addedTransceivers[0].kind,
        RTCRtpMediaType.RTCRtpMediaTypeVideo,
      );
      expect(peer.addedTransceivers[0].mid, '0');
      expect(
        peer.addedTransceivers[0].directionValue,
        TransceiverDirection.RecvOnly,
      );
      expect(
        peer.addedTransceivers[0].preferredCodecs?.first.mimeType.toLowerCase(),
        'video/vp8',
      );
      expect(
        peer.addedTransceivers[1].kind,
        RTCRtpMediaType.RTCRtpMediaTypeAudio,
      );
      expect(peer.addedTransceivers[1].mid, '1');
      expect(
        peer.addedTransceivers[1].directionValue,
        TransceiverDirection.RecvOnly,
      );

      // 3. Early remote ICE candidates arrive BEFORE setRemoteDescription completes.
      events.add(
        const CoreEvent.streamIceCandidate(
          streamId: 'stream-42',
          sourceClientId: 7,
          sdp: 'candidate:1 1 UDP 2122252543 192.0.2.1 50000 typ host',
          mid: '0',
          mLine: 0,
        ),
      );
      events.add(
        const CoreEvent.streamIceCandidate(
          streamId: 'stream-42',
          sourceClientId: 7,
          sdp: 'candidate:2 1 UDP 2122252543 192.0.2.1 50001 typ host',
          mid: '1',
          mLine: 1,
        ),
      );
      await _pumpEventQueue();
      expect(peer.addedCandidates, isEmpty);

      // 4. Complete setRemoteDescription -> cached candidates flush in order,
      // Answer is created with VP8 first & m=audio preserved, and sent via FFI.
      remoteGate.complete();
      await _pumpEventQueue();

      expect(peer.callOrder, [
        'setRemoteDescription',
        'addCandidate:candidate:1 1 UDP 2122252543 192.0.2.1 50000 typ host',
        'addCandidate:candidate:2 1 UDP 2122252543 192.0.2.1 50001 typ host',
        'createAnswer',
        'setLocalDescription',
      ]);
      expect(core.sentAnswers, hasLength(1));
      final sentAnswer = core.sentAnswers.single;
      expect(sentAnswer.streamId, 'stream-42');
      expect(sentAnswer.targetClid, 7);
      expect(
        sentAnswer.sdp,
        contains('m=video 9 UDP/TLS/RTP/SAVPF 96 97 102 103\r\n'),
      );
      expect(inspectSdpMediaLayout(sentAnswer.sdp).isTs6Compatible, isTrue);

      // 5. Local ICE candidate -> forwarded via FFI SendStreamIceCandidate.
      peer.onIceCandidate?.call(
        RTCIceCandidate(
          'candidate:local 1 UDP 2122252543 198.51.100.2 60000 typ host',
          '0',
          0,
        ),
      );
      await _pumpEventQueue();
      expect(core.sentIceCandidates, [
        (
          streamId: 'stream-42',
          targetClid: 7,
          sdp: 'candidate:local 1 UDP 2122252543 198.51.100.2 60000 typ host',
          mid: '0',
          mLine: 0,
        ),
      ]);

      // 6. Remote track arrives -> attaches to renderer & supports mute toggle.
      final audioTrack = _FakeMediaStreamTrack(
        trackId: 'audio-track-1',
        trackKind: 'audio',
      );
      final videoTrack = _FakeMediaStreamTrack(
        trackId: 'video-track-1',
        trackKind: 'video',
      );
      final remoteStream = _FakeMediaStream(
        'remote-ms-1',
        audioTracks: [audioTrack],
        videoTracks: [videoTrack],
      );
      peer.onTrack?.call(
        RTCTrackEvent(
          receiver: _FakeRtpReceiver(),
          streams: [remoteStream],
          track: videoTrack,
          transceiver: peer.addedTransceivers.first,
        ),
      );
      await _pumpEventQueue();

      final viewerState = container.read(streamViewerProvider);
      expect(viewerState.hasVideo, isTrue);
      expect(viewerState.isConnecting, isFalse);
      expect(bindings.createdRenderers.single.srcObject, same(remoteStream));

      await container.read(streamViewerProvider.notifier).toggleMuted();
      expect(container.read(streamViewerProvider).isMuted, isTrue);
      expect(audioTrack.enabled, isFalse);
      expect(bindings.volumeUpdates.last, (
        volume: 0.0,
        trackId: 'audio-track-1',
      ));

      // 7. User closes viewer -> destroys RTCPeerConnection and RTCVideoRenderer.
      final renderer = bindings.createdRenderers.single;
      await container.read(sessionViewProvider.notifier).leaveStream();
      expect(core.leftStreams, ['stream-42']);
      expect(container.read(streamViewerProvider).renderer, isNull);
      expect(container.read(streamViewerProvider).isActive, isFalse);
      expect(renderer.isDisposed, isTrue);
      expect(peer.closed, isTrue);
      expect(peer.disposed, isTrue);
    });

    test('destroys RTCPeerConnection and RTCVideoRenderer on StreamEnded and channel switch', () async {
      final events = StreamController<CoreEvent>.broadcast();
      final core = _FakeCoreSession(events);
      final bindings = _FakeWebRtcBindings();

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
          state: CoreSessionState.connected(clientId: 1, channelId: 10),
        ),
      );
      const stream = StreamView(
        id: 'stream-99',
        clientId: 8,
        name: 'Bob Screen',
        hasAudio: true,
      );
      events.add(const CoreEvent.streams(streams: [stream]));
      await _pumpEventQueue();

      await container.read(sessionViewProvider.notifier).watchStream(stream);
      events.add(
        const CoreEvent.streamOffer(
          streamId: 'stream-99',
          sourceClientId: 8,
          sdp: _sampleOfferSdp,
        ),
      );
      await _pumpEventQueue();

      final firstPeer = bindings.createdPeers.first;
      final firstRenderer = bindings.createdRenderers.first;
      expect(firstPeer.disposed, isFalse);
      expect(firstRenderer.isDisposed, isFalse);

      // StreamEnded destroys peer and renderer.
      events.add(
        const CoreEvent.streamEnded(
          streamId: 'stream-99',
          reason: StreamEndReason.sourceStopped,
        ),
      );
      await _pumpEventQueue();

      expect(firstPeer.closed, isTrue);
      expect(firstPeer.disposed, isTrue);
      expect(firstRenderer.isDisposed, isTrue);
      expect(container.read(streamViewerProvider).renderer, isNull);

      // Start watching again, then switch channels -> destroys peer and renderer.
      await container.read(sessionViewProvider.notifier).watchStream(stream);
      events.add(
        const CoreEvent.streamOffer(
          streamId: 'stream-99',
          sourceClientId: 8,
          sdp: _sampleOfferSdp,
        ),
      );
      await _pumpEventQueue();

      final secondPeer = bindings.createdPeers.last;
      final secondRenderer = bindings.createdRenderers.last;
      expect(secondPeer.disposed, isFalse);
      expect(secondRenderer.isDisposed, isFalse);

      events.add(const CoreEvent.clientMoved(id: 1, channelId: 20));
      await _pumpEventQueue();

      expect(secondPeer.closed, isTrue);
      expect(secondPeer.disposed, isTrue);
      expect(secondRenderer.isDisposed, isTrue);
      expect(container.read(streamViewerProvider).renderer, isNull);
    });
  });
}
