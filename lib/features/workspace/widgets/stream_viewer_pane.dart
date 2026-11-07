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
import '../../../widgets/pane_resizer.dart';

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

    final remoteStreams = view.streams
        .where(
          (s) =>
              (!publisher.isActive || s.id != publisher.streamId) &&
              (view.selfClientId == null || s.clientId != view.selfClientId),
        )
        .toList(growable: false);

    final hasActiveRemoteInList =
        activeStreamId != null &&
        remoteStreams.any((s) => s.id == activeStreamId);

    final hasRemoteWatching = viewer.isActive || activeStreamId != null;
    final hasPublisherExpanded =
        publisher.isActive &&
        publisher.isPreviewExpanded &&
        publisher.renderer != null;
    final hasExpandedVideo = hasRemoteWatching || hasPublisherExpanded;

    final hasAnyStream =
        publisher.isActive ||
        remoteStreams.isNotEmpty ||
        (hasRemoteWatching && !hasActiveRemoteInList);
    if (!hasAnyStream) {
      return const SizedBox.shrink();
    }

    final viewportHeight = MediaQuery.sizeOf(context).height;
    const reservedWorkspaceSpace = 220.0;
    const minStageHeight = 100.0;
    const cardOverhead = 86.0;
    const handleThickness = 8.0;

    final maxSectionHeight = math.max(
      minStageHeight + cardOverhead + handleThickness,
      viewportHeight - reservedWorkspaceSpace,
    );
    final maxStageHeight = math.max(
      minStageHeight,
      maxSectionHeight - cardOverhead - handleThickness,
    );
    final defaultStageHeight = math.min(
      216.0,
      math.max(minStageHeight, (viewportHeight - 290.0) * 0.45),
    );

    final storedHeight = ref.watch(
      preferencesProvider.select((p) => p.streamViewerHeight),
    );
    final effectiveStageHeight = storedHeight != null
        ? storedHeight.clamp(minStageHeight, maxStageHeight)
        : defaultStageHeight;

    List<Widget> buildStreamChildren(double currentStageHeight) {
      final children = <Widget>[];

      if (publisher.isActive) {
        children.add(
          _StreamPublisherBanner(
            publisher: publisher,
            stageHeight: currentStageHeight,
          ),
        );
      }

      if (hasRemoteWatching && !hasActiveRemoteInList) {
        final fallbackStream = StreamView(
          id: activeStreamId ?? viewer.streamId ?? '',
          clientId: viewer.sourceClientId ?? 0,
          name: '',
          hasAudio: true,
        );
        children.add(
          _RemoteStreamBanner(
            key: ValueKey('stream-remote-${fallbackStream.id}'),
            view: view,
            stream: fallbackStream,
            viewer: viewer,
            isWatching: true,
            stageHeight: currentStageHeight,
          ),
        );
      }

      for (final stream in remoteStreams) {
        final isWatching = hasRemoteWatching && stream.id == activeStreamId;
        children.add(
          _RemoteStreamBanner(
            key: ValueKey('stream-remote-${stream.id}'),
            view: view,
            stream: stream,
            viewer: viewer,
            isWatching: isWatching,
            stageHeight: currentStageHeight,
          ),
        );
      }

      return children;
    }

    if (!hasExpandedVideo) {
      final children = buildStreamChildren(effectiveStageHeight);
      final Widget content = children.length == 1
          ? children.single
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            );
      return SingleChildScrollView(clipBehavior: Clip.hardEdge, child: content);
    }

    final l10n = AppLocalizations.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSectionHeight),
      child: PaneResizer(
        axis: Axis.vertical,
        size: effectiveStageHeight,
        minSize: minStageHeight,
        maxSize: maxStageHeight,
        defaultSize: defaultStageHeight,
        handleThickness: handleThickness,
        handleKey: const ValueKey('stream-viewer-resize-handle'),
        gripKey: const ValueKey('stream-viewer-resize-grip'),
        semanticLabel: l10n.streamViewerResize,
        onSizeChanged: (height) {
          ref.read(preferencesProvider.notifier).setStreamViewerHeight(height);
        },
        onReset: () {
          ref.read(preferencesProvider.notifier).setStreamViewerHeight(null);
        },
        builder: (context, currentHeight) {
          final children = buildStreamChildren(currentHeight);
          if (children.isEmpty) {
            return const SizedBox.shrink();
          }
          final Widget content = children.length == 1
              ? children.single
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                );
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(64.0, maxSectionHeight - handleThickness),
            ),
            child: SingleChildScrollView(
              clipBehavior: Clip.hardEdge,
              child: content,
            ),
          );
        },
      ),
    );
  }
}

/// Common banner container reused for both self-screen-share (publisher)
/// and remote-screen-share (viewer / subscriber).
class _StreamBanner extends StatelessWidget {
  const _StreamBanner({
    this.containerKey,
    required this.title,
    this.badge,
    required this.actions,
    this.error,
    this.content,
    this.contentHeight,
  });

