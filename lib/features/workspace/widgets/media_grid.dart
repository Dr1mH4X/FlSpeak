import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/remote_image.dart';
import 'media_viewer.dart';
import '../../../widgets/press_feedback.dart';

/// 频道媒体墙：把聊天里出现过的图片按顺序铺成方格，点击进入全屏浏览。
///
/// 展示已收到的 URL 图片；本地图片由聊天输入框上传。
class MediaGrid extends StatelessWidget {
  const MediaGrid({required this.urls, required this.onOpen, super.key});

  final List<String> urls;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (urls.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_rounded,
              size: 40,
              color: context.scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n.mediaEmpty,
                textAlign: TextAlign.center,
                style: context.texts.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final horizontal = context.isCompact ? 16.0 : 32.0;
    final columns = context.isCompact ? 3 : 4;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 896),
        child: GridView.builder(
          padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: urls.length,
          itemBuilder: (context, index) =>
              _MediaTile(url: urls[index], onTap: () => onOpen(index)),
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final name = mediaFileName(url);
    return Semantics(
      button: true,
      label: name.isEmpty ? l10n.mediaViewerTitle : name,
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: Radii.xxlAll,
        clipBehavior: Clip.antiAlias,
        child: AnimatedInkWell(
          onTap: onTap,
          child: RemoteImage(
            url: url,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
