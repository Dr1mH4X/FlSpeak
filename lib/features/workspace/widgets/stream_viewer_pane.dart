import 'dart:async';
import 'dart:math' as math;

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../core/stream_publisher.dart';
import '../../../core/stream_viewer.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';

/// Top workspace section displaying active channel screen shares, the active
/// publisher status banner, and the embedded WebRTC video viewer when watching.
class StreamViewerSection extends ConsumerWidget {
  const StreamViewerSection({required this.view, super.key});

  final SessionView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!view.connected) {
      return const SizedBox.shrink();
    }

    final publisher = ref.watch(streamPublisherProvider);
    final viewer = ref.watch(streamViewerProvider);
    final activeStreamId = viewer.streamId ?? view.watchingStreamId;
    final watchingStream = activeStreamId == null
        ? null
        : _findStream(view.streams, activeStreamId);

    final children = <Widget>[];

    if (publisher.isActive) {
      children.add(_StreamPublisherBanner(publisher: publisher));
    }

    if (viewer.isActive || watchingStream != null) {
      final publisherName = _resolvePublisherName(
        view: view,
        stream: watchingStream,
        fallbackClientId: viewer.sourceClientId,
      );
      children.add(
        _StreamViewerStage(
          view: view,
          viewer: viewer,
          publisherName: publisherName,
        ),
      );
    } else {
      final remoteStreams = publisher.isActive
          ? view.streams
                .where(
                  (s) =>
                      s.id != publisher.streamId &&
                      (view.selfClientId == null ||
                          s.clientId != view.selfClientId),
                )
                .toList(growable: false)
          : view.streams;
      if (remoteStreams.isNotEmpty) {
        children.add(_ActiveStreamsBar(view: view, streams: remoteStreams));
      }
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final maxSectionHeight = viewportHeight > 300
        ? math.max(
            76.0,
            math.min(viewportHeight * 0.46, viewportHeight - 220.0),
          )
        : math.max(64.0, viewportHeight * 0.45);

    final Widget content = children.length == 1
        ? children.single
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSectionHeight),
      child: SingleChildScrollView(clipBehavior: Clip.hardEdge, child: content),
    );
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

class _StreamPublisherBanner extends ConsumerWidget {
  const _StreamPublisherBanner({required this.publisher});

