import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/channel_icons.dart';
import '../core/providers.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'expressive_frame.dart';

class ChannelIcon extends ConsumerWidget {
  const ChannelIcon({this.iconId, required this.color, super.key});

  final int? iconId;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = iconId;
    if (id == null || id == 0) {
      return ExpressiveFrame(
        size: 28,
        color: color.withValues(alpha: 0.08),
        child: Icon(
          Icons.volume_up_outlined,
          size: IconSizes.medium,
          color: color,
        ),
      );
    }
    final data = ref.watch(channelIconProvider(id));
    final session = ref.watch(
      sessionViewProvider.select(
        (view) => (view.activeServerId, view.connectionEpoch),
      ),
    );
    return _IconImage(
      key: ValueKey((session, id)),
      data: data,
      color: color,
      seed: id,
      onRetry: () => ref.invalidate(channelIconProvider(id)),
    );
  }
}

class _IconImage extends StatefulWidget {
  const _IconImage({
    required this.data,
    required this.color,
    required this.seed,
    required this.onRetry,
    super.key,
  });

  final AsyncValue<Uint8List> data;
  final Color color;
  final int seed;
  final VoidCallback onRetry;

  @override
  State<_IconImage> createState() => _IconImageState();
}

class _IconImageState extends State<_IconImage> {
  bool _decoded = false;
  bool _decodeFailed = false;
  Uint8List? _bytes;

  void _finishDecode(bool failed) {
    if (_decoded || _decodeFailed) return;
    final bytes = _bytes;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(bytes, _bytes) && !_decoded && !_decodeFailed) {
        setState(() {
          _decoded = !failed;
          _decodeFailed = failed;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.data.isLoading ? null : widget.data.asData?.value;
    if (!identical(bytes, _bytes)) {
      _bytes = bytes;
      _decoded = false;
      _decodeFailed = false;
    }
    final failed =
        (!widget.data.isLoading && widget.data.hasError) || _decodeFailed;
    final fallback = Icon(
      failed ? Icons.refresh_rounded : Icons.volume_up_outlined,
      size: IconSizes.medium,
      color: widget.color,
    );
    final content = bytes == null || _decodeFailed
        ? fallback
        : Image.memory(
            bytes,
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            cacheWidth: 64,
            cacheHeight: 64,
            excludeFromSemantics: true,
            frameBuilder: (context, child, frame, synchronous) {
              if (frame != null || synchronous) _finishDecode(false);
              return frame == null ? fallback : child;
            },
            errorBuilder: (context, error, stack) {
              _finishDecode(true);
              return fallback;
            },
          );
    return Semantics(
      button: failed,
      label: failed ? AppLocalizations.of(context).channelIconRetry : null,
      child: GestureDetector(
        onTap: failed ? widget.onRetry : null,
        child: ExpressiveFrame(
          size: 28,
          color: widget.color.withValues(alpha: 0.08),
          shapeSeed: widget.seed,
          loading: !failed && (widget.data.isLoading || !_decoded),
          child: content,
        ),
      ),
    );
  }
}
