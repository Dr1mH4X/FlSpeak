import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'providers.dart';

/// Default STUN server configuration for TS6 screen-share viewer connections.
const List<Map<String, dynamic>> defaultStreamIceServers = [
  {
    'urls': ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478'],
  },
];

/// Default timeout for WebRTC offer/answer + ICE negotiation.
const Duration defaultStreamNegotiationTimeout = Duration(seconds: 15);

/// Reorders the `m=video` payload type list in [sdp] so `VP8` (and its
/// associated `rtx` payload types) appear first, while keeping `m=audio`
/// and all MID attributes intact for TS6 native client compatibility.
String preferVp8InSdp(String sdp) {
  if (sdp.isEmpty) return sdp;
  final lineSeparator = sdp.contains('\r\n') ? '\r\n' : '\n';
  final lines = sdp.split(RegExp(r'\r?\n'));

  var videoSectionStart = -1;
  var videoSectionEnd = lines.length;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (videoSectionStart == -1) {
      if (line.startsWith('m=video ')) {
        videoSectionStart = i;
      }
    } else if (line.startsWith('m=')) {
      videoSectionEnd = i;
      break;
    }
  }

  if (videoSectionStart == -1) {
    return sdp;
  }

  final mLineParts = lines[videoSectionStart].trim().split(RegExp(r'\s+'));
  if (mLineParts.length <= 4) {
    return sdp;
  }

  final headerPrefix = mLineParts.sublist(0, 3);
  final payloadTypes = mLineParts.sublist(3);

  final vp8Pts = <String>{};
  final rtxAptMap = <String, String>{};
  final rtpmapRegex = RegExp(
    r'^a=rtpmap:(\d+)\s+([^/\s]+)/',
    caseSensitive: false,
  );
  final fmtpAptRegex = RegExp(
    r'^a=fmtp:(\d+)\s+.*\bapt=(\d+)\b',
    caseSensitive: false,
  );

  for (var i = videoSectionStart + 1; i < videoSectionEnd; i++) {
    final line = lines[i].trim();
    final rtpmapMatch = rtpmapRegex.firstMatch(line);
    if (rtpmapMatch != null) {
      final pt = rtpmapMatch.group(1)!;
      final codec = rtpmapMatch.group(2)!.toUpperCase();
      if (codec == 'VP8') {
        vp8Pts.add(pt);
      }
      continue;
    }
    final fmtpMatch = fmtpAptRegex.firstMatch(line);
    if (fmtpMatch != null) {
      final rtxPt = fmtpMatch.group(1)!;
      final aptPt = fmtpMatch.group(2)!;
      rtxAptMap[rtxPt] = aptPt;
    }
  }

  if (vp8Pts.isEmpty) {
    return sdp;
  }

  final prioritizedPts = <String>{
    ...vp8Pts,
    for (final entry in rtxAptMap.entries)
      if (vp8Pts.contains(entry.value)) entry.key,
  };

  final preferredOrder = <String>[
    for (final pt in payloadTypes)
      if (prioritizedPts.contains(pt)) pt,
    for (final pt in payloadTypes)
      if (!prioritizedPts.contains(pt)) pt,
  ];

  lines[videoSectionStart] =
      '${headerPrefix.join(' ')} ${preferredOrder.join(' ')}';
  return lines.join(lineSeparator);
}

/// Inspects an SDP string to verify TS6 native compatibility invariants:
/// - Contains both `m=video` and `m=audio` sections.
/// - Video section precedes audio section (MID 0 = video, MID 1 = audio).
class SdpMediaLayout {
  const SdpMediaLayout({
    required this.hasVideo,
    required this.hasAudio,
    required this.videoMid,
    required this.audioMid,
    required this.videoIndex,
    required this.audioIndex,
  });

  final bool hasVideo;
  final bool hasAudio;
  final String? videoMid;
  final String? audioMid;
  final int videoIndex;
  final int audioIndex;

  bool get isTs6Compatible =>
      hasVideo &&
      hasAudio &&
      videoIndex >= 0 &&
      audioIndex > videoIndex &&
      (videoMid == null || videoMid == '0') &&
      (audioMid == null || audioMid == '1');
}

