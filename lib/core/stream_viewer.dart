import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'preferences.dart';
import 'providers.dart';
import 'window_chrome.dart';

/// Default STUN server configuration for TS6 screen-share viewer connections.
/// Prioritizes fast, widely reachable STUN servers (Cloudflare, QQ, MiWiFi,
/// Syncthing) before Google STUN to avoid lengthy timeouts in restricted networks.
/// Default STUN server configuration for TS6 screen-share viewer and publisher connections.
/// Combines TeamSpeak official STUN servers with high-speed domestic and global STUN candidates
/// for fast, reliable ICE candidate gathering across NATs.
const List<Map<String, dynamic>> defaultStreamIceServers = [
  {
    'urls': [
      'stun:turn.teamspeak.com:3478',
      'stun:turn2.teamspeak.com:3478',
      'stun:stun.miwifi.com:3478',
      'stun:stun.chat.bilibili.com:3478',
      'stun:stun.qq.com:3478',
      'stun:stun.aliyun.com:3478',
      'stun:stun.cloudflare.com:3478',
      'stun:stun.bige0.com:3478',
      'stun:stun.hitv.com:3478',
      'stun:stun.syncthing.net:3478',
    ],
  },
];

/// Default timeout for WebRTC offer/answer + ICE negotiation.
const Duration defaultStreamNegotiationTimeout = Duration(seconds: 15);

