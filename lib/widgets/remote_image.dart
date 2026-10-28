import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/remote_images.dart';
import '../l10n/app_localizations.dart';

/// 聊天、媒体墙和浏览层的图片统一经过 Rust 的地址及传输限制。
class RemoteImage extends ConsumerWidget {
  const RemoteImage({
    required this.url,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.foregroundColor,
    super.key,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(remoteImageProvider(url));
    final l10n = AppLocalizations.of(context);
    final color =
        foregroundColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    Widget loading() => Center(
      child: Semantics(
        label: l10n.chatImageLoading,
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
      ),
    );
    Widget failed() => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_rounded, color: color),
            const SizedBox(height: 8),
            Text(
              l10n.chatImageLoadFailed,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
            const SizedBox(height: 4),
            SelectableText(
              url,
              maxLines: 2,
              style: TextStyle(color: color, fontSize: 12),
            ),
            TextButton.icon(
              onPressed: () => ref.invalidate(remoteImageProvider(url)),
              style: TextButton.styleFrom(foregroundColor: color),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
    return image.when(
      skipLoadingOnRefresh: false,
      data: (bytes) => Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        frameBuilder: (context, child, frame, synchronous) =>
            frame == null ? loading() : child,
        errorBuilder: (context, error, stackTrace) => failed(),
      ),
      loading: loading,
      error: (error, stackTrace) => failed(),
    );
  }
}