  final Key? containerKey;
  final String title;
  final Widget? badge;
  final List<Widget> actions;
  final Widget? error;
  final Widget? content;
  final double? contentHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: AnimatedContainer(
        key: containerKey,
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
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (badge != null) ...[const SizedBox(width: 8), badge!],
                  for (final action in actions) ...[
                    const SizedBox(width: 4),
                    action,
                  ],
                ],
              ),
            ),
            ?error,
            if (content != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: ClipRRect(
                  borderRadius: Radii.mediumAll,
                  child: SizedBox(height: contentHeight, child: content!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StreamPublisherBanner extends ConsumerWidget {
  const _StreamPublisherBanner({required this.publisher, this.stageHeight});

  final StreamPublisherState publisher;
  final double? stageHeight;

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
    final previewHeight =
        stageHeight ??
        math.min(216.0, math.max(100.0, (viewportHeight - 290.0) * 0.45));

    return _StreamBanner(
      containerKey: const ValueKey('stream-publisher-banner'),
      title: '${l10n.streamPublishing} · $sourceLabel',
      badge: Container(
        key: const ValueKey('stream-publisher-viewer-count'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      actions: [
        if (renderer != null)
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
      error: publisher.viewerFailure != null
          ? Padding(
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
            )
          : null,
      contentHeight: previewHeight,
      content: publisher.isPreviewExpanded && renderer != null
          ? DecoratedBox(
              key: const ValueKey('stream-publisher-preview-stage'),
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
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  );
                },
              ),
            )
          : null,
    );
  }
}

class _RemoteStreamBanner extends ConsumerStatefulWidget {
  const _RemoteStreamBanner({
    super.key,
    required this.view,
    required this.stream,
    required this.viewer,
    required this.isWatching,
    this.stageHeight,
  });

  final SessionView view;
  final StreamView stream;
  final StreamViewerState viewer;
  final bool isWatching;
  final double? stageHeight;

  @override
  ConsumerState<_RemoteStreamBanner> createState() =>
      _RemoteStreamBannerState();
}

class _RemoteStreamBannerState extends ConsumerState<_RemoteStreamBanner> {
  final OverlayPortalController _overlayController = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _syncOverlay(widget.isWatching && widget.viewer.isFullScreen);
  }

  @override
  void didUpdateWidget(covariant _RemoteStreamBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fullScreen = widget.isWatching && widget.viewer.isFullScreen;
    final oldFullScreen = oldWidget.isWatching && oldWidget.viewer.isFullScreen;
    if (fullScreen != oldFullScreen) {
      _syncOverlay(fullScreen);
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
    final stream = widget.stream;
    final viewer = widget.viewer;
    final isWatching = widget.isWatching;
    final publisherName = _resolvePublisherName(
      view: widget.view,
      stream: stream,
      fallbackClientId: viewer.sourceClientId,
    );

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final stageHeight =
        widget.stageHeight ??
        math.min(216.0, math.max(100.0, (viewportHeight - 290.0) * 0.45));

    final title = isWatching
        ? '${l10n.streamWatching} · $publisherName'
        : '$publisherName · ${l10n.streamSharing}';

    final actions = isWatching
        ? <Widget>[
            IconButton(
              key: const ValueKey('stream-mute-toggle'),
              onPressed: viewerController.toggleMuted,
              icon: Icon(
                viewer.isMuted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                size: IconSizes.medium,
                color: viewer.isMuted ? scheme.error : scheme.onSurfaceVariant,
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
                  sessionController.leaveStream(viewer.streamId ?? stream.id),
              icon: Icon(
                Icons.close_rounded,
                size: IconSizes.medium,
                color: scheme.onSurfaceVariant,
                semanticLabel: l10n.streamStopWatching,
              ),
            ),
          ]
        : <Widget>[
            IconButton(
              key: ValueKey('stream-watch-${stream.id}'),
              onPressed: () => sessionController.watchStream(stream),
              icon: Icon(
                Icons.visibility_rounded,
                size: IconSizes.medium,
                color: scheme.onSurfaceVariant,
                semanticLabel: l10n.streamWatch,
              ),
            ),
          ];

    final banner = _StreamBanner(
      containerKey: isWatching
          ? const ValueKey('stream-viewer-stage')
          : ValueKey('stream-banner-${stream.id}'),
      title: title,
      actions: actions,
      contentHeight: isWatching && !viewer.isFullScreen ? stageHeight : null,
      content: isWatching && !viewer.isFullScreen
          ? _StreamVideoCanvas(
              renderer: viewer.renderer,
              viewer: viewer,
              connectingLabel: l10n.streamConnecting,
            )
          : null,
    );

    return OverlayPortal(
      controller: _overlayController,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (overlayContext) => _StreamFullscreenStage(
        viewer: viewer,
        publisherName: publisherName,
        onToggleMute: () => unawaited(viewerController.toggleMuted()),
        onExitFullScreen: () =>
            unawaited(viewerController.setFullScreen(false)),
        onCloseStream: () => unawaited(
          sessionController.leaveStream(viewer.streamId ?? stream.id),
        ),
      ),
      child: banner,
    );
  }

  static String _resolvePublisherName({
    required SessionView view,
    required StreamView? stream,
    required int? fallbackClientId,
  }) {
    final clientId = (stream != null && stream.clientId != 0)
        ? stream.clientId
        : fallbackClientId;
    if (clientId != null && clientId != 0) {
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