/// Reorders the `m=video` payload type list in [sdp] so [preferredCodec] (e.g.
/// `VP8` or `H264`, along with its associated `rtx` payload types) appears
/// first, while keeping `m=audio` and all MID attributes intact for TS6 native
/// client compatibility.
String preferCodecInSdp(String sdp, String preferredCodec) {
  if (sdp.isEmpty) return sdp;
  final targetCodec = preferredCodec.trim().toUpperCase();
  if (targetCodec.isEmpty) return sdp;
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

  final matchingPts = <String>{};
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
      if (codec == targetCodec) {
        matchingPts.add(pt);
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

  if (matchingPts.isEmpty) {
    return sdp;
  }

  final prioritizedPts = <String>{
    ...matchingPts,
    for (final entry in rtxAptMap.entries)
      if (matchingPts.contains(entry.value)) entry.key,
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

/// Reorders the `m=video` payload type list in [sdp] so `VP8` (and its
/// associated `rtx` payload types) appear first, while keeping `m=audio`
/// and all MID attributes intact for TS6 native client compatibility.
String preferVp8InSdp(String sdp) => preferCodecInSdp(sdp, 'VP8');

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

/// Ensures that the `m=audio` section in [sdp] has `a=$targetDirection`
/// (e.g. `a=sendonly` for screen publisher offers or `a=recvonly` for viewer offers).
///
/// In WebRTC unified-plan, creating an offer for an audio transceiver without an
/// attached audio track (e.g. screen sharing without system audio) causes
/// native `libwebrtc` to emit `a=inactive` (RFC 8829 Section 5.2.1). However,
/// official TeamSpeak 5/6 clients strictly require `slot=1 media=audio dir=kSendOnly`
/// in publisher offers, ignoring or hanging indefinitely on `a=inactive` offers.
///
/// If a direction attribute (`a=sendrecv`, `a=sendonly`, `a=recvonly`, `a=inactive`)
/// is present in `m=audio`, replaces it with `a=$targetDirection`.
/// If no direction attribute is present, inserts `a=$targetDirection`.
String ensureAudioDirectionInSdp(String sdp, String targetDirection) {
  if (sdp.isEmpty) return sdp;
  final lineSeparator = sdp.contains('\r\n') ? '\r\n' : '\n';
  final lines = sdp.split(RegExp(r'\r?\n'));

  var audioStart = -1;
  var audioEnd = lines.length;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (audioStart == -1) {
      if (line.startsWith('m=audio ')) {
        audioStart = i;
      }
    } else if (line.startsWith('m=')) {
      audioEnd = i;
      break;
    }
  }

  if (audioStart == -1) return sdp;

  final directionRegex = RegExp(r'^a=(sendrecv|sendonly|recvonly|inactive)$');
  var foundDirection = false;
  final updatedLines = <String>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (i > audioStart && i < audioEnd) {
      if (directionRegex.hasMatch(line.trim())) {
        updatedLines.add('a=$targetDirection');
        foundDirection = true;
        continue;
      }
    }
    updatedLines.add(line);
  }

  if (!foundDirection) {
    // Insert a=$targetDirection after a=mid: or right after m=audio
    var insertIdx = audioStart + 1;
    for (var i = audioStart + 1; i < audioEnd && i < updatedLines.length; i++) {
      if (updatedLines[i].trim().startsWith('a=mid:')) {
        insertIdx = i + 1;
        break;
      }
    }
    updatedLines.insert(insertIdx, 'a=$targetDirection');
  }

  return updatedLines.join(lineSeparator);
}

/// Prunes unused codecs from [sdp] to keep the SDP offer compact and prevent
/// TeamSpeak command buffer overflow (>9,150 bytes escaped on wire).
///
/// In native `libwebrtc`, an offer often lists 10+ video codecs and 14+ audio codecs,
/// producing a raw SDP of 5-6 KB that swells to over 10 KB when escaped with TeamSpeak
/// protocol syntax (`\s`, `\/`, `\r\n`), causing TeamSpeak server to silently drop
/// `respondjoinstreamrequest`.
///
/// This function:
/// - In `m=video`: retains only payload types matching [targetVideoCodec] (e.g. `VP8`)
///   and [fallbackVideoCodec] (e.g. `H264`), along with their associated RTX payload types.
///   Removes all other video payload types and their `a=rtpmap`, `a=rtcp-fb`, and `a=fmtp` lines.
/// - In `m=audio`: retains only the `opus` payload type (and its RTX if any), removing
///   extraneous audio codecs (G722, PCMU, PCMA, ISAC, telephone-event, red, etc.).
String pruneSdpCodecsForTs6(
  String sdp, {
  String targetVideoCodec = 'VP8',
  String? fallbackVideoCodec = 'H264',
}) {
  if (sdp.isEmpty) return sdp;
  final lineSeparator = sdp.contains('\r\n') ? '\r\n' : '\n';
  final lines = sdp.split(RegExp(r'\r?\n'));

  var videoStart = -1;
  var audioStart = -1;
  var videoEnd = lines.length;
  var audioEnd = lines.length;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('m=video ')) {
      videoStart = i;
    } else if (line.startsWith('m=audio ')) {
      audioStart = i;
    }
  }

  if (videoStart != -1 && audioStart != -1) {
    if (videoStart < audioStart) {
      videoEnd = audioStart;
      audioEnd = lines.length;
    } else {
      audioEnd = videoStart;
      videoEnd = lines.length;
    }
  } else if (videoStart != -1) {
    videoEnd = lines.length;
  } else if (audioStart != -1) {
    audioEnd = lines.length;
  }

  final targetUpper = targetVideoCodec.trim().toUpperCase();
  final fallbackUpper = fallbackVideoCodec?.trim().toUpperCase();

  final rtpmapRegex = RegExp(
    r'^a=rtpmap:(\d+)\s+([^/\s]+)/',
    caseSensitive: false,
  );
  final fmtpAptRegex = RegExp(
    r'^a=fmtp:(\d+)\s+.*\bapt=(\d+)\b',
    caseSensitive: false,
  );
  final codecAttrRegex = RegExp(
    r'^a=(rtpmap|rtcp-fb|fmtp):(\d+)\b',
    caseSensitive: false,
  );

  // 1. Process video section
  Set<String>? keptVideoPts;
  List<String>? orderedVideoPts;
  if (videoStart != -1) {
    final videoHeaderParts = lines[videoStart].trim().split(RegExp(r'\s+'));
    if (videoHeaderParts.length > 3) {
      final originalPts = videoHeaderParts.sublist(3);
      final targetPts = <String>{};
      final fallbackPts = <String>{};
      final rtxAptMap = <String, String>{};

      for (var i = videoStart + 1; i < videoEnd; i++) {
        final line = lines[i].trim();
        final rtpmapMatch = rtpmapRegex.firstMatch(line);
        if (rtpmapMatch != null) {
          final pt = rtpmapMatch.group(1)!;
          final codec = rtpmapMatch.group(2)!.toUpperCase();
          if (codec == targetUpper) {
            targetPts.add(pt);
          } else if (fallbackUpper != null && codec == fallbackUpper) {
            fallbackPts.add(pt);
          }
          continue;
        }
        final fmtpMatch = fmtpAptRegex.firstMatch(line);
        if (fmtpMatch != null) {
          rtxAptMap[fmtpMatch.group(1)!] = fmtpMatch.group(2)!;
        }
      }

      final prioritizedTargetPts = <String>[
        for (final pt in originalPts)
          if (targetPts.contains(pt)) pt,
        for (final entry in rtxAptMap.entries)
          if (targetPts.contains(entry.value) &&
              originalPts.contains(entry.key))
            entry.key,
      ];

      final prioritizedFallbackPts = <String>[
        for (final pt in originalPts)
          if (fallbackPts.contains(pt) && !prioritizedTargetPts.contains(pt))
            pt,
        for (final entry in rtxAptMap.entries)
          if (fallbackPts.contains(entry.value) &&
              originalPts.contains(entry.key) &&
              !prioritizedTargetPts.contains(entry.key))
            entry.key,
      ];

      if (prioritizedTargetPts.isNotEmpty ||
          prioritizedFallbackPts.isNotEmpty) {
        orderedVideoPts = [...prioritizedTargetPts, ...prioritizedFallbackPts];
        keptVideoPts = orderedVideoPts.toSet();
      }
    }
  }

  // 2. Process audio section
  Set<String>? keptAudioPts;
  List<String>? orderedAudioPts;
  if (audioStart != -1) {
    final audioHeaderParts = lines[audioStart].trim().split(RegExp(r'\s+'));
    if (audioHeaderParts.length > 3) {
      final originalAudioPts = audioHeaderParts.sublist(3);
      final opusPts = <String>{};
      final audioRtxMap = <String, String>{};

      for (var i = audioStart + 1; i < audioEnd; i++) {
        final line = lines[i].trim();
        final rtpmapMatch = rtpmapRegex.firstMatch(line);
        if (rtpmapMatch != null) {
          final pt = rtpmapMatch.group(1)!;
          final codec = rtpmapMatch.group(2)!.toUpperCase();
          if (codec == 'OPUS') {
            opusPts.add(pt);
          }
          continue;
        }
        final fmtpMatch = fmtpAptRegex.firstMatch(line);
        if (fmtpMatch != null) {
          audioRtxMap[fmtpMatch.group(1)!] = fmtpMatch.group(2)!;
        }
      }

      if (opusPts.isNotEmpty) {
        orderedAudioPts = [
          for (final pt in originalAudioPts)
            if (opusPts.contains(pt)) pt,
          for (final entry in audioRtxMap.entries)
            if (opusPts.contains(entry.value) &&
                originalAudioPts.contains(entry.key))
              entry.key,
        ];
        keptAudioPts = orderedAudioPts.toSet();
      }
    }
  }

  // 3. Assemble filtered lines
  final updatedLines = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (i == videoStart && orderedVideoPts != null) {
      final headerPrefix = line.trim().split(RegExp(r'\s+')).sublist(0, 3);
      updatedLines.add(
        '${headerPrefix.join(' ')} ${orderedVideoPts.join(' ')}',
      );
      continue;
    }
    if (i == audioStart && orderedAudioPts != null) {
      final headerPrefix = line.trim().split(RegExp(r'\s+')).sublist(0, 3);
      updatedLines.add(
        '${headerPrefix.join(' ')} ${orderedAudioPts.join(' ')}',
      );
      continue;
    }

    if (videoStart != -1 &&
        i > videoStart &&
        i < videoEnd &&
        keptVideoPts != null) {
      final match = codecAttrRegex.firstMatch(line.trim());
      if (match != null) {
        final pt = match.group(2)!;
        if (!keptVideoPts.contains(pt)) {
          continue; // Strip discarded video codec attributes
        }
      }
    } else if (audioStart != -1 &&
        i > audioStart &&
        i < audioEnd &&
        keptAudioPts != null) {
      final match = codecAttrRegex.firstMatch(line.trim());
      if (match != null) {
        final pt = match.group(2)!;
        if (!keptAudioPts.contains(pt)) {
          continue; // Strip discarded audio codec attributes
        }
      }
    }

    updatedLines.add(line);
  }

  return updatedLines.join(lineSeparator);
}

