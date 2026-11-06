import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../core/stream_viewer.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';

/// Top workspace section displaying active channel screen shares and the
/// embedded WebRTC video viewer when watching a stream.
class StreamViewerSection extends ConsumerWidget {
  const StreamViewerSection({required this.view, super.key});

  final SessionView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!view.connected) {
      return const SizedBox.shrink();
    }

    final viewer = ref.watch(streamViewerProvider);
    final activeStreamId = viewer.streamId ?? view.watchingStreamId;
    final watchingStream = activeStreamId == null
        ? null
        : _findStream(view.streams, activeStreamId);

    if (viewer.isActive || watchingStream != null) {
      final publisherName = _resolvePublisherName(
        view: view,
        stream: watchingStream,
        fallbackClientId: viewer.sourceClientId,
      );
      return _StreamViewerStage(
        view: view,
        viewer: viewer,
        publisherName: publisherName,
      );
    }

    if (view.streams.isEmpty) {
      return const SizedBox.shrink();
    }

    return _ActiveStreamsBar(view: view);
  }

  StreamView? _findStream(List<StreamView> streams, String streamId) {
    for (final stream in streams) {
      if (stream.id == streamId) {
        return stream;
      }
    }
    return null;
  }

  String _resolvePublisherName({
    required SessionView view,
    required StreamView? stream,
    required int? fallbackClientId,
  }) {
    final clientId = stream?.clientId ?? fallbackClientId;
    if (clientId != null) {
      for (final client in view.clients) {
        if (client.id == clientId && client.nickname.trim().isNotEmpty) {
          return client.nickname;
        }
      }
    }
    if (stream != null && stream.name.trim().isNotEmpty) {
      return stream.name;
    }
    return '#${clientId ?? 0}';
  }
}

class _ActiveStreamsBar extends ConsumerWidget {
  const _ActiveStreamsBar({required this.view});

  final SessionView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final controller = ref.read(sessionViewProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final stream in view.streams)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                key: ValueKey('stream-banner-${stream.id}'),
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: Radii.largeAll,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: Radii.smallAll,
                      ),
                      child: Icon(
                        Icons.screen_share_rounded,
                        size: IconSizes.state,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_publisherName(view, stream)} · ${l10n.streamSharing}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      key: ValueKey('stream-watch-${stream.id}'),
                      onPressed: () => controller.watchStream(stream),
                      icon: const Icon(
                        Icons.visibility_rounded,
                        size: IconSizes.state,
                      ),
                      label: Text(l10n.streamWatch),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _publisherName(SessionView view, StreamView stream) {
    for (final client in view.clients) {
      if (client.id == stream.clientId && client.nickname.trim().isNotEmpty) {
        return client.nickname;
      }
    }
    return stream.name.trim().isNotEmpty ? stream.name : '#${stream.clientId}';
  }
}

class _StreamViewerStage extends ConsumerWidget {
  const _StreamViewerStage({
    required this.view,
    required this.viewer,
    required this.publisherName,
  });

  final SessionView view;
  final StreamViewerState viewer;
  final String publisherName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final sessionController = ref.read(sessionViewProvider.notifier);
    final viewerController = ref.read(streamViewerProvider.notifier);
    final stageHeight = viewer.isExpanded ? 340.0 : 216.0;
    final renderer = viewer.renderer;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AnimatedContainer(
        key: const ValueKey('stream-viewer-stage'),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.effectsDefault,
        curve: Motion.effectsDefaultCurve,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: Radii.largeAll,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.screen_share_rounded,
                    size: IconSizes.medium,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l10n.streamWatching} · $publisherName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('stream-mute-toggle'),
                    onPressed: viewerController.toggleMuted,
                    icon: Icon(
                      viewer.isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      size: IconSizes.medium,
                      color: viewer.isMuted
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                      semanticLabel: viewer.isMuted
                          ? l10n.streamUnmute
                          : l10n.streamMute,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('stream-expand-toggle'),
                    onPressed: viewerController.toggleExpanded,
                    icon: Icon(
                      viewer.isExpanded
                          ? Icons.close_fullscreen_rounded
                          : Icons.open_in_full_rounded,
                      size: IconSizes.medium,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: viewer.isExpanded
                          ? l10n.streamCollapse
                          : l10n.streamExpand,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('stream-close-button'),
                    onPressed: () =>
                        sessionController.leaveStream(viewer.streamId),
                    icon: Icon(
                      Icons.close_rounded,
                      size: IconSizes.medium,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: l10n.streamStopWatching,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ClipRRect(
                borderRadius: Radii.mediumAll,
                child: SizedBox(
                  height: stageHeight,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xFF0A0D12)),
                    child: renderer != null
                        ? ValueListenableBuilder<RTCVideoValue>(
                            valueListenable: renderer,
                            builder: (context, videoValue, _) {
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  RTCVideoView(
                                    renderer,
                                    key: ValueKey((
                                      renderer.textureId,
                                      renderer.renderVideo,
                                      videoValue.width,
                                      videoValue.height,
                                    )),
                                    objectFit: RTCVideoViewObjectFit
                                        .RTCVideoViewObjectFitContain,
                                    placeholderBuilder: (_) =>
                                        _ConnectingPlaceholder(
                                          label: l10n.streamConnecting,
                                        ),
                                  ),
                                  if (viewer.isConnecting && !viewer.hasVideo)
                                    _ConnectingPlaceholder(
                                      label: l10n.streamConnecting,
                                    ),
                                ],
                              );
                            },
                          )
                        : _ConnectingPlaceholder(label: l10n.streamConnecting),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectingPlaceholder extends StatelessWidget {
  const _ConnectingPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: context.texts.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
