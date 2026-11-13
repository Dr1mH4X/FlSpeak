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

class _FakeWebRtcBindings extends WebRtcBindings {
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

/// 真实 libwebrtc（Chromium）生成的 2 条 m-line、约 5 KB Offer，含 VP8/VP9/AV1/H264
/// 与 RTX/red/ulpfec。用来验证 SDP 重写在真实载荷上仍自洽。
const _realLibwebrtcOfferSdp =
    'v=0\r\n'
    'o=- 8364204764808447283 2 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'a=group:BUNDLE 0 1\r\n'
    'a=extmap-allow-mixed\r\n'
    'a=msid-semantic: WMS 5fab3177-825a-4f8e-a970-ad92889d3546\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 96 97 102 103 104 107 108 109 114 115 116 117 39 40 45 46 98 99 100 101 118 119 120\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=rtcp:9 IN IP4 0.0.0.0\r\n'
    'a=ice-ufrag:HMHZ\r\n'
    'a=ice-pwd:VrAsNfLk/l06iEK3KQN2E1YO\r\n'
    'a=ice-options:trickle\r\n'
    'a=fingerprint:sha-256 6F:13:B0:DA:23:7F:CA:9C:D3:09:84:1D:64:68:F1:36:67:D3:E0:E1:B7:FB:42:1E:E1:20:04:B5:CB:A3:21:34\r\n'
    'a=setup:actpass\r\n'
    'a=mid:0\r\n'
    'a=extmap:1 urn:ietf:params:rtp-hdrext:toffset\r\n'
    'a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\n'
    'a=extmap:3 urn:3gpp:video-orientation\r\n'
    'a=extmap:4 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\n'
    'a=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\r\n'
    'a=extmap:6 http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\r\n'
    'a=extmap:7 http://www.webrtc.org/experiments/rtp-hdrext/video-timing\r\n'
    'a=extmap:8 http://www.webrtc.org/experiments/rtp-hdrext/color-space\r\n'
    'a=extmap:9 urn:ietf:params:rtp-hdrext:sdes:mid\r\n'
    'a=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\r\n'
    'a=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\r\n'
    'a=sendrecv\r\n'
    'a=msid:5fab3177-825a-4f8e-a970-ad92889d3546 1ebd1994-92bf-4fbd-9abc-082641e0fb6d\r\n'
    'a=rtcp-mux\r\n'
    'a=rtcp-rsize\r\n'
    'a=rtcp-xr:rcvr-rtt=all\r\n'
    'a=rtpmap:96 VP8/90000\r\n'
    'a=rtcp-fb:96 goog-remb\r\n'
    'a=rtcp-fb:96 transport-cc\r\n'
    'a=rtcp-fb:96 ccm fir\r\n'
    'a=rtcp-fb:96 nack\r\n'
    'a=rtcp-fb:96 nack pli\r\n'
    'a=rtpmap:97 rtx/90000\r\n'
    'a=fmtp:97 apt=96\r\n'
    'a=rtpmap:102 H264/90000\r\n'
    'a=rtcp-fb:102 goog-remb\r\n'
    'a=rtcp-fb:102 transport-cc\r\n'
    'a=rtcp-fb:102 ccm fir\r\n'
    'a=rtcp-fb:102 nack\r\n'
    'a=rtcp-fb:102 nack pli\r\n'
    'a=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f\r\n'
    'a=rtpmap:103 rtx/90000\r\n'
    'a=fmtp:103 apt=102\r\n'
    'a=rtpmap:104 H264/90000\r\n'
    'a=rtcp-fb:104 goog-remb\r\n'
    'a=rtcp-fb:104 transport-cc\r\n'
    'a=rtcp-fb:104 ccm fir\r\n'
    'a=rtcp-fb:104 nack\r\n'
    'a=rtcp-fb:104 nack pli\r\n'
    'a=fmtp:104 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f\r\n'
    'a=rtpmap:107 rtx/90000\r\n'
    'a=fmtp:107 apt=104\r\n'
    'a=rtpmap:108 H264/90000\r\n'
    'a=rtcp-fb:108 goog-remb\r\n'
    'a=rtcp-fb:108 transport-cc\r\n'
    'a=rtcp-fb:108 ccm fir\r\n'
    'a=rtcp-fb:108 nack\r\n'
    'a=rtcp-fb:108 nack pli\r\n'
    'a=fmtp:108 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\n'
    'a=rtpmap:109 rtx/90000\r\n'
    'a=fmtp:109 apt=108\r\n'
    'a=rtpmap:114 H264/90000\r\n'
    'a=rtcp-fb:114 goog-remb\r\n'
    'a=rtcp-fb:114 transport-cc\r\n'
    'a=rtcp-fb:114 ccm fir\r\n'
    'a=rtcp-fb:114 nack\r\n'
    'a=rtcp-fb:114 nack pli\r\n'
    'a=fmtp:114 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42e01f\r\n'
    'a=rtpmap:115 rtx/90000\r\n'
    'a=fmtp:115 apt=114\r\n'
    'a=rtpmap:116 H264/90000\r\n'
    'a=rtcp-fb:116 goog-remb\r\n'
    'a=rtcp-fb:116 transport-cc\r\n'
    'a=rtcp-fb:116 ccm fir\r\n'
    'a=rtcp-fb:116 nack\r\n'
    'a=rtcp-fb:116 nack pli\r\n'
    'a=fmtp:116 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f\r\n'
    'a=rtpmap:117 rtx/90000\r\n'
    'a=fmtp:117 apt=116\r\n'
    'a=rtpmap:39 H264/90000\r\n'
    'a=rtcp-fb:39 goog-remb\r\n'
    'a=rtcp-fb:39 transport-cc\r\n'
    'a=rtcp-fb:39 ccm fir\r\n'
    'a=rtcp-fb:39 nack\r\n'
    'a=rtcp-fb:39 nack pli\r\n'
    'a=fmtp:39 level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=4d001f\r\n'
    'a=rtpmap:40 rtx/90000\r\n'
    'a=fmtp:40 apt=39\r\n'
    'a=rtpmap:45 AV1/90000\r\n'
    'a=rtcp-fb:45 goog-remb\r\n'
    'a=rtcp-fb:45 transport-cc\r\n'
    'a=rtcp-fb:45 ccm fir\r\n'
    'a=rtcp-fb:45 nack\r\n'
    'a=rtcp-fb:45 nack pli\r\n'
    'a=fmtp:45 level-idx=5;profile=0;tier=0\r\n'
    'a=rtpmap:46 rtx/90000\r\n'
    'a=fmtp:46 apt=45\r\n'
    'a=rtpmap:98 VP9/90000\r\n'
    'a=rtcp-fb:98 goog-remb\r\n'
    'a=rtcp-fb:98 transport-cc\r\n'
    'a=rtcp-fb:98 ccm fir\r\n'
    'a=rtcp-fb:98 nack\r\n'
    'a=rtcp-fb:98 nack pli\r\n'
    'a=fmtp:98 profile-id=0\r\n'
    'a=rtpmap:99 rtx/90000\r\n'
    'a=fmtp:99 apt=98\r\n'
    'a=rtpmap:100 VP9/90000\r\n'
    'a=rtcp-fb:100 goog-remb\r\n'
    'a=rtcp-fb:100 transport-cc\r\n'
    'a=rtcp-fb:100 ccm fir\r\n'
    'a=rtcp-fb:100 nack\r\n'
    'a=rtcp-fb:100 nack pli\r\n'
    'a=fmtp:100 profile-id=2\r\n'
    'a=rtpmap:101 rtx/90000\r\n'
    'a=fmtp:101 apt=100\r\n'
    'a=rtpmap:118 red/90000\r\n'
    'a=rtpmap:119 rtx/90000\r\n'
    'a=fmtp:119 apt=118\r\n'
    'a=rtpmap:120 ulpfec/90000\r\n'
    'a=ssrc-group:FID 1531688491 1908866941\r\n'
    'a=ssrc:1531688491 cname:dwKVQolmiETMm27d\r\n'
    'a=ssrc:1531688491 msid:5fab3177-825a-4f8e-a970-ad92889d3546 1ebd1994-92bf-4fbd-9abc-082641e0fb6d\r\n'
    'a=ssrc:1908866941 cname:dwKVQolmiETMm27d\r\n'
    'a=ssrc:1908866941 msid:5fab3177-825a-4f8e-a970-ad92889d3546 1ebd1994-92bf-4fbd-9abc-082641e0fb6d\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=rtcp:9 IN IP4 0.0.0.0\r\n'
    'a=ice-ufrag:HMHZ\r\n'
    'a=ice-pwd:VrAsNfLk/l06iEK3KQN2E1YO\r\n'
    'a=ice-options:trickle\r\n'
    'a=fingerprint:sha-256 6F:13:B0:DA:23:7F:CA:9C:D3:09:84:1D:64:68:F1:36:67:D3:E0:E1:B7:FB:42:1E:E1:20:04:B5:CB:A3:21:34\r\n'
    'a=setup:actpass\r\n'
    'a=mid:1\r\n'
    'a=extmap:14 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\n'
    'a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\n'
    'a=extmap:4 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\r\n'
    'a=extmap:9 urn:ietf:params:rtp-hdrext:sdes:mid\r\n'
    'a=sendonly\r\n'
    'a=msid:- 79963b1e-8f8f-4046-ab5c-40d7b21d1464\r\n'
    'a=rtcp-mux\r\n'
    'a=rtcp-rsize\r\n'
    'a=rtcp-xr:rcvr-rtt=all\r\n'
    'a=rtpmap:111 opus/48000/2\r\n'
    'a=rtcp-fb:111 transport-cc\r\n'
    'a=fmtp:111 minptime=10;useinbandfec=1\r\n'
    'a=rtpmap:63 red/48000/2\r\n'
    'a=fmtp:63 111/111\r\n'
    'a=rtpmap:9 G722/8000\r\n'
    'a=rtpmap:0 PCMU/8000\r\n'
    'a=rtpmap:8 PCMA/8000\r\n'
    'a=rtpmap:13 CN/8000\r\n'
    'a=rtpmap:110 telephone-event/48000\r\n'
    'a=rtpmap:126 telephone-event/8000\r\n'
    'a=ssrc:1117638041 cname:dwKVQolmiETMm27d\r\n'
    'a=ssrc:1117638041 msid:- 79963b1e-8f8f-4046-ab5c-40d7b21d1464\r\n';

List<List<String>> _sdpSections(String sdp) {
  final sections = <List<String>>[];
  for (final line in sdp.split(RegExp(r'\r?\n'))) {
    if (line.startsWith('m=')) {
      sections.add(<String>[]);
    }
    if (sections.isNotEmpty) {
      sections.last.add(line);
    }
  }
  return sections;
}

/// 每个 m= 段里用到的 PT 都必须有 rtpmap；RTX 的 apt 必须指向仍保留的编码；
/// 属性行不能引用已被裁剪的 PT；a=mid 数量与 m= 段数量一致。
void _expectSelfConsistentSdp(String sdp) {
  final sections = _sdpSections(sdp);
  expect(sections, hasLength(2));
  expect(
    sdp.split(RegExp(r'\r?\n')).where((line) => line.startsWith('a=mid:')),
    hasLength(sections.length),
  );
  for (final section in sections) {
    final pts = section.first.trim().split(RegExp(r'\s+')).sublist(3).toSet();
    final rtpmapPts = <String>{};
    for (final line in section.skip(1)) {
      final rtpmap = RegExp(r'^a=rtpmap:(\d+)\s').firstMatch(line);
      if (rtpmap != null) {
        rtpmapPts.add(rtpmap.group(1)!);
      }
    }
    expect(
      rtpmapPts,
      containsAll(pts),
      reason: 'm= 段里的 PT 缺少 a=rtpmap: ${section.first}',
    );
    for (final line in section.skip(1)) {
      final attr = RegExp(r'^a=(rtpmap|rtcp-fb|fmtp):(\d+)\b').firstMatch(line);
      if (attr != null) {
        expect(pts, contains(attr.group(2)!), reason: '属性引用已裁剪的 PT: $line');
      }
      final apt = RegExp(r'^a=fmtp:(\d+)\s.*\bapt=(\d+)\b').firstMatch(line);
      if (apt != null) {
        expect(pts, contains(apt.group(1)!));
        expect(pts, contains(apt.group(2)!));
        expect(rtpmapPts, contains(apt.group(2)!));
      }
    }
  }
}

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
    test('negotiates TS6 viewer offer/answer with MID 0=video, MID 1=audio, H264 priority, and cached early ICE candidates', () async {
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
        'video/h264',
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
      // Answer is created with H264 first & m=audio preserved, and sent via FFI.
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
        contains('m=video 9 UDP/TLS/RTP/SAVPF 102 103 96 97\r\n'),
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

    test('preferVideoCodecOnTransceiver preserves RTX pairing and auxiliary recovery codecs', () async {
      final vp8 = RTCRtpCodecCapability(
        clockRate: 90000,
        mimeType: 'video/VP8',
      );
      final rtxVp8 = RTCRtpCodecCapability(
        clockRate: 90000,
        mimeType: 'video/rtx',
      );
      final h264 = RTCRtpCodecCapability(
        clockRate: 90000,
        mimeType: 'video/H264',
        sdpFmtpLine: 'profile-level-id=42e01f',
      );
      final rtxH264 = RTCRtpCodecCapability(
        clockRate: 90000,
        mimeType: 'video/rtx',
      );
      final red = RTCRtpCodecCapability(
        clockRate: 90000,
        mimeType: 'video/red',
      );
      final ulpfec = RTCRtpCodecCapability(
        clockRate: 90000,
        mimeType: 'video/ulpfec',
      );

      final capabilities = RTCRtpCapabilities(
        codecs: [h264, rtxH264, vp8, rtxVp8, red, ulpfec],
      );

      final transceiver = _FakeTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        midValue: '0',
        directionValue: TransceiverDirection.SendRecv,
      );

      await preferVideoCodecOnTransceiver(
        capabilities: capabilities,
        transceiver: transceiver,
        preferredMimeType: 'video/vp8',
      );

      expect(transceiver.preferredCodecs, [
        vp8,
        rtxVp8,
        red,
        ulpfec,
        h264,
        rtxH264,
      ]);
    });

    test('ensureAudioDirectionInSdp replaces existing direction or inserts when absent', () {
      const sdpWithInactive =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'a=mid:0\r\n'
          'a=sendonly\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=mid:1\r\n'
          'a=inactive\r\n'
          'a=rtpmap:111 opus/48000/2\r\n';

      final resultSendonly = ensureAudioDirectionInSdp(
        sdpWithInactive,
        'sendonly',
      );
      expect(resultSendonly, contains('m=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'));
      expect(resultSendonly, contains('a=mid:1\r\na=sendonly\r\n'));
      expect(resultSendonly, isNot(contains('a=inactive')));

      const sdpWithoutDirection =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'a=mid:0\r\n'
          'a=sendonly\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=mid:1\r\n'
          'a=rtpmap:111 opus/48000/2\r\n';

      final resultInserted = ensureAudioDirectionInSdp(
        sdpWithoutDirection,
        'sendonly',
      );
      expect(resultInserted, contains('a=mid:1\r\na=sendonly\r\n'));

      const sdpWithSendrecv =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=mid:1\r\n'
          'a=sendrecv\r\n'
          'a=rtpmap:111 opus/48000/2\r\n';

      final resultRecvonly = ensureAudioDirectionInSdp(
        sdpWithSendrecv,
        'recvonly',
      );
      expect(
        resultRecvonly,
        contains('m=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\na=sendrecv'),
      );
      expect(
        resultRecvonly,
        contains('m=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:1\r\na=recvonly'),
      );
    });

    test('normalizeSdpForTs6 converts a=inactive in m=audio to sendonly for publisher offers', () {
      const offerWithInactiveAudio =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 102 96\r\n'
          'a=mid:0\r\n'
          'a=sendonly\r\n'
          'a=rtpmap:102 H264/90000\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=mid:1\r\n'
          'a=inactive\r\n'
          'a=rtpmap:111 opus/48000/2\r\n';

      final normalized = normalizeSdpForTs6(
        offerWithInactiveAudio,
        preferredVideoCodec: 'VP8',
        fallbackAudioDirection: 'sendonly',
      );

      expect(normalized, contains('m=video 9 UDP/TLS/RTP/SAVPF 96 102\r\n'));
      expect(normalized, contains('a=mid:1\r\na=sendonly\r\n'));
      expect(normalized, isNot(contains('a=inactive')));
    });

    test('pruneSdpCodecsForTs6 prunes extraneous codecs and keeps target, fallback, RTX, and Opus', () {
      const sdpWithManyCodecs =
          'v=0\r\n'
          'o=- 123 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99 102 103 120 121\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:0\r\n'
          'a=sendonly\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          'a=rtcp-fb:96 nack\r\n'
          'a=rtpmap:97 rtx/90000\r\n'
          'a=fmtp:97 apt=96\r\n'
          'a=rtpmap:98 VP9/90000\r\n'
          'a=rtcp-fb:98 nack\r\n'
          'a=rtpmap:99 rtx/90000\r\n'
          'a=fmtp:99 apt=98\r\n'
          'a=rtpmap:102 H264/90000\r\n'
          'a=rtcp-fb:102 nack\r\n'
          'a=rtpmap:103 rtx/90000\r\n'
          'a=fmtp:103 apt=102\r\n'
          'a=rtpmap:120 AV1/90000\r\n'
          'a=rtpmap:121 rtx/90000\r\n'
          'a=fmtp:121 apt=120\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111 9 0 8 126\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=mid:1\r\n'
          'a=sendonly\r\n'
          'a=rtpmap:111 opus/48000/2\r\n'
          'a=rtcp-fb:111 transport-cc\r\n'
          'a=fmtp:111 minptime=10\r\n'
          'a=rtpmap:9 G722/8000\r\n'
          'a=rtpmap:0 PCMU/8000\r\n'
          'a=rtpmap:8 PCMA/8000\r\n'
          'a=rtpmap:126 telephone-event/8000\r\n';

      final pruned = pruneSdpCodecsForTs6(
        sdpWithManyCodecs,
        targetVideoCodec: 'VP8',
        fallbackVideoCodec: 'H264',
      );

      // Kept video: 96 (VP8), 97 (rtx), 102 (H264), 103 (rtx)
      expect(pruned, contains('m=video 9 UDP/TLS/RTP/SAVPF 96 97 102 103\r\n'));
      expect(pruned, contains('a=rtpmap:96 VP8/90000\r\n'));
      expect(pruned, contains('a=rtpmap:97 rtx/90000\r\n'));
      expect(pruned, contains('a=rtpmap:102 H264/90000\r\n'));
      expect(pruned, contains('a=rtpmap:103 rtx/90000\r\n'));

      // Discarded video: VP9 (98, 99), AV1 (120, 121)
      expect(pruned, isNot(contains('VP9')));
      expect(pruned, isNot(contains('AV1')));
      expect(pruned, isNot(contains('apt=98')));
      expect(pruned, isNot(contains('apt=120')));

      // Kept audio: 111 (opus)
      expect(pruned, contains('m=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'));
      expect(pruned, contains('a=rtpmap:111 opus/48000/2\r\n'));

      // Discarded audio: G722 (9), PCMU (0), PCMA (8), telephone-event (126)
      expect(pruned, isNot(contains('G722')));
      expect(pruned, isNot(contains('PCMU')));
      expect(pruned, isNot(contains('PCMA')));
      expect(pruned, isNot(contains('telephone-event')));
    });

    test(
      'rewrites a real libwebrtc offer into a self-consistent TS6 offer',
      () {
        const realOffer = _realLibwebrtcOfferSdp;
        expect(realOffer.length, greaterThan(5000));

        final normalized = normalizeSdpForTs6(
          realOffer,
          preferredVideoCodec: 'VP8',
          fallbackAudioDirection: 'sendonly',
        );

        _expectSelfConsistentSdp(normalized);
        // 裁剪确实发生，且保留了已协商编码需要的 RTX。
        expect(normalized.length, lessThan(realOffer.length));
        expect(normalized, contains('a=rtpmap:96 VP8/90000'));
        expect(normalized, contains('a=fmtp:97 apt=96'));
        expect(normalized, isNot(contains('VP9')));
        expect(normalized, isNot(contains('AV1')));

        final layout = inspectSdpMediaLayout(normalized);
        expect(layout.hasVideo, isTrue);
        expect(layout.hasAudio, isTrue);
        expect(layout.videoMid, '0');
        expect(layout.audioMid, '1');

        // 没有系统音频时 libwebrtc 会写 a=inactive；推流端必须给官方客户端一个可接受的
        // a=sendonly，且改完仍自洽。
        final withoutAudioTrack = realOffer.replaceAll(
          'a=sendonly',
          'a=inactive',
        );
        final publisherOffer = normalizeSdpForTs6(
          withoutAudioTrack,
          preferredVideoCodec: 'VP8',
          fallbackAudioDirection: 'sendonly',
        );
        _expectSelfConsistentSdp(publisherOffer);
        expect(_sdpSections(publisherOffer).last, contains('a=sendonly'));
        expect(
          _sdpSections(publisherOffer).last,
          isNot(contains('a=inactive')),
        );
      },
    );

    test('defaultStreamIceServers includes TeamSpeak official STUN and high-priority domestic candidates', () {
      final urls = (defaultStreamIceServers.first['urls'] as List)
          .cast<String>();
      expect(urls, contains('stun:turn.teamspeak.com:3478'));
      expect(urls, contains('stun:turn2.teamspeak.com:3478'));
      expect(urls, contains('stun:stun.miwifi.com:3478'));
      expect(urls, contains('stun:stun.chat.bilibili.com:3478'));
      expect(urls, contains('stun:stun.qq.com:3478'));
      expect(urls, contains('stun:stun.aliyun.com:3478'));
      expect(urls, contains('stun:stun.cloudflare.com:3478'));
    });
  });
}