/// Normalizes an Offer or Answer SDP for TS6 native compatibility:
/// - Prunes unused codecs to stay safely under TeamSpeak's 9,150 byte line limit.
/// - Prioritizes [preferredVideoCodec] (`VP8` by default, or `H264`) in `m=video`.
/// - Guarantees `m=audio` has `a=$fallbackAudioDirection` (`sendonly` for publisher,
///   `recvonly` for viewer) even when native `libwebrtc` generated `a=inactive` due
///   to lack of an audio track.
/// - Appends a minimal `m=audio` section with `a=mid:1` and `a=$fallbackAudioDirection`
///   only if the input SDP omitted `m=audio` completely.
String normalizeSdpForTs6(
  String sdp, {
  String preferredVideoCodec = 'VP8',
  String fallbackAudioDirection = 'recvonly',
  bool pruneUnusedCodecs = true,
}) {
  if (sdp.isEmpty) return sdp;
  final codecNormalized = pruneUnusedCodecs
      ? pruneSdpCodecsForTs6(
          sdp,
          targetVideoCodec: preferredVideoCodec,
          fallbackVideoCodec: preferredVideoCodec.toUpperCase() == 'VP8'
              ? 'H264'
              : 'VP8',
        )
      : preferCodecInSdp(sdp, preferredVideoCodec);
  final layout = inspectSdpMediaLayout(codecNormalized);
  if (!layout.hasVideo) {
    return codecNormalized;
  }
  if (layout.hasAudio) {
    return ensureAudioDirectionInSdp(codecNormalized, fallbackAudioDirection);
  }
  final lineSeparator = codecNormalized.contains('\r\n') ? '\r\n' : '\n';
  final trimmed = codecNormalized.endsWith(lineSeparator)
      ? codecNormalized
      : '$codecNormalized$lineSeparator';
  final fallbackAudioSection = [
    'm=audio 9 UDP/TLS/RTP/SAVPF 111',
    'c=IN IP4 0.0.0.0',
    'a=rtcp:9 IN IP4 0.0.0.0',
    'a=mid:1',
    'a=$fallbackAudioDirection',
    'a=rtcp-mux',
    'a=rtpmap:111 opus/48000/2',
  ].join(lineSeparator);
  return '$trimmed$fallbackAudioSection$lineSeparator';
}

