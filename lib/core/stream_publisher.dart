import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'logging/logger.dart';
import 'preferences.dart';
import 'providers.dart';
import 'stream_viewer.dart';

/// Lightweight, testable representation of a desktop screen or window source.
class DesktopSourceEntry extends DesktopCapturerSource {
  DesktopSourceEntry({
    required this.id,
    required this.name,
    required this.type,
    this.thumbnail,
    ThumbnailSize? thumbnailSize,
  }) : thumbnailSize = thumbnailSize ?? ThumbnailSize(320, 180);

  @override
  final String id;

  @override
  final String name;

  @override
  final SourceType type;

  @override
  final Uint8List? thumbnail;

  @override
  final ThumbnailSize thumbnailSize;
}

/// Why a viewer's screen-share negotiation ended without a connected peer.
enum _ViewerFailureReason {
  /// No Answer (or no usable Answer) arrived before `defaultStreamNegotiationTimeout`.
  answerTimeout,

  /// Applying the viewer's Answer or its ICE candidates failed.
  answerRejected,

  /// The peer connection reported `failed`/`closed` before media flowed.
  connectionFailed,
}

/// Immutable state for the screen-share publisher (`StreamPublisherController`).
@immutable
class StreamPublisherState {
  const StreamPublisherState({
    this.streamId,
    this.sourceId,
    this.sourceName,
    this.resolution = ScreenShareResolutionPreset.p720,
    this.frameRate = ScreenShareFrameRatePreset.fps30,
    this.hasAudio = false,
    this.isStarting = false,
    this.isSharing = false,
    this.isPreviewExpanded = false,
    this.viewerIds = const <int>{},
    this.renderer,
  });

  final String? streamId;
  final String? sourceId;
  final String? sourceName;
  final ScreenShareResolutionPreset resolution;
  final ScreenShareFrameRatePreset frameRate;
  final bool hasAudio;
  final bool isStarting;
  final bool isSharing;
  final bool isPreviewExpanded;
  final Set<int> viewerIds;
  final RTCVideoRenderer? renderer;

  bool get isActive => isSharing || isStarting;

  int get viewerCount => viewerIds.length;

  StreamPublisherState copyWith({
    String? streamId,
    bool clearStreamId = false,
    String? sourceId,
    bool clearSourceId = false,
    String? sourceName,
    bool clearSourceName = false,
    ScreenShareResolutionPreset? resolution,
    ScreenShareFrameRatePreset? frameRate,
    bool? hasAudio,
    bool? isStarting,
    bool? isSharing,
    bool? isPreviewExpanded,
    Set<int>? viewerIds,
    RTCVideoRenderer? renderer,
    bool clearRenderer = false,
  }) {
    return StreamPublisherState(
      streamId: clearStreamId ? null : (streamId ?? this.streamId),
      sourceId: clearSourceId ? null : (sourceId ?? this.sourceId),
      sourceName: clearSourceName ? null : (sourceName ?? this.sourceName),
      resolution: resolution ?? this.resolution,
      frameRate: frameRate ?? this.frameRate,
      hasAudio: hasAudio ?? this.hasAudio,
      isStarting: isStarting ?? this.isStarting,
      isSharing: isSharing ?? this.isSharing,
      isPreviewExpanded: isPreviewExpanded ?? this.isPreviewExpanded,
      viewerIds: viewerIds ?? this.viewerIds,
      renderer: clearRenderer ? null : (renderer ?? this.renderer),
    );
  }
}

final streamPublisherProvider =
    NotifierProvider<StreamPublisherController, StreamPublisherState>(
      StreamPublisherController.new,
    );

/// Synthetic source identifier used on Android where the system prompt owns source selection.
const String androidScreenShareSourceId = 'android-screen';

/// Computes the `RTCRtpEncoding.scaleResolutionDownBy` factor needed to fit a
/// captured desktop or mobile source of `[sourceWidth] x [sourceHeight]` within
/// [resolution], matching WebSpeak's sender scaling logic while aligning target
/// long/short edges for portrait mobile captures.
double computeScaleResolutionDownBy({
  required int sourceWidth,
  required int sourceHeight,
  required ScreenShareResolutionPreset resolution,
}) {
  if (sourceWidth <= 0 || sourceHeight <= 0) {
    return 1.0;
  }
  final portrait = sourceHeight > sourceWidth;
  final targetWidth = portrait ? resolution.height : resolution.width;
  final targetHeight = portrait ? resolution.width : resolution.height;
  final widthRatio = sourceWidth / targetWidth;
  final heightRatio = sourceHeight / targetHeight;
  final scale = widthRatio > heightRatio ? widthRatio : heightRatio;
  return scale > 1.01 ? scale : 1.0;
}

class _ViewerPeerSession {
  _ViewerPeerSession({required this.viewerClid, required this.peerGeneration});