/// Parses the media section layout of [sdp].
SdpMediaLayout inspectSdpMediaLayout(String sdp) {
  final lines = sdp.split(RegExp(r'\r?\n'));
  var currentMedia = '';
  var sectionCounter = 0;
  var videoIndex = -1;
  var audioIndex = -1;
  String? videoMid;
  String? audioMid;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.startsWith('m=video ')) {
      currentMedia = 'video';
      if (videoIndex == -1) videoIndex = sectionCounter;
      sectionCounter++;
    } else if (line.startsWith('m=audio ')) {
      currentMedia = 'audio';
      if (audioIndex == -1) audioIndex = sectionCounter;
      sectionCounter++;
    } else if (line.startsWith('m=')) {
      currentMedia = 'other';
      sectionCounter++;
    } else if (line.startsWith('a=mid:')) {
      final mid = line.substring('a=mid:'.length).trim();
      if (currentMedia == 'video' && videoMid == null) {
        videoMid = mid;
      } else if (currentMedia == 'audio' && audioMid == null) {
        audioMid = mid;
      }
    }
  }

  return SdpMediaLayout(
    hasVideo: videoIndex != -1,
    hasAudio: audioIndex != -1,
    videoMid: videoMid,
    audioMid: audioMid,
    videoIndex: videoIndex,
    audioIndex: audioIndex,
  );
}

/// Normalizes an Offer or Answer SDP for TS6 native compatibility:
/// prioritizes `VP8` in `m=video` and preserves `m=audio` (appending a
/// minimal recvonly `m=audio` section with `a=mid:1` only if a malformed SDP
/// omitted it).
String normalizeSdpForTs6(String sdp) {
  if (sdp.isEmpty) return sdp;
  final vp8Prioritized = preferVp8InSdp(sdp);
  final layout = inspectSdpMediaLayout(vp8Prioritized);
  if (layout.hasAudio || !layout.hasVideo) {
    return vp8Prioritized;
  }
  final lineSeparator = vp8Prioritized.contains('\r\n') ? '\r\n' : '\n';
  final trimmed = vp8Prioritized.endsWith(lineSeparator)
      ? vp8Prioritized
      : '$vp8Prioritized$lineSeparator';
  final fallbackAudioSection = [
    'm=audio 9 UDP/TLS/RTP/SAVPF 111',
    'c=IN IP4 0.0.0.0',
    'a=rtcp:9 IN IP4 0.0.0.0',
    'a=mid:1',
    'a=recvonly',
    'a=rtcp-mux',
    'a=rtpmap:111 opus/48000/2',
  ].join(lineSeparator);
  return '$trimmed$fallbackAudioSection$lineSeparator';
}

/// Abstraction over `flutter_webrtc` factory functions for testability.
abstract class WebRtcBindings {
  Future<RTCPeerConnection> createPeer(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints,
  ]);

  RTCVideoRenderer createVideoRenderer();

  Future<MediaStream> createMediaStream(String label);

  Future<RTCRtpCapabilities?> getVideoReceiverCapabilities();

  Future<void> setTrackVolume(double volume, MediaStreamTrack track);
}

/// Default production bindings backed by `flutter_webrtc`.
class FlutterWebRtcBindings implements WebRtcBindings {
  const FlutterWebRtcBindings();

  @override
  Future<RTCPeerConnection> createPeer(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) {
    return createPeerConnection(configuration, constraints);
  }

  @override
  RTCVideoRenderer createVideoRenderer() {
    return RTCVideoRenderer();
  }

  @override
  Future<MediaStream> createMediaStream(String label) {
    return createLocalMediaStream(label);
  }

