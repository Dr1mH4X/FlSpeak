import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/preferences.dart';
import '../../../core/providers.dart';
import '../../../core/stream_publisher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/press_feedback.dart';

/// User selection returned from [showScreenSharePickerDialog].
@immutable
class ScreenSharePickerSelection {
  const ScreenSharePickerSelection({
    required this.sourceId,
    required this.sourceName,
    required this.resolution,
    required this.frameRate,
    this.shareAudio = false,
  });

  final String sourceId;
  final String sourceName;
  final ScreenShareResolutionPreset resolution;
  final ScreenShareFrameRatePreset frameRate;
  final bool shareAudio;
}

/// Opens the desktop screen/window source picker modal and starts screen
/// sharing if the user confirms a selection.
Future<bool> showScreenSharePickerAndStart(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context);
  final selection = await showAppModal<ScreenSharePickerSelection>(
    context,
    title: l10n.streamPickerTitle,
    builder: (_) => const ScreenSharePickerSheet(),
  );
  if (selection == null || !context.mounted) {
    return false;
  }
  return ref
      .read(sessionViewProvider.notifier)
      .startScreenShare(
        sourceId: selection.sourceId,
        sourceName: selection.sourceName,
        resolution: selection.resolution,
        frameRate: selection.frameRate,
        audio: selection.shareAudio,
      );
}

/// Modal body for picking a screen or window to share along with resolution
/// and frame rate presets.
class ScreenSharePickerSheet extends ConsumerStatefulWidget {
  const ScreenSharePickerSheet({super.key});

  @override
  ConsumerState<ScreenSharePickerSheet> createState() =>
      _ScreenSharePickerSheetState();
}