  final int viewerClid;
  final int peerGeneration;
  RTCPeerConnection? peer;
  bool remoteDescriptionSet = false;
  bool failureReported = false;
  final List<RTCIceCandidate> pendingLocalCandidates = [];
  final List<RTCIceCandidate> pendingRemoteCandidates = [];

  /// Serializes Answer/ICE handling so a candidate can never be added before the
  /// Answer that established the remote description.
  Future<void> signalingTail = Future<void>.value();
  Timer? negotiationTimer;
}

/// Manages local desktop media capture and 1-to-N viewer `RTCPeerConnection`s
/// for TS6 screen sharing.
class StreamPublisherController extends Notifier<StreamPublisherState> {
  MediaStream? _localStream;
  RTCVideoRenderer? _previewRenderer;
  final Map<int, _ViewerPeerSession> _viewerSessions = {};
  int _generation = 0;
  int _peerGenerationCounter = 0;
  bool _stopping = false;
  bool _androidMediaProjectionUpgraded = false;
  Future<bool> Function(bool active)? _androidMediaProjectionHandler;

  /// Read-only view of active viewer `RTCPeerConnection`s keyed by `viewerClid`.
  Map<int, RTCPeerConnection> get activePeers => Map.unmodifiable({
    for (final entry in _viewerSessions.entries)
      if (entry.value.peer != null) entry.key: entry.value.peer!,
  });

  @override
  StreamPublisherState build() {
    ref.onDispose(() {
      unawaited(_disposeAllResources(updateState: false));
    });
    return const StreamPublisherState();
  }

  /// Enumerates available desktop screens and application windows.
  Future<List<DesktopCapturerSource>> getDesktopSources({
    List<SourceType> types = const [SourceType.Screen, SourceType.Window],
    ThumbnailSize? thumbnailSize,
  }) async {
    final bindings = ref.read(webRtcBindingsProvider);
    return bindings.getDesktopSources(
      types: types,
      thumbnailSize: thumbnailSize ?? ThumbnailSize(320, 180),
    );
  }

  /// Captures the selected desktop source via `getDisplayMedia`, binds the OS
  /// banner stop callback (`videoTrack.onEnded`), and registers the stream on
  /// the TS6 server via FFI `startScreenShare`.
  Future<bool> startScreenShare({
    required String sourceId,
    required String sourceName,
    ScreenShareResolutionPreset? resolution,
    ScreenShareFrameRatePreset? frameRate,
    bool audio = false,
    int? maxViewers,
    Future<bool> Function(bool active)? onAndroidMediaProjectionChanged,
  }) async {
    await _disposeAllResources();
    final currentGeneration = ++_generation;
    _stopping = false;

    final viewerLimit = maxViewers ?? defaultMaxStreamViewers();
    final prefs = ref.read(preferencesProvider);
    final selectedResolution = resolution ?? prefs.screenShareResolution;
    final selectedFrameRate = frameRate ?? prefs.screenShareFrameRate;
    final normalizedName = sourceName.trim().isEmpty
        ? 'Screen Share'
        : sourceName.trim();

    final bindings = ref.read(webRtcBindingsProvider);
    final coreSession = ref.read(coreSessionProvider);
    final isAndroidCapture = ref
        .read(androidSessionServiceProvider)
        .isSupported;
    final effectiveAudio = isAndroidCapture ? false : audio;

    state = StreamPublisherState(
      sourceId: sourceId,
      sourceName: normalizedName,
      resolution: selectedResolution,
      frameRate: selectedFrameRate,
      hasAudio: effectiveAudio,
      isStarting: true,
      isSharing: false,
    );

    try {
      if (isAndroidCapture) {
        final granted = await bindings.requestCapturePermission();
        if (!_isCurrentGeneration(currentGeneration)) return false;
        if (!granted) {
          await _disposeAllResources();
          return false;
        }

        final projectionHandler = onAndroidMediaProjectionChanged;
        final promoted =
            projectionHandler != null && await projectionHandler(true);
        if (!_isCurrentGeneration(currentGeneration)) {
          if (promoted) {
            await _invokeAndroidMediaProjectionDowngrade(projectionHandler);
          }
          return false;
        }
        if (!promoted) {
          throw StateError(
            'Failed to promote Android foreground service for media projection',
          );
        }
        _androidMediaProjectionUpgraded = true;
        _androidMediaProjectionHandler = projectionHandler;
      }

      final mediaConstraints = isAndroidCapture
          ? <String, dynamic>{
              'video': <String, dynamic>{'frameRate': selectedFrameRate.fps},
              'audio': false,
            }
          : <String, dynamic>{
              'video': <String, dynamic>{
                'deviceId': <String, dynamic>{'exact': sourceId},
                'mandatory': <String, dynamic>{
                  'frameRate': selectedFrameRate.fps,
                },
              },
              'audio': effectiveAudio,
            };

      final stream = await bindings.getDisplayMedia(mediaConstraints);
      if (!_isCurrentGeneration(currentGeneration)) {
        await _disposeMediaStream(stream);
        if (isAndroidCapture) {
          await _downgradeAndroidMediaProjection();
        }
        return false;
      }

      final videoTracks = stream.getVideoTracks();
      if (videoTracks.isEmpty) {
        await _disposeMediaStream(stream);
        await _disposeAllResources();
        return false;
      }

      _localStream = stream;
      final videoTrack = videoTracks.first;

      // Apply ideal capture constraints if the platform supports it.
      try {
        await videoTrack.applyConstraints(<String, dynamic>{
          'frameRate': selectedFrameRate.fps,
        });
      } catch (_) {
        // Not all desktop platforms implement applyConstraints after capture.
      }
      if (!_isCurrentGeneration(currentGeneration)) return false;

      // Automatically stop sharing when the user clicks "Stop sharing" in the
      // native OS screen-capture banner.
      videoTrack.onEnded = () {
        if (!_isCurrentGeneration(currentGeneration)) return;
        unawaited(stopScreenShare());
      };

      final renderer = bindings.createVideoRenderer();
      _previewRenderer = renderer;
      await renderer.initialize();
      if (!_isCurrentGeneration(currentGeneration)) return false;
      renderer.onResize = () {
        if (!_isCurrentGeneration(currentGeneration)) return;
        unawaited(_reapplyAllViewerVideoSenderParameters(currentGeneration));
      };
      renderer.srcObject = stream;

      final hasAudioTrack =
          effectiveAudio && stream.getAudioTracks().isNotEmpty;
      state = state.copyWith(
        hasAudio: hasAudioTrack,
        isStarting: true,
        isSharing: true,
        renderer: renderer,
      );

      await coreSession.startScreenShare(
        name: normalizedName,
        audio: hasAudioTrack,
        bitrate: selectedResolution.bitrateKbps,
        viewerLimit: viewerLimit,
      );
      if (!_isCurrentGeneration(currentGeneration)) return false;

      state = state.copyWith(isStarting: false, isSharing: true);
      return true;
    } catch (_) {
      if (_isCurrentGeneration(currentGeneration)) {
        await _disposeAllResources();
      }
      rethrow;
    }
  }