  @override
  Future<RTCRtpCapabilities?> getVideoReceiverCapabilities() async {
    try {
      return await getRtpReceiverCapabilities('video');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setTrackVolume(double volume, MediaStreamTrack track) async {
    try {
      await Helper.setVolume(volume, track);
    } catch (_) {
      // Ignore platform errors if audio track was already stopped.
    }
  }
}

final webRtcBindingsProvider = Provider<WebRtcBindings>((ref) {
  return const FlutterWebRtcBindings();
});

/// Reason why a screen share viewing session ended or failed.
enum StreamEndNotice { stopped, rejected, removed, negotiationFailed }

/// Immutable state for the screen-share viewer.
@immutable
class StreamViewerState {
  const StreamViewerState({
    this.streamId,
    this.sourceClientId,
    this.renderer,
    this.isConnecting = false,
    this.hasVideo = false,
    this.isMuted = false,
    this.isExpanded = false,
    this.endNotice,
  });

  final String? streamId;
  final int? sourceClientId;
  final RTCVideoRenderer? renderer;
  final bool isConnecting;
  final bool hasVideo;
  final bool isMuted;
  final bool isExpanded;
  final StreamEndNotice? endNotice;

  bool get isActive => streamId != null;

  StreamViewerState copyWith({
    String? streamId,
    bool clearStreamId = false,
    int? sourceClientId,
    bool clearSourceClientId = false,
    RTCVideoRenderer? renderer,
    bool clearRenderer = false,
    bool? isConnecting,
    bool? hasVideo,
    bool? isMuted,
    bool? isExpanded,
    StreamEndNotice? endNotice,
    bool clearEndNotice = false,
  }) {
    return StreamViewerState(
      streamId: clearStreamId ? null : (streamId ?? this.streamId),
      sourceClientId: clearSourceClientId
          ? null
          : (sourceClientId ?? this.sourceClientId),
      renderer: clearRenderer ? null : (renderer ?? this.renderer),
      isConnecting: isConnecting ?? this.isConnecting,
      hasVideo: hasVideo ?? this.hasVideo,
      isMuted: isMuted ?? this.isMuted,
      isExpanded: isExpanded ?? this.isExpanded,
      endNotice: clearEndNotice ? null : (endNotice ?? this.endNotice),
    );
  }
}

final streamViewerProvider =
    NotifierProvider<StreamViewerController, StreamViewerState>(
      StreamViewerController.new,
    );

/// Manages the lifecycle of a single TS6 screen-share viewer WebRTC session.
class StreamViewerController extends Notifier<StreamViewerState> {
  RTCPeerConnection? _peer;
  RTCVideoRenderer? _renderer;
  MediaStream? _fallbackStream;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  final List<MediaStreamTrack> _remoteAudioTracks = [];
  Timer? _negotiationTimer;
  bool _remoteDescriptionSet = false;
  int _generation = 0;

  @override
  StreamViewerState build() {
    ref.onDispose(() {
      unawaited(_disposeResources(updateState: false));
    });
    return const StreamViewerState();
  }

  /// Prepares the viewer state when the user clicks to watch a stream (`JoinStream`).
  Future<void> prepareWatch({
    required String streamId,
    required int sourceClientId,
  }) async {
    await _disposeResources();
    state = StreamViewerState(
      streamId: streamId,
      sourceClientId: sourceClientId,
      isConnecting: true,
      isMuted: state.isMuted,
      isExpanded: state.isExpanded,
    );
  }

  /// Synchronizes viewer state with `CoreEvent_Streams` updates.
  Future<void> syncStreams({
    required List<StreamView> streams,
    required String? watchingStreamId,
  }) async {
    final currentId = state.streamId;
    if (currentId == null) {
      if (watchingStreamId != null) {
        StreamView? target;
        for (final stream in streams) {
          if (stream.id == watchingStreamId) {
            target = stream;
            break;
          }
        }
        if (target != null) {
          state = state.copyWith(
            streamId: target.id,
            sourceClientId: target.clientId,
            isConnecting: _peer == null,
            clearEndNotice: true,
          );
        }
      }
      return;
    }

    final stillExists = streams.any((s) => s.id == currentId);
    if (!stillExists ||
        (watchingStreamId != null && watchingStreamId != currentId)) {
      await closeSession();
    }
  }

  /// Handles an incoming `CoreEvent_StreamOffer` from the publisher:
  /// - Creates `RTCPeerConnection` with STUN servers.
  /// - Adds `RecvOnly` video (MID 0) and `RecvOnly` audio (MID 1) transceivers.
  /// - Prioritizes `VP8` codec and preserves `m=audio`.
  /// - Sets remote description and flushes any cached early ICE candidates.
  /// - Creates SDP Answer, sets local description, and sends via FFI `sendStreamAnswer`.
  Future<void> handleOffer({
    required String streamId,
    required int sourceClientId,
    required String sdp,
  }) async {
    if (sdp.trim().isEmpty) return;

    await _disposeResources();
    final currentGeneration = ++_generation;

    final bindings = ref.read(webRtcBindingsProvider);
    final coreSession = ref.read(coreSessionProvider);

    final renderer = bindings.createVideoRenderer();
    _renderer = renderer;

    state = StreamViewerState(
      streamId: streamId,
      sourceClientId: sourceClientId,
      renderer: renderer,
      isConnecting: true,
      hasVideo: false,
      isMuted: state.isMuted,
      isExpanded: state.isExpanded,
    );

    try {
      await renderer.initialize();
      if (!_isCurrentGeneration(currentGeneration)) return;

      final peer = await bindings.createPeer({
        'iceServers': defaultStreamIceServers,
        'sdpSemantics': 'unified-plan',
      });
      _peer = peer;
      if (!_isCurrentGeneration(currentGeneration)) return;

      // TS6 native compatibility: MID 0 = video, MID 1 = audio.
      // Never omit or strip the audio transceiver even for video-only shares.
      final videoTransceiver = await peer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      if (!_isCurrentGeneration(currentGeneration)) return;

      await peer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      if (!_isCurrentGeneration(currentGeneration)) return;

      await _preferVp8OnTransceiver(bindings, videoTransceiver);
      if (!_isCurrentGeneration(currentGeneration)) return;

      peer.onIceCandidate = (candidate) {
        if (!_isCurrentGeneration(currentGeneration)) return;
        final candidateSdp = candidate.candidate;
        if (candidateSdp == null || candidateSdp.isEmpty) return;
        unawaited(
          coreSession.sendStreamIceCandidate(
            streamId: streamId,
            targetClid: sourceClientId,
            sdp: candidateSdp,
            mid: candidate.sdpMid,
            mLine: candidate.sdpMLineIndex,
          ),
        );
      };

      peer.onTrack = (event) {
        if (!_isCurrentGeneration(currentGeneration)) return;
        unawaited(_handleRemoteTrack(currentGeneration, event));
      };

      peer.onAddStream = (stream) {
        if (!_isCurrentGeneration(currentGeneration)) return;
        _attachStreamToRenderer(currentGeneration, stream);
      };

      peer.onConnectionState = (connectionState) {
        if (!_isCurrentGeneration(currentGeneration)) return;
        if (connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _clearNegotiationTimer();
        } else if (connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          unawaited(_failNegotiation(currentGeneration));
        }
      };

      peer.onIceConnectionState = (iceState) {
        if (!_isCurrentGeneration(currentGeneration)) return;
        if (iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _clearNegotiationTimer();
        } else if (iceState ==
            RTCIceConnectionState.RTCIceConnectionStateFailed) {
          unawaited(_failNegotiation(currentGeneration));
        }
      };

      _armNegotiationTimer(currentGeneration);

      final normalizedOfferSdp = normalizeSdpForTs6(sdp);
      await peer.setRemoteDescription(
        RTCSessionDescription(normalizedOfferSdp, 'offer'),
      );
      if (!_isCurrentGeneration(currentGeneration)) return;

      _remoteDescriptionSet = true;
      await _flushPendingRemoteCandidates(currentGeneration, peer);
      if (!_isCurrentGeneration(currentGeneration)) return;

      final rawAnswer = await peer.createAnswer();
      if (!_isCurrentGeneration(currentGeneration)) return;

      final answerSdp = normalizeSdpForTs6(rawAnswer.sdp ?? '');
      final answerDescription = RTCSessionDescription(
        answerSdp,
        rawAnswer.type ?? 'answer',
      );
      await peer.setLocalDescription(answerDescription);
      if (!_isCurrentGeneration(currentGeneration)) return;

      await coreSession.sendStreamAnswer(
        streamId: streamId,
        targetClid: sourceClientId,
        sdp: answerSdp,
      );
    } catch (_) {
      if (_isCurrentGeneration(currentGeneration)) {
        await _failNegotiation(currentGeneration);
      }
    }
  }

  /// Handles an incoming `CoreEvent_StreamIceCandidate` from the publisher.
  /// Caches candidates that arrive before `setRemoteDescription` completes.
  Future<void> handleRemoteIceCandidate({
    required String streamId,
    required int sourceClientId,
    required String sdp,
    String? mid,
    int? mLine,
  }) async {
    if (sdp.trim().isEmpty) return;
    if (state.streamId != null && state.streamId != streamId) return;
    if (state.sourceClientId != null &&
        state.sourceClientId != sourceClientId) {
      return;
    }

    final candidate = RTCIceCandidate(sdp, mid, mLine);
    final peer = _peer;
    if (peer == null || !_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }

    try {
      await peer.addCandidate(candidate);
    } catch (_) {
      // Stale or duplicate ICE candidates are harmless.
    }
  }

  /// Handles `CoreEvent_StreamEnded` by destroying the WebRTC session and
  /// optionally surfacing a status notice.
  Future<void> handleStreamEnded({
    required String streamId,
    required StreamEndReason reason,
  }) async {
    if (state.streamId != null && state.streamId != streamId) {
      return;
    }

    final notice = switch (reason) {
      StreamEndReason.sourceStopped => StreamEndNotice.stopped,
      StreamEndReason.rejected => StreamEndNotice.rejected,
      StreamEndReason.removed => StreamEndNotice.removed,
      StreamEndReason.sourceLeft ||
      StreamEndReason.sourceMoved ||
      StreamEndReason.selfMoved ||
      StreamEndReason.disconnected ||
      StreamEndReason.left => null,
    };

    await closeSession(endNotice: notice);
  }

  /// Toggles remote stream audio mute.
  Future<void> toggleMuted() async {
    await setMuted(!state.isMuted);
  }

  /// Sets remote stream audio mute state.
  Future<void> setMuted(bool muted) async {
    if (state.isMuted == muted) return;
    state = state.copyWith(isMuted: muted);
    final bindings = ref.read(webRtcBindingsProvider);
    final volume = muted ? 0.0 : 1.0;
    for (final track in _remoteAudioTracks) {
      track.enabled = !muted;
      await bindings.setTrackVolume(volume, track);
    }
  }

  /// Toggles whether the viewer stage is expanded.
  void toggleExpanded() {
    state = state.copyWith(isExpanded: !state.isExpanded);
  }

  /// Clears any transient stream end notice.
  void clearEndNotice() {
    if (state.endNotice == null) return;
    state = state.copyWith(clearEndNotice: true);
  }

  /// Destroys the active `RTCPeerConnection` and `RTCVideoRenderer` immediately.
  Future<void> closeSession({StreamEndNotice? endNotice}) async {
    final preserveMuted = state.isMuted;
    await _disposeResources();
    state = StreamViewerState(isMuted: preserveMuted, endNotice: endNotice);
  }

  bool _isCurrentGeneration(int generation) => _generation == generation;

  Future<void> _preferVp8OnTransceiver(
    WebRtcBindings bindings,
    RTCRtpTransceiver transceiver,
  ) async {
    final capabilities = await bindings.getVideoReceiverCapabilities();
    final codecs = capabilities?.codecs;
    if (codecs == null || codecs.isEmpty) return;

    final vp8Codecs = <RTCRtpCodecCapability>[];
    final otherCodecs = <RTCRtpCodecCapability>[];
    for (final codec in codecs) {
      final mime = codec.mimeType.toLowerCase();
      if (mime == 'video/vp8') {
        vp8Codecs.add(codec);
      } else {
        otherCodecs.add(codec);
      }
    }
    if (vp8Codecs.isEmpty) return;

    try {
      await transceiver.setCodecPreferences([...vp8Codecs, ...otherCodecs]);
    } catch (_) {
      // Ignore platforms that do not support setCodecPreferences; SDP
      // normalization (`preferVp8InSdp`) still reorders VP8 first.
    }
  }

  Future<void> _flushPendingRemoteCandidates(
    int generation,
    RTCPeerConnection peer,
  ) async {
    if (_pendingRemoteCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.of(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      if (!_isCurrentGeneration(generation)) return;
      try {
        await peer.addCandidate(candidate);
      } catch (_) {
        // Ignore obsolete ICE candidates.
      }
    }
  }

  Future<void> _handleRemoteTrack(int generation, RTCTrackEvent event) async {
    _clearNegotiationTimer();
    final track = event.track;
    if (track.kind == 'audio') {
      if (!_remoteAudioTracks.any((existing) => existing.id == track.id)) {
        _remoteAudioTracks.add(track);
      }
      final muted = state.isMuted;
      track.enabled = !muted;
      await ref
          .read(webRtcBindingsProvider)
          .setTrackVolume(muted ? 0.0 : 1.0, track);
      if (!_isCurrentGeneration(generation)) return;
    }

    if (event.streams.isNotEmpty) {
      final remoteStream = event.streams.first;
      for (final audioTrack in remoteStream.getAudioTracks()) {
        if (!_remoteAudioTracks.any(
          (existing) => existing.id == audioTrack.id,
        )) {
          _remoteAudioTracks.add(audioTrack);
        }
        final muted = state.isMuted;
        audioTrack.enabled = !muted;
        await ref
            .read(webRtcBindingsProvider)
            .setTrackVolume(muted ? 0.0 : 1.0, audioTrack);
        if (!_isCurrentGeneration(generation)) return;
      }
      _attachStreamToRenderer(generation, remoteStream);
      return;
    }

    // Fallback when remote peer sends tracks without an MSID stream container.
    var fallback = _fallbackStream;
    if (fallback == null) {
      fallback = await ref
          .read(webRtcBindingsProvider)
          .createMediaStream('flspeak-remote-${state.streamId ?? "stream"}');
      if (!_isCurrentGeneration(generation)) {
        await fallback.dispose();
        return;
      }
      _fallbackStream = fallback;
    }
    await fallback.addTrack(track, addToNative: true);
    if (!_isCurrentGeneration(generation)) return;
    _attachStreamToRenderer(generation, fallback);
  }

  void _attachStreamToRenderer(int generation, MediaStream stream) {
    if (!_isCurrentGeneration(generation)) return;
    final renderer = _renderer;
    if (renderer == null) return;
    _clearNegotiationTimer();
    if (renderer.srcObject?.id != stream.id) {
      renderer.srcObject = stream;
    }
    state = state.copyWith(
      isConnecting: false,
      hasVideo: true,
      clearEndNotice: true,
    );
  }

  void _armNegotiationTimer(int generation) {
    _clearNegotiationTimer();
    _negotiationTimer = Timer(defaultStreamNegotiationTimeout, () {
      if (!_isCurrentGeneration(generation)) return;
      unawaited(_failNegotiation(generation));
    });
  }

  void _clearNegotiationTimer() {
    _negotiationTimer?.cancel();
    _negotiationTimer = null;
  }

  Future<void> _failNegotiation(int generation) async {
    if (!_isCurrentGeneration(generation)) return;
    final activeStreamId = state.streamId;
    await closeSession(endNotice: StreamEndNotice.negotiationFailed);
    if (activeStreamId != null) {
      try {
        await ref
            .read(coreSessionProvider)
            .leaveStream(streamId: activeStreamId);
      } catch (_) {
        // Ignore FFI error if already disconnected.
      }
    }
  }

  Future<void> _disposeResources({bool updateState = true}) async {
    _generation++;
    _clearNegotiationTimer();
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();
    _remoteAudioTracks.clear();

    final peer = _peer;
    final renderer = _renderer;
    final fallbackStream = _fallbackStream;
    _peer = null;
    _renderer = null;
    _fallbackStream = null;

    // Synchronously detach the renderer from state before disposing it so
    // `RTCVideoView` unmounts immediately and never touches a disposed notifier.
    if (updateState &&
        ref.mounted &&
        (state.renderer != null || state.hasVideo || state.isConnecting)) {
      state = state.copyWith(
        clearRenderer: true,
        hasVideo: false,
        isConnecting: false,
      );
    }

    if (peer != null) {
      peer.onIceCandidate = null;
      peer.onTrack = null;
      peer.onAddStream = null;
      peer.onConnectionState = null;
      peer.onIceConnectionState = null;
    }

    if (renderer != null) {
      try {
        if (renderer.textureId != null && renderer.srcObject != null) {
          renderer.srcObject = null;
        }
      } catch (_) {
        // Ignore if renderer was not initialized.
      }
      try {
        await renderer.dispose();
      } catch (_) {
        // Ignore platform disposal errors.
      }
    }

    if (fallbackStream != null) {
      try {
        for (final track in fallbackStream.getTracks()) {
          await track.stop();
        }
        await fallbackStream.dispose();
      } catch (_) {
        // Ignore fallback stream disposal errors.
      }
    }

    if (peer != null) {
      try {
        await peer.close();
      } catch (_) {
        // Closing an already closed peer is harmless.
      }
      try {
        await peer.dispose();
      } catch (_) {
        // Ignore peer disposal errors.
      }
    }
  }
}