/// Applies codec preference ordering on a video [transceiver] so codecs
/// matching [preferredMimeType] (e.g. `video/vp8` or `video/h264`) appear first.
///
/// Preserves `video/rtx` retransmission payloads paired with their parent codec
/// and retains auxiliary resilience payloads (`video/red`, `video/ulpfec`)
/// so native `libwebrtc` does not reject `setCodecPreferences` with
/// `INVALID_MODIFICATION`.
Future<void> preferVideoCodecOnTransceiver({
  required RTCRtpCapabilities? capabilities,
  required RTCRtpTransceiver transceiver,
  String preferredMimeType = 'video/vp8',
}) async {
  final codecs = capabilities?.codecs;
  if (codecs == null || codecs.isEmpty) return;

  final targetMime = preferredMimeType.trim().toLowerCase();
  final secondaryMime = targetMime == 'video/vp8' ? 'video/h264' : 'video/vp8';

  final preferredBlocks = <List<RTCRtpCodecCapability>>[];
  final secondaryBlocks = <List<RTCRtpCodecCapability>>[];
  final auxiliaryCodecs = <RTCRtpCodecCapability>[];

  List<RTCRtpCodecCapability>? currentBlock;
  int currentBlockCategory = 0; // 1 = preferred, 2 = secondary, 0 = other

  for (final codec in codecs) {
    final mime = codec.mimeType.toLowerCase();
    if (mime == 'video/rtx') {
      if (currentBlock != null) {
        currentBlock.add(codec);
      } else {
        auxiliaryCodecs.add(codec);
      }
    } else if (mime == 'video/red' ||
        mime == 'video/ulpfec' ||
        mime == 'video/flexfec-03') {
      auxiliaryCodecs.add(codec);
    } else {
      if (currentBlock != null) {
        if (currentBlockCategory == 1) {
          preferredBlocks.add(currentBlock);
        } else if (currentBlockCategory == 2) {
          secondaryBlocks.add(currentBlock);
        }
      }
      currentBlock = [codec];
      if (mime == targetMime) {
        currentBlockCategory = 1;
      } else if (mime == secondaryMime) {
        currentBlockCategory = 2;
      } else {
        currentBlockCategory = 0;
      }
    }
  }

  if (currentBlock != null) {
    if (currentBlockCategory == 1) {
      preferredBlocks.add(currentBlock);
    } else if (currentBlockCategory == 2) {
      secondaryBlocks.add(currentBlock);
    }
  }

  if (preferredBlocks.isEmpty && secondaryBlocks.isEmpty) return;

  final orderedCodecs = <RTCRtpCodecCapability>[
    for (final block in preferredBlocks) ...block,
    ...auxiliaryCodecs,
    for (final block in secondaryBlocks) ...block,
  ];

  try {
    await transceiver.setCodecPreferences(orderedCodecs);
  } catch (_) {
    // Ignore platforms that do not support setCodecPreferences; SDP
    // normalization (`pruneSdpCodecsForTs6`) still reorders and prunes codecs.
  }
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

  Future<RTCRtpCapabilities?> getVideoSenderCapabilities() async => null;

  Future<void> setTrackVolume(double volume, MediaStreamTrack track);

  Future<List<DesktopCapturerSource>> getDesktopSources({
    List<SourceType> types = const [SourceType.Screen, SourceType.Window],
    ThumbnailSize? thumbnailSize,
  }) async => const [];

  Future<MediaStream> getDisplayMedia(Map<String, dynamic> mediaConstraints) {
    throw UnimplementedError('getDisplayMedia is not implemented');
  }
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
  Future<RTCRtpCapabilities?> getVideoSenderCapabilities() async {
    try {
      return await getRtpSenderCapabilities('video');
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

  @override
  Future<List<DesktopCapturerSource>> getDesktopSources({
    List<SourceType> types = const [SourceType.Screen, SourceType.Window],
    ThumbnailSize? thumbnailSize,
  }) {
    return desktopCapturer.getSources(
      types: types,
      thumbnailSize: thumbnailSize,
    );
  }

  @override
  Future<MediaStream> getDisplayMedia(Map<String, dynamic> mediaConstraints) {
    return navigator.mediaDevices.getDisplayMedia(mediaConstraints);
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
    this.isFullScreen = false,
    this.endNotice,
  });

  final String? streamId;
  final int? sourceClientId;
  final RTCVideoRenderer? renderer;
  final bool isConnecting;
  final bool hasVideo;
  final bool isMuted;
  final bool isFullScreen;
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
    bool? isFullScreen,
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
      isFullScreen: isFullScreen ?? this.isFullScreen,
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
  final List<RTCIceCandidate> _pendingLocalCandidates = [];
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  final List<MediaStreamTrack> _remoteAudioTracks = [];
  Timer? _negotiationTimer;
  bool _remoteDescriptionSet = false;
  bool _answerSent = false;
  bool _windowWasFullScreenBeforeStream = false;
  bool _changingWindowFullScreen = false;
  int _generation = 0;

  @override
  StreamViewerState build() {
    void handleWindowFullScreenChanged() {
      if (_changingWindowFullScreen || !ref.mounted) return;
      if (!WindowChrome.fullScreen.value && state.isFullScreen) {
        _windowWasFullScreenBeforeStream = false;
        state = state.copyWith(isFullScreen: false);
      }
    }

    WindowChrome.fullScreen.addListener(handleWindowFullScreenChanged);
    ref.onDispose(() {
      WindowChrome.fullScreen.removeListener(handleWindowFullScreenChanged);
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
      isFullScreen: state.isFullScreen,
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
      isFullScreen: state.isFullScreen,
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

      final codecPreference = ref.read(preferencesProvider).screenShareCodec;
      final preferredCodec = codecPreference == ScreenShareCodecPreference.h264
          ? 'H264'
          : 'VP8';
      final preferredMime = codecPreference == ScreenShareCodecPreference.h264
          ? 'video/h264'
          : 'video/vp8';

      await _preferCodecOnTransceiver(
        bindings,
        videoTransceiver,
        preferredMimeType: preferredMime,
      );
      if (!_isCurrentGeneration(currentGeneration)) return;

      peer.onIceCandidate = (candidate) {
        if (!_isCurrentGeneration(currentGeneration)) return;
        final candidateSdp = candidate.candidate;
        if (candidateSdp == null || candidateSdp.isEmpty) return;
        if (!_answerSent) {
          _pendingLocalCandidates.add(candidate);
          return;
        }
        unawaited(
          _sendLocalIceCandidate(
            generation: currentGeneration,
            streamId: streamId,
            targetClid: sourceClientId,
            candidate: candidate,
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

      final normalizedOfferSdp = normalizeSdpForTs6(
        sdp,
        preferredVideoCodec: preferredCodec,
      );
      await peer.setRemoteDescription(
        RTCSessionDescription(normalizedOfferSdp, 'offer'),
      );
      if (!_isCurrentGeneration(currentGeneration)) return;

      _remoteDescriptionSet = true;
      await _flushPendingRemoteCandidates(currentGeneration, peer);
      if (!_isCurrentGeneration(currentGeneration)) return;

      final rawAnswer = await peer.createAnswer();
      if (!_isCurrentGeneration(currentGeneration)) return;

      final answerSdp = normalizeSdpForTs6(
        rawAnswer.sdp ?? '',
        preferredVideoCodec: preferredCodec,
      );
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
      if (!_isCurrentGeneration(currentGeneration)) return;
      _answerSent = true;
      await _flushPendingLocalCandidates(
        generation: currentGeneration,
        streamId: streamId,
        targetClid: sourceClientId,
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

  /// Toggles whether the viewer stage occupies OS screen fullscreen.
  Future<void> toggleFullScreen() async {
    await setFullScreen(!state.isFullScreen);
  }

  /// Enters or exits OS screen fullscreen for the active stream viewer.
  Future<void> setFullScreen(bool fullScreen) async {
    if (state.isFullScreen == fullScreen) return;
    if (fullScreen && !state.isActive) return;

    if (fullScreen) {
      _windowWasFullScreenBeforeStream = WindowChrome.fullScreen.value;
      state = state.copyWith(isFullScreen: true);
      if (!_windowWasFullScreenBeforeStream) {
        _changingWindowFullScreen = true;
        try {
          await WindowChrome.setFullScreen(true);
        } finally {
          _changingWindowFullScreen = false;
        }
      }
      return;
    }

    final shouldExitNativeWindow = !_windowWasFullScreenBeforeStream;
    _windowWasFullScreenBeforeStream = false;
    state = state.copyWith(isFullScreen: false);
    if (shouldExitNativeWindow && WindowChrome.fullScreen.value) {
      _changingWindowFullScreen = true;
      try {
        await WindowChrome.setFullScreen(false);
      } finally {
        _changingWindowFullScreen = false;
      }
    }
  }

  /// Clears any transient stream end notice.
  void clearEndNotice() {
    if (state.endNotice == null) return;
    state = state.copyWith(clearEndNotice: true);
  }

  /// Destroys the active `RTCPeerConnection` and `RTCVideoRenderer` immediately.
  Future<void> closeSession({StreamEndNotice? endNotice}) async {
    final preserveMuted = state.isMuted;
    final wasFullScreen = state.isFullScreen;
    final shouldExitNativeWindow =
        wasFullScreen && !_windowWasFullScreenBeforeStream;
    _windowWasFullScreenBeforeStream = false;
    await _disposeResources();
    state = StreamViewerState(isMuted: preserveMuted, endNotice: endNotice);
    if (shouldExitNativeWindow && WindowChrome.fullScreen.value) {
      _changingWindowFullScreen = true;
      try {
        await WindowChrome.setFullScreen(false);
      } finally {
        _changingWindowFullScreen = false;
      }
    }
  }

  bool _isCurrentGeneration(int generation) => _generation == generation;

  Future<void> _sendLocalIceCandidate({
    required int generation,
    required String streamId,
    required int targetClid,
    required RTCIceCandidate candidate,
  }) async {
    if (!_isCurrentGeneration(generation)) return;
    final candidateSdp = candidate.candidate;
    if (candidateSdp == null || candidateSdp.isEmpty) return;
    try {
      await ref
          .read(coreSessionProvider)
          .sendStreamIceCandidate(
            streamId: streamId,
            targetClid: targetClid,
            sdp: candidateSdp,
            mid: candidate.sdpMid,
            mLine: candidate.sdpMLineIndex,
          );
    } catch (_) {
      // Ignore late ICE candidate signaling errors if the stream already ended.
    }
  }

  Future<void> _flushPendingLocalCandidates({
    required int generation,
    required String streamId,
    required int targetClid,
  }) async {
    if (_pendingLocalCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.of(_pendingLocalCandidates);
    _pendingLocalCandidates.clear();
    for (final candidate in pending) {
      if (!_isCurrentGeneration(generation)) return;
      await _sendLocalIceCandidate(
        generation: generation,
        streamId: streamId,
        targetClid: targetClid,
        candidate: candidate,
      );
    }
  }

  Future<void> _preferCodecOnTransceiver(
    WebRtcBindings bindings,
    RTCRtpTransceiver transceiver, {
    required String preferredMimeType,
  }) async {
    final capabilities = await bindings.getVideoReceiverCapabilities();
    await preferVideoCodecOnTransceiver(
      capabilities: capabilities,
      transceiver: transceiver,
      preferredMimeType: preferredMimeType,
    );
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
    _answerSent = false;
    _pendingLocalCandidates.clear();
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