  /// Handles `CoreEvent_ScreenSharePublished` from the Rust session actor.
  void handlePublished({required String streamId}) {
    if (!state.isActive) return;
    state = state.copyWith(
      streamId: streamId,
      isStarting: false,
      isSharing: true,
    );
  }

  /// Handles `CoreEvent_ScreenShareStopped` from the Rust session actor.
  Future<void> handleStopped() async {
    await _disposeAllResources();
  }

  /// Stops screen sharing, closes all viewer `RTCPeerConnection`s, disposes the
  /// local capture stream, and notifies the server via FFI `stopScreenShare`.
  Future<void> stopScreenShare({bool notifyServer = true}) async {
    if (_stopping) return;
    final wasActive = state.isActive || _localStream != null;
    _stopping = true;
    try {
      await _disposeAllResources();
      if (notifyServer && wasActive) {
        try {
          await ref.read(coreSessionProvider).stopScreenShare();
        } catch (_) {
          // Ignore FFI errors if already disconnected or stopped.
        }
      }
    } finally {
      _stopping = false;
    }
  }

  /// Toggles whether the local preview video stage is expanded in the workspace.
  void togglePreviewExpanded() {
    if (!state.isActive) return;
    state = state.copyWith(isPreviewExpanded: !state.isPreviewExpanded);
  }

  /// Handles `CoreEvent_StreamViewerJoinRequested`:
  /// - Creates a dedicated `RTCPeerConnection` for `viewerClid`.
  /// - Strictly adds video first (`MID 0 = video`) and audio or `SendOnly`
  ///   audio transceiver second (`MID 1 = audio`) for TS6 compatibility.
  /// - Sets `RTCDegradationPreference` (default `MAINTAIN_RESOLUTION`) and
  ///   bitrate/framerate encoding parameters on the video `RTCRtpSender`.
  /// - Creates an Offer with VP8 preferred by default (or H.264 if configured),
  ///   calls `setLocalDescription`, and sends via FFI `respondStreamJoinRequest`.
  Future<void> handleViewerJoinRequested({
    required String streamId,
    required int viewerClid,
  }) async {
    final localStream = _localStream;
    if (!state.isActive || localStream == null) return;
    if (state.streamId != null && state.streamId != streamId) return;

    final videoTracks = localStream.getVideoTracks();
    if (videoTracks.isEmpty) return;

    final coreSession = ref.read(coreSessionProvider);
    final currentGeneration = _generation;

    logInfo(
      'Received join request for viewer $viewerClid (streamId=$streamId)',
      target: 'stream',
    );

    // If this viewer already had an existing session, clean it up before
    // re-negotiating so they don't consume two slots.
    if (_viewerSessions.containsKey(viewerClid)) {
      await _closeViewerSession(viewerClid);
      if (!_isCurrentGeneration(currentGeneration) ||
          !state.isActive ||
          _localStream == null) {
        return;
      }
    }

    final peerGeneration = ++_peerGenerationCounter;
    final viewerSession = _ViewerPeerSession(
      viewerClid: viewerClid,
      peerGeneration: peerGeneration,
    );
    _viewerSessions[viewerClid] = viewerSession;
    _syncViewerIds();

    final bindings = ref.read(webRtcBindingsProvider);
    final prefs = ref.read(preferencesProvider);
    final preferredCodec =
        prefs.screenShareCodec == ScreenShareCodecPreference.h264
        ? 'H264'
        : 'VP8';
    final preferredMime =
        prefs.screenShareCodec == ScreenShareCodecPreference.h264
        ? 'video/h264'
        : 'video/vp8';

    try {
      final peer = await bindings.createPeer({
        'iceServers': defaultStreamIceServers,
        'sdpSemantics': 'unified-plan',
      });
      viewerSession.peer = peer;
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerClid,
        peerGeneration,
      )) {
        await _safeDisposePeer(peer);
        return;
      }