  final StreamPublisherState publisher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final publisherController = ref.read(streamPublisherProvider.notifier);
    final renderer = publisher.renderer;
    final sourceLabel =
        publisher.sourceName != null && publisher.sourceName!.trim().isNotEmpty
        ? publisher.sourceName!
        : l10n.streamSharing;

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final previewHeight = math.min(
      180.0,
      math.max(88.0, (viewportHeight - 310.0) * 0.45),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AnimatedContainer(
        key: const ValueKey('stream-publisher-banner'),
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
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
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
                      '${l10n.streamPublishing} · $sourceLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    key: const ValueKey('stream-publisher-viewer-count'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer.withValues(alpha: 0.7),
                      borderRadius: Radii.smallAll,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_alt_rounded,
                          size: IconSizes.state,
                          color: scheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.streamViewerCount(publisher.viewerCount),
                          style: context.texts.labelSmall?.copyWith(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (renderer != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      key: const ValueKey('stream-publisher-preview-toggle'),
                      onPressed: publisherController.togglePreviewExpanded,
                      icon: Icon(
                        publisher.isPreviewExpanded
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: IconSizes.medium,
                        color: scheme.onSurfaceVariant,
                        semanticLabel: publisher.isPreviewExpanded
                            ? l10n.streamPreviewHide
                            : l10n.streamPreviewShow,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (publisher.viewerFailure != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(
                  key: const ValueKey('stream-publisher-viewer-failure'),
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: IconSizes.state,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.streamNegotiationFailed,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (publisher.isPreviewExpanded && renderer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: ClipRRect(
                  borderRadius: Radii.mediumAll,
                  child: SizedBox(
                    key: const ValueKey('stream-publisher-preview-stage'),
                    height: previewHeight,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: Color(0xFF0A0D12)),
                      child: ValueListenableBuilder<RTCVideoValue>(
                        valueListenable: renderer,
                        builder: (context, videoValue, _) {
                          return RTCVideoView(
                            renderer,
                            key: ValueKey((
                              renderer.textureId,
                              renderer.renderVideo,
                              videoValue.width,
                              videoValue.height,
                            )),
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitContain,
                          );
                        },
                      ),
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

class _ActiveStreamsBar extends ConsumerWidget {
  const _ActiveStreamsBar({required this.view, required this.streams});

  final SessionView view;
  final List<StreamView> streams;

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
          for (final stream in streams)
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

class _StreamViewerStage extends ConsumerStatefulWidget {
  const _StreamViewerStage({
    required this.view,
    required this.viewer,
    required this.publisherName,
  });

  final SessionView view;
  final StreamViewerState viewer;
  final String publisherName;

  @override
  ConsumerState<_StreamViewerStage> createState() => _StreamViewerStageState();
}

class _StreamViewerStageState extends ConsumerState<_StreamViewerStage> {
  final OverlayPortalController _overlayController = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _syncOverlay(widget.viewer.isFullScreen);
  }

  @override
  void didUpdateWidget(covariant _StreamViewerStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewer.isFullScreen != widget.viewer.isFullScreen) {
      _syncOverlay(widget.viewer.isFullScreen);
    }
  }

  void _syncOverlay(bool fullScreen) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (fullScreen && !_overlayController.isShowing) {
        _overlayController.show();
      } else if (!fullScreen && _overlayController.isShowing) {
        _overlayController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final sessionController = ref.read(sessionViewProvider.notifier);
    final viewerController = ref.read(streamViewerProvider.notifier);
    final viewer = widget.viewer;
    final publisherName = widget.publisherName;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final stageHeight = math.min(
      216.0,
      math.max(108.0, (viewportHeight - 290.0) * 0.5),
    );
    final renderer = viewer.renderer;

    return OverlayPortal(
      controller: _overlayController,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (overlayContext) => _StreamFullscreenStage(
        viewer: viewer,
        publisherName: publisherName,
        onToggleMute: () => unawaited(viewerController.toggleMuted()),
        onExitFullScreen: () =>
            unawaited(viewerController.setFullScreen(false)),
        onCloseStream: () =>
            unawaited(sessionController.leaveStream(viewer.streamId)),
      ),
      child: Padding(
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
                      key: const ValueKey('stream-fullscreen-toggle'),
                      onPressed: viewerController.toggleFullScreen,
                      icon: Icon(
                        viewer.isFullScreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        size: IconSizes.medium,
                        color: scheme.onSurfaceVariant,
                        semanticLabel: viewer.isFullScreen
                            ? l10n.streamExitFullscreen
                            : l10n.streamFullscreen,
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
              if (!viewer.isFullScreen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: ClipRRect(
                    borderRadius: Radii.mediumAll,
                    child: SizedBox(
                      height: stageHeight,
                      child: _StreamVideoCanvas(
                        renderer: renderer,
                        viewer: viewer,
                        connectingLabel: l10n.streamConnecting,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreamVideoCanvas extends StatelessWidget {
  const _StreamVideoCanvas({
    required this.renderer,
    required this.viewer,
    required this.connectingLabel,
  });

  final RTCVideoRenderer? renderer;
  final StreamViewerState viewer;
  final String connectingLabel;

  @override
  Widget build(BuildContext context) {
    final activeRenderer = renderer;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF0A0D12)),
      child: activeRenderer != null
          ? ValueListenableBuilder<RTCVideoValue>(
              valueListenable: activeRenderer,
              builder: (context, videoValue, _) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    RTCVideoView(
                      activeRenderer,
                      key: ValueKey((
                        activeRenderer.textureId,
                        activeRenderer.renderVideo,
                        videoValue.width,
                        videoValue.height,
                      )),
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      placeholderBuilder: (_) =>
                          _ConnectingPlaceholder(label: connectingLabel),
                    ),
                    if (viewer.isConnecting && !viewer.hasVideo)
                      _ConnectingPlaceholder(label: connectingLabel),
                  ],
                );
              },
            )
          : _ConnectingPlaceholder(label: connectingLabel),
    );
  }
}

class _StreamFullscreenStage extends StatelessWidget {
  const _StreamFullscreenStage({
    required this.viewer,
    required this.publisherName,
    required this.onToggleMute,
    required this.onExitFullScreen,
    required this.onCloseStream,
  });

  final StreamViewerState viewer;
  final String publisherName;
  final VoidCallback onToggleMute;
  final VoidCallback onExitFullScreen;
  final VoidCallback onCloseStream;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return Positioned.fill(
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): onExitFullScreen,
        },
        child: Focus(
          autofocus: true,
          child: Material(
            key: const ValueKey('stream-fullscreen-stage'),
            color: const Color(0xFF0A0D12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _StreamVideoCanvas(
                  renderer: viewer.renderer,
                  viewer: viewer,
                  connectingLabel: l10n.streamConnecting,
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: DecoratedBox(
                        key: const ValueKey('stream-fullscreen-controls'),
                        decoration: BoxDecoration(
                          color: const Color(0xD914181F),
                          borderRadius: Radii.pillAll,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.screen_share_rounded,
                                size: IconSizes.medium,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 280,
                                  ),
                                  child: Text(
                                    '${l10n.streamWatching} · $publisherName',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.texts.bodyMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 1,
                                height: 18,
                                color: Colors.white24,
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                key: const ValueKey(
                                  'stream-fullscreen-mute-toggle',
                                ),
                                onPressed: onToggleMute,
                                icon: Icon(
                                  viewer.isMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  size: IconSizes.medium,
                                  color: viewer.isMuted
                                      ? scheme.error
                                      : Colors.white70,
                                  semanticLabel: viewer.isMuted
                                      ? l10n.streamUnmute
                                      : l10n.streamMute,
                                ),
                              ),
                              IconButton(
                                key: const ValueKey(
                                  'stream-fullscreen-exit-button',
                                ),
                                onPressed: onExitFullScreen,
                                icon: Icon(
                                  Icons.fullscreen_exit_rounded,
                                  size: IconSizes.medium,
                                  color: Colors.white70,
                                  semanticLabel: l10n.streamExitFullscreen,
                                ),
                              ),
                              IconButton(
                                key: const ValueKey(
                                  'stream-fullscreen-close-button',
                                ),
                                onPressed: onCloseStream,
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: IconSizes.medium,
                                  color: Colors.white70,
                                  semanticLabel: l10n.streamStopWatching,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