class _ScreenSharePickerSheetState
    extends ConsumerState<ScreenSharePickerSheet> {
  SourceType _activeTab = SourceType.Screen;
  List<DesktopCapturerSource> _sources = const [];
  String? _selectedSourceId;
  bool _loading = true;
  late ScreenShareResolutionPreset _resolution;
  late ScreenShareFrameRatePreset _frameRate;

  static bool get isAudioLoopbackSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(preferencesProvider);
    _resolution = prefs.screenShareResolution;
    _frameRate = prefs.screenShareFrameRate;
    unawaited(_loadSources());
  }

  Future<void> _loadSources() async {
    setState(() => _loading = true);
    try {
      final fetched = await ref
          .read(streamPublisherProvider.notifier)
          .getDesktopSources(
            types: const [SourceType.Screen, SourceType.Window],
            thumbnailSize: ThumbnailSize(320, 180),
          );
      if (!mounted) return;
      setState(() {
        _sources = fetched;
        _loading = false;
        final hasScreen = fetched.any((s) => s.type == SourceType.Screen);
        final hasWindow = fetched.any((s) => s.type == SourceType.Window);
        if (_activeTab == SourceType.Screen && !hasScreen && hasWindow) {
          _activeTab = SourceType.Window;
        } else if (_activeTab == SourceType.Window && !hasWindow && hasScreen) {
          _activeTab = SourceType.Screen;
        }
        _syncSelectedSource();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sources = const [];
        _selectedSourceId = null;
        _loading = false;
      });
    }
  }

  void _syncSelectedSource() {
    final filtered = _filteredSources;
    if (filtered.isEmpty) {
      _selectedSourceId = null;
      return;
    }
    if (_selectedSourceId == null ||
        !filtered.any((s) => s.id == _selectedSourceId)) {
      _selectedSourceId = filtered.first.id;
    }
  }

  List<DesktopCapturerSource> get _filteredSources =>
      _sources.where((s) => s.type == _activeTab).toList(growable: false);

  DesktopCapturerSource? get _selectedSource {
    final id = _selectedSourceId;
    if (id == null) return null;
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  void _switchTab(SourceType tab) {
    if (_activeTab == tab) return;
    setState(() {
      _activeTab = tab;
      _syncSelectedSource();
    });
  }

  void _submit() {
    final source = _selectedSource;
    if (source == null) return;
    Navigator.of(context).pop(
      ScreenSharePickerSelection(
        sourceId: source.id,
        sourceName: source.name,
        resolution: _resolution,
        frameRate: _frameRate,
        shareAudio: isAudioLoopbackSupported,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final filtered = _filteredSources;
    final selected = _selectedSource;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: Radii.mediumAll,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SourceTabButton(
                        key: const ValueKey('screen-share-tab-screens'),
                        icon: Icons.desktop_windows_rounded,
                        label: l10n.streamPickerScreens,
                        selected: _activeTab == SourceType.Screen,
                        onTap: () => _switchTab(SourceType.Screen),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _SourceTabButton(
                        key: const ValueKey('screen-share-tab-windows'),
                        icon: Icons.web_asset_rounded,
                        label: l10n.streamPickerWindows,
                        selected: _activeTab == SourceType.Window,
                        onTap: () => _switchTab(SourceType.Window),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('screen-share-refresh-sources'),
              onPressed: _loading ? null : _loadSources,
              icon: Icon(
                Icons.refresh_rounded,
                size: IconSizes.toolbar,
                semanticLabel: l10n.streamPickerRefresh,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 196, maxHeight: 280),
          child: _loading
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.desktop_access_disabled_rounded,
                          size: 32,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.streamPickerEmpty,
                          textAlign: TextAlign.center,
                          style: context.texts.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.32,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final source = filtered[index];
                    final isSelected = source.id == _selectedSourceId;
                    return _SourceCard(
                      key: ValueKey('screen-source-${source.id}'),
                      source: source,
                      selected: isSelected,
                      onTap: () =>
                          setState(() => _selectedSourceId = source.id),
                    );
                  },
                ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: Radii.largeAll,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.streamPickerResolution,
                    style: context.texts.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final preset in ScreenShareResolutionPreset.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _PresetChip(
                        key: ValueKey('screen-share-res-${preset.id}'),
                        label: preset.id,
                        selected: _resolution == preset,
                        onTap: () => setState(() => _resolution = preset),
                      ),
                    ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.streamPickerFrameRate,
                    style: context.texts.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final preset in ScreenShareFrameRatePreset.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _PresetChip(
                        key: ValueKey('screen-share-fps-${preset.fps}'),
                        label: '${preset.fps} FPS',
                        selected: _frameRate == preset,
                        onTap: () => setState(() => _frameRate = preset),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('screen-share-confirm-start'),
              onPressed: selected == null || _loading ? null : _submit,
              icon: const Icon(
                Icons.screen_share_rounded,
                size: IconSizes.state,
              ),
              label: Text(l10n.streamPickerStart),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _SourceTabButton extends StatelessWidget {
  const _SourceTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.effectsFast,
        curve: Motion.effectsDefaultCurve,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: Radii.smallAll,
        ),
        child: AnimatedInkWell(
          onTap: onTap,
          borderRadius: Radii.smallAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: IconSizes.state,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelMedium?.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final DesktopCapturerSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final thumbnail = source.thumbnail;
    final hasThumbnail = thumbnail != null && thumbnail.isNotEmpty;

    return Semantics(
      button: true,
      selected: selected,
      label: source.name,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.effectsFast,
        curve: Motion.effectsDefaultCurve,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.32)
              : scheme.surfaceContainerLow,
          borderRadius: Radii.mediumAll,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedInkWell(
          onTap: onTap,
          borderRadius: Radii.mediumAll,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: Radii.smallAll,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (hasThumbnail)
                            Image.memory(
                              thumbnail,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => _SourceFallbackIcon(
                                type: source.type,
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          else
                            _SourceFallbackIcon(
                              type: source.type,
                              color: scheme.onSurfaceVariant,
                            ),
                          if (selected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: scheme.onPrimary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

class _SourceFallbackIcon extends StatelessWidget {
  const _SourceFallbackIcon({required this.type, required this.color});

  final SourceType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        type == SourceType.Screen
            ? Icons.desktop_windows_rounded
            : Icons.web_asset_rounded,
        size: 28,
        color: color,
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.effectsFast,
        curve: Motion.effectsDefaultCurve,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: Radii.smallAll,
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
          ),
        ),
        child: AnimatedInkWell(
          onTap: onTap,
          borderRadius: Radii.smallAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              label,
              style: context.texts.labelSmall?.copyWith(
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