      // 1. Strict MID order: add video track FIRST so MID 0 is video.
      final videoTrack = videoTracks.first;
      final videoSender = await peer.addTrack(videoTrack, localStream);
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerClid,
        peerGeneration,
      )) {
        return;
      }

      // 2. Add audio track or SendOnly audio transceiver SECOND so MID 1 is audio.
      // Never omit m=audio or TS6 official clients will reject the Offer.
      final audioTracks = localStream.getAudioTracks();
      if (state.hasAudio && audioTracks.isNotEmpty) {
        await peer.addTrack(audioTracks.first, localStream);
      } else {
        await peer.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly),
        );
      }
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerClid,
        peerGeneration,
      )) {
        return;
      }

      // Configure transceiver directions and preferred video codec.
      await _configurePublisherTransceivers(
        bindings: bindings,
        peer: peer,
        preferredMimeType: preferredMime,
      );
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerClid,
        peerGeneration,
      )) {
        return;
      }

      // Configure video RtpSender degradationPreference & encoding limits.
      await _configureVideoSenderParameters(
        videoSender: videoSender,
        resolution: state.resolution,
        frameRate: state.frameRate,
        degradationPreference: prefs.screenShareDegradation,
      );
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerClid,
        peerGeneration,
      )) {
        return;
      }

      peer.onIceCandidate = (candidate) {
        if (!_isViewerSessionValid(
          currentGeneration,
          viewerClid,
          peerGeneration,
        )) {
          return;
        }
        final candidateSdp = candidate.candidate;
        if (candidateSdp == null || candidateSdp.isEmpty) return;
        // Trickle candidates only after the viewer's Answer established the remote
        // description; the official client otherwise receives a burst of signals
        // before it has a peer to apply them to.
        if (!viewerSession.remoteDescriptionSet) {
          viewerSession.pendingLocalCandidates.add(candidate);
          return;
        }
        unawaited(
          _sendLocalViewerCandidate(
            currentGeneration: currentGeneration,
            viewerSession: viewerSession,
            candidate: candidate,
          ),
        );
      };

      peer.onConnectionState = (connectionState) {
        if (!_isViewerSessionValid(
          currentGeneration,
          viewerClid,
          peerGeneration,
        )) {
          return;
        }
        if (kDebugMode) {
          logDebug(
            'viewer $viewerClid connection state: $connectionState',
            target: 'stream',
          );
        }
        if (connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _clearViewerNegotiationTimer(viewerSession);
        } else if (connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          unawaited(
            _failViewerSession(
              viewerClid,
              reason: _ViewerFailureReason.connectionFailed,
            ),
          );
        }
      };

      peer.onIceConnectionState = (iceState) {
        if (!_isViewerSessionValid(
          currentGeneration,
          viewerClid,
          peerGeneration,
        )) {
          return;
        }
        if (kDebugMode) {
          logDebug('viewer $viewerClid ICE state: $iceState', target: 'stream');
        }
        if (iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _clearViewerNegotiationTimer(viewerSession);
        } else if (iceState ==
                RTCIceConnectionState.RTCIceConnectionStateFailed ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          unawaited(
            _failViewerSession(
              viewerClid,
              reason: _ViewerFailureReason.connectionFailed,
            ),
          );
        }
      };

      _armViewerNegotiationTimer(
        currentGeneration: currentGeneration,
        viewerSession: viewerSession,
      );

      // Never ask libwebrtc to "receive" audio/video implicitly: flutter_webrtc's
      // default SDP constraints add a recvonly audio and a recvonly video section,
      // so the offer would carry four m-lines. The TS6 client expects exactly the
      // two transceivers the publisher created (video, then audio) and does not
      // answer the four-section offer.
      final rawOffer = await peer.createOffer(<String, dynamic>{
        'mandatory': <String, dynamic>{},
        'optional': <dynamic>[],
      });
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerClid,
        peerGeneration,
      )) {
        return;
      }

      final rawSdp = rawOffer.sdp ?? '';
      // Both known-working TS6 implementations hand libwebrtc's own offer to the
      // viewer unchanged and only narrow codecs through `setCodecPreferences`.
      // Rewriting the SDP is a last resort for the server's command-line limit.
      var appliedSdp = streamOfferFitsCommand(sdp: rawSdp)
          ? rawSdp
          : normalizeSdpForTs6(
              rawSdp,
              preferredVideoCodec: preferredCodec,
              fallbackAudioDirection: 'sendonly',
            );
      try {
        await peer.setLocalDescription(
          RTCSessionDescription(appliedSdp, rawOffer.type ?? 'offer'),
        );
      } catch (e) {
        logWarn(
          'setLocalDescription with the rewritten offer failed, falling back to raw offer',
          target: 'stream',
          error: e,
        );
        await peer.setLocalDescription(rawOffer);
        appliedSdp = rawSdp;
      }
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerClid,
        peerGeneration,
      )) {
        return;
      }

      logInfo(
        'Sending respondjoinstreamrequest for viewer $viewerClid '
        '(offer_sdp_len=${appliedSdp.length}, raw_len=${rawSdp.length})',
        target: 'stream',
      );

      await coreSession.respondStreamJoinRequest(
        viewerClid: viewerClid,
        accept: true,
        offerSdp: appliedSdp,
      );
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerClid,
        peerGeneration,
      )) {
        return;
      }
    } catch (e, st) {
      logError(
        'Error negotiating stream with viewer $viewerClid',
        target: 'stream',
        error: e,
        stackTrace: st,
      );
      if (_isViewerSessionValid(
        currentGeneration,
        viewerClid,
        peerGeneration,
      )) {
        await _failViewerSession(
          viewerClid,
          reason: _ViewerFailureReason.answerRejected,
        );
      }
    }
  }

  /// Handles `CoreEvent_PublisherSignalReceived` (viewer Answer or ICE candidate).
  Future<void> handlePublisherSignal({
    required String streamId,
    required int viewerClid,
    required PublisherSignal signal,
  }) async {
    if (!state.isActive) return;
    if (state.streamId != null && state.streamId != streamId) return;

    final viewerSession = _viewerSessions[viewerClid];
    if (viewerSession == null) return;

    // Signals arrive from the actor as separate unawaited calls. Chain them per
    // viewer so the Answer always establishes the remote description before its
    // ICE candidates are added, regardless of event ordering.
    final previous = viewerSession.signalingTail;
    final done = Completer<void>();
    viewerSession.signalingTail = done.future;
    try {
      await previous;
      if (!_isViewerSessionValid(
        _generation,
        viewerClid,
        viewerSession.peerGeneration,
      )) {
        return;
      }
      try {
        await _applyPublisherSignal(
          viewerSession: viewerSession,
          signal: signal,
        );
      } catch (e, st) {
        // Signaling is delivered fire-and-forget; never let one bad payload
        // surface as an unhandled async error.
        logWarn(
          'Failed to apply signal for viewer $viewerClid',
          target: 'stream',
          error: e,
          stackTrace: st,
        );
      }
    } finally {
      done.complete();
    }
  }

  Future<void> _applyPublisherSignal({
    required _ViewerPeerSession viewerSession,
    required PublisherSignal signal,
  }) async {
    final viewerClid = viewerSession.viewerClid;
    final currentGeneration = _generation;
    final peerGeneration = viewerSession.peerGeneration;

    switch (signal) {
      case PublisherSignal_Answer(:final sdp):
        if (sdp.trim().isEmpty) {
          logWarn(
            'Ignoring empty Answer for viewer $viewerClid',
            target: 'stream',
          );
          return;
        }
        if (viewerSession.remoteDescriptionSet) {
          logWarn(
            'Ignoring duplicate Answer for viewer $viewerClid',
            target: 'stream',
          );
          return;
        }
        final peer = viewerSession.peer;
        if (peer == null) return;
        logInfo(
          'Received Answer for viewer $viewerClid (sdp_len=${sdp.length})',
          target: 'stream',
        );
        try {
          // Pass the answer SDP directly without normalization; normalizing or
          // altering an answer SDP violates RFC 3264 / JSEP and corrupts payload
          // type mappings.
          await peer.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
          if (!_isViewerSessionValid(
            currentGeneration,
            viewerClid,
            peerGeneration,
          )) {
            return;
          }
          viewerSession.remoteDescriptionSet = true;
          await _flushPendingViewerCandidates(
            currentGeneration: currentGeneration,
            viewerSession: viewerSession,
          );
          if (!_isViewerSessionValid(
            currentGeneration,
            viewerClid,
            peerGeneration,
          )) {
            return;
          }
          // Safely reapply video sender parameters after answer negotiation.
          await _reapplyViewerVideoSenderParameters(
            generation: currentGeneration,
            viewerSession: viewerSession,
          );
          if (!_isViewerSessionValid(
            currentGeneration,
            viewerClid,
            peerGeneration,
          )) {
            return;
          }
          // Flush local candidates asynchronously so slow server command round-trips
          // do not block incoming remote ICE candidates on `signalingTail`.
          unawaited(
            _flushPendingLocalViewerCandidates(
              currentGeneration: currentGeneration,
              viewerSession: viewerSession,
            ),
          );
        } catch (e, st) {
          logError(
            'Failed to set remote answer for viewer $viewerClid',
            target: 'stream',
            error: e,
            stackTrace: st,
          );
          if (_isViewerSessionValid(
            currentGeneration,
            viewerClid,
            peerGeneration,
          )) {
            await _failViewerSession(
              viewerClid,
              reason: _ViewerFailureReason.answerRejected,
            );
          }
        }
      case PublisherSignal_IceCandidate(:final sdp, :final mid, :final mLine):
        if (sdp.trim().isEmpty) return;
        logInfo(
          'Received iceCandidate for viewer $viewerClid '
          '(mid=${mid ?? '-'}, mLine=${mLine ?? '-'})',
          target: 'stream',
        );
        final candidate = RTCIceCandidate(sdp, mid, mLine);
        final peer = viewerSession.peer;
        if (peer == null || !viewerSession.remoteDescriptionSet) {
          viewerSession.pendingRemoteCandidates.add(candidate);
          return;
        }
        try {
          await peer.addCandidate(candidate);
        } catch (e) {
          logWarn(
            'Failed to apply remote iceCandidate for viewer $viewerClid',
            target: 'stream',
            error: e,
          );
        }
    }
  }

  /// Handles `CoreEvent_StreamViewerLeft` by closing only that viewer's peer.
  Future<void> handleViewerLeft({
    required String streamId,
    required int viewerClid,
  }) async {
    if (state.streamId != null && state.streamId != streamId) return;
    await _closeViewerSession(viewerClid);
  }

  bool _isCurrentGeneration(int generation) => _generation == generation;

  bool _isViewerSessionValid(
    int generation,
    int viewerClid,
    int peerGeneration,
  ) {
    if (_generation != generation) return false;
    final current = _viewerSessions[viewerClid];
    return current != null && current.peerGeneration == peerGeneration;
  }

  Future<void> _configurePublisherTransceivers({
    required WebRtcBindings bindings,
    required RTCPeerConnection peer,
    required String preferredMimeType,
  }) async {
    List<RTCRtpTransceiver> transceivers;
    try {
      transceivers = await peer.getTransceivers();
    } catch (_) {
      return;
    }
    if (transceivers.isEmpty) return;

    final capabilities = await bindings.getVideoSenderCapabilities();
    for (var i = 0; i < transceivers.length; i++) {
      final transceiver = transceivers[i];
      try {
        await transceiver.setDirection(TransceiverDirection.SendOnly);
      } catch (_) {}
      // Video transceiver is always added first (index 0 / MID 0).
      if (i == 0) {
        await _preferPrimaryVideoCodecs(
          capabilities: capabilities,
          transceiver: transceiver,
          preferredMimeType: preferredMimeType,
        );
      }
    }
  }

  /// Restricts the publisher's offer to H.264 and VP8 with the configured codec
  /// ordered first. libwebrtc then writes the offer itself, so no SDP rewriting
  /// is needed to stay inside the command line limit.
  Future<void> _preferPrimaryVideoCodecs({
    required RTCRtpCapabilities? capabilities,
    required RTCRtpTransceiver transceiver,
    required String preferredMimeType,
  }) async {
    await preferVideoCodecOnTransceiver(
      capabilities: capabilities,
      transceiver: transceiver,
      preferredMimeType: preferredMimeType,
      onError: (e) =>
          logWarn('setCodecPreferences failed', target: 'stream', error: e),
    );
  }

  Future<void> _reapplyAllViewerVideoSenderParameters(int generation) async {
    if (!_isCurrentGeneration(generation) || !state.isActive) return;
    final sessions = _viewerSessions.values.toList(growable: false);
    if (sessions.isEmpty) return;
    final degradationPreference = ref
        .read(preferencesProvider)
        .screenShareDegradation;
    for (final viewerSession in sessions) {
      await _reapplyViewerVideoSenderParameters(
        generation: generation,
        viewerSession: viewerSession,
        degradationPreference: degradationPreference,
      );
    }
  }

  Future<void> _reapplyViewerVideoSenderParameters({
    required int generation,
    required _ViewerPeerSession viewerSession,
    ScreenShareDegradationPreference? degradationPreference,
  }) async {
    if (!_isViewerSessionValid(
      generation,
      viewerSession.viewerClid,
      viewerSession.peerGeneration,
    )) {
      return;
    }
    final peer = viewerSession.peer;
    if (peer == null) return;
    try {
      final senders = await peer.getSenders();
      final videoSender = senders
          .where((s) => s.track?.kind == 'video')
          .firstOrNull;
      if (videoSender != null &&
          _isViewerSessionValid(
            generation,
            viewerSession.viewerClid,
            viewerSession.peerGeneration,
          )) {
        await _configureVideoSenderParameters(
          videoSender: videoSender,
          resolution: state.resolution,
          frameRate: state.frameRate,
          degradationPreference:
              degradationPreference ??
              ref.read(preferencesProvider).screenShareDegradation,
        );
      }
    } catch (_) {
      // Updating sender parameters is best-effort and must never trigger
      // viewer session teardown.
    }
  }

  Future<void> _configureVideoSenderParameters({
    required RTCRtpSender videoSender,
    required ScreenShareResolutionPreset resolution,
    required ScreenShareFrameRatePreset frameRate,
    required ScreenShareDegradationPreference degradationPreference,
  }) async {
    try {
      final sourceWidth = _previewRenderer?.videoWidth ?? 0;
      final sourceHeight = _previewRenderer?.videoHeight ?? 0;
      final scaleResolutionDownBy = computeScaleResolutionDownBy(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        resolution: resolution,
      );

      final params = videoSender.parameters;
      params.degradationPreference =
          degradationPreference ==
              ScreenShareDegradationPreference.maintainFramerate
          ? RTCDegradationPreference.MAINTAIN_FRAMERATE
          : RTCDegradationPreference.MAINTAIN_RESOLUTION;

      final encodings = params.encodings;
      if (encodings == null || encodings.isEmpty) {
        params.encodings = [
          RTCRtpEncoding(
            active: true,
            maxBitrate: resolution.maxBitrateBps,
            maxFramerate: frameRate.fps,
            scaleResolutionDownBy: scaleResolutionDownBy,
          ),
        ];
      } else {
        for (final encoding in encodings) {
          encoding.maxBitrate = resolution.maxBitrateBps;
          encoding.maxFramerate = frameRate.fps;
          encoding.scaleResolutionDownBy = scaleResolutionDownBy;
        }
      }
      await videoSender.setParameters(params);
    } catch (_) {
      // Ignore platforms where sender.parameters is not mutable prior to negotiation.
    }
  }

  Future<void> _sendLocalViewerCandidate({
    required int currentGeneration,
    required _ViewerPeerSession viewerSession,
    required RTCIceCandidate candidate,
  }) async {
    if (!_isViewerSessionValid(
      currentGeneration,
      viewerSession.viewerClid,
      viewerSession.peerGeneration,
    )) {
      return;
    }
    final candidateSdp = candidate.candidate;
    if (candidateSdp == null || candidateSdp.isEmpty) return;
    logInfo(
      'Sending iceCandidate for viewer ${viewerSession.viewerClid} '
      '(mid=${candidate.sdpMid ?? '-'}, mLine=${candidate.sdpMLineIndex ?? '-'})',
      target: 'stream',
    );
    try {
      await ref
          .read(coreSessionProvider)
          .sendPublisherIceCandidate(
            viewerClid: viewerSession.viewerClid,
            sdp: candidateSdp,
            mid: candidate.sdpMid,
            mLine: candidate.sdpMLineIndex,
          );
    } catch (e) {
      logWarn(
        'Failed to send iceCandidate for viewer ${viewerSession.viewerClid}',
        target: 'stream',
        error: e,
      );
    }
  }

  Future<void> _flushPendingLocalViewerCandidates({
    required int currentGeneration,
    required _ViewerPeerSession viewerSession,
  }) async {
    if (viewerSession.pendingLocalCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.of(
      viewerSession.pendingLocalCandidates,
    );
    viewerSession.pendingLocalCandidates.clear();
    for (final candidate in pending) {
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerSession.viewerClid,
        viewerSession.peerGeneration,
      )) {
        return;
      }
      await _sendLocalViewerCandidate(
        currentGeneration: currentGeneration,
        viewerSession: viewerSession,
        candidate: candidate,
      );
    }
  }

  Future<void> _flushPendingViewerCandidates({
    required int currentGeneration,
    required _ViewerPeerSession viewerSession,
  }) async {
    final peer = viewerSession.peer;
    if (peer == null || viewerSession.pendingRemoteCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.of(
      viewerSession.pendingRemoteCandidates,
    );
    viewerSession.pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerSession.viewerClid,
        viewerSession.peerGeneration,
      )) {
        return;
      }
      try {
        await peer.addCandidate(candidate);
      } catch (e) {
        logWarn(
          'Failed to apply queued remote iceCandidate for viewer ${viewerSession.viewerClid}',
          target: 'stream',
          error: e,
        );
      }
    }
  }

  void _armViewerNegotiationTimer({
    required int currentGeneration,
    required _ViewerPeerSession viewerSession,
  }) {
    _clearViewerNegotiationTimer(viewerSession);
    viewerSession.negotiationTimer = Timer(defaultStreamNegotiationTimeout, () {
      if (!_isViewerSessionValid(
        currentGeneration,
        viewerSession.viewerClid,
        viewerSession.peerGeneration,
      )) {
        return;
      }
      unawaited(
        _failViewerSession(
          viewerSession.viewerClid,
          reason: _ViewerFailureReason.answerTimeout,
        ),
      );
    });
  }

  /// Ends a viewer session that never reached `connected`, logs the reason, and
  /// releases the viewer on the server so the official client stops waiting on a
  /// stream that will not arrive.
  Future<void> _failViewerSession(
    int viewerClid, {
    required _ViewerFailureReason reason,
  }) async {
    final session = _viewerSessions[viewerClid];
    if (session == null || session.failureReported) return;
    session.failureReported = true;
    logWarn(
      'viewer $viewerClid negotiation failed: ${reason.name}',
      target: 'stream',
    );
    await _closeViewerSession(viewerClid);
    try {
      await ref
          .read(coreSessionProvider)
          .kickStreamViewer(viewerClid: viewerClid);
    } catch (_) {
      // The viewer may already have left or the stream may be stopping.
    }
  }

  void _clearViewerNegotiationTimer(_ViewerPeerSession viewerSession) {
    viewerSession.negotiationTimer?.cancel();
    viewerSession.negotiationTimer = null;
  }

  void _syncViewerIds() {
    if (!ref.mounted) return;
    state = state.copyWith(
      viewerIds: Set<int>.unmodifiable(_viewerSessions.keys),
    );
  }

  Future<void> _closeViewerSession(int viewerClid) async {
    final session = _viewerSessions.remove(viewerClid);
    if (session == null) return;
    _clearViewerNegotiationTimer(session);
    session.pendingLocalCandidates.clear();
    session.pendingRemoteCandidates.clear();
    _syncViewerIds();

    final peer = session.peer;
    session.peer = null;
    if (peer != null) {
      await _safeDisposePeer(peer);
    }
  }

  Future<void> _safeDisposePeer(RTCPeerConnection peer) async {
    peer.onIceCandidate = null;
    peer.onTrack = null;
    peer.onAddStream = null;
    peer.onConnectionState = null;
    peer.onIceConnectionState = null;
    try {
      await peer.close();
    } catch (_) {}
    try {
      await peer.dispose();
    } catch (_) {}
  }

  Future<void> _disposeMediaStream(MediaStream stream) async {
    try {
      for (final track in stream.getTracks()) {
        track.onEnded = null;
        try {
          await track.stop();
        } catch (_) {}
      }
    } catch (_) {}
    try {
      await stream.dispose();
    } catch (_) {}
  }

  Future<void> _downgradeAndroidMediaProjection() async {
    final handler = _androidMediaProjectionHandler;
    _androidMediaProjectionUpgraded = false;
    _androidMediaProjectionHandler = null;
    if (handler == null) {
      return;
    }
    await _invokeAndroidMediaProjectionDowngrade(handler);
  }

  Future<void> _invokeAndroidMediaProjectionDowngrade(
    Future<bool> Function(bool active) handler,
  ) async {
    try {
      await handler(false);
    } catch (error) {
      logWarn(
        'Failed to downgrade Android media projection foreground service',
        target: 'stream',
        error: error,
      );
    }
  }

  Future<void> _disposeAllResources({bool updateState = true}) async {
    _generation++;
    final shouldDowngradeMediaProjection = _androidMediaProjectionUpgraded;
    final projectionHandler = _androidMediaProjectionHandler;
    _androidMediaProjectionUpgraded = false;
    _androidMediaProjectionHandler = null;
    final sessions = _viewerSessions.values.toList(growable: false);
    _viewerSessions.clear();
    for (final session in sessions) {
      _clearViewerNegotiationTimer(session);
      session.pendingLocalCandidates.clear();
      session.pendingRemoteCandidates.clear();
    }

    final localStream = _localStream;
    final previewRenderer = _previewRenderer;
    _localStream = null;
    _previewRenderer = null;

    if (updateState && ref.mounted) {
      state = const StreamPublisherState();
    }

    for (final session in sessions) {
      final peer = session.peer;
      session.peer = null;
      if (peer != null) {
        await _safeDisposePeer(peer);
      }
    }

    if (previewRenderer != null) {
      previewRenderer.onResize = null;
      try {
        previewRenderer.srcObject = null;
      } catch (_) {}
      try {
        await previewRenderer.dispose();
      } catch (_) {}
    }

    if (localStream != null) {
      await _disposeMediaStream(localStream);
    }

    if (shouldDowngradeMediaProjection &&
        projectionHandler != null &&
        updateState &&
        ref.mounted) {
      await _invokeAndroidMediaProjectionDowngrade(projectionHandler);
    }
  }
}
