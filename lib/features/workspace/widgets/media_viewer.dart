import 'package:flutter/material.dart';

import '../../../core/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/remote_image.dart';
import 'message_content.dart';

/// 全屏浏览层的底色。图片浏览固定用深色底：图片本身的亮暗不可控，只有深底能
/// 保证任何一张图都不会和界面融为一体，所以这里不跟随主题的明暗。
const Color _viewerBackground = Color(0xFF0B0F0E);
const Color _viewerForeground = Colors.white;
const Color _viewerMutedForeground = Color(0xB3FFFFFF);

/// 从一条消息正文里按行提取图片地址；解析规则复用聊天正文的 [parseImageUrl]，
/// 保证媒体页和消息里看到的「哪些内容算图片」完全一致。
List<String> imageUrlsInMessages(Iterable<ChatMessage> messages) {
  final urls = <String>[];
  for (final message in messages) {
    for (final line in message.text.split('\n')) {
      final url = parseImageUrl(line);
      if (url != null) {
        urls.add(url);
      }
    }
  }
  return urls;
}

/// 图片地址末段文件名，作为浏览层的标题；地址没有文件名时退回空串。
String mediaFileName(String url) {
  final uri = Uri.tryParse(url);
  final segments = uri == null
      ? const <String>[]
      : uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (segments.isEmpty) {
    return '';
  }
  return segments.last;
}

/// 打开全屏媒体浏览层。没有任何图片时直接返回，避免打开一个空对话框。
Future<void> showMediaViewer(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) {
  if (urls.isEmpty) {
    return Future<void>.value();
  }
  final disableAnimations = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) =>
        MediaViewer(urls: urls, initialIndex: initialIndex),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// 全屏媒体浏览：顶部标题栏 + 可横向翻页的图片。
///
/// 没有下载入口：当前没有保存文件的 API，放一个点不动的下载按钮比没有更糟。
class MediaViewer extends StatefulWidget {
  const MediaViewer({required this.urls, this.initialIndex = 0, super.key});

  final List<String> urls;
  final int initialIndex;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _goTo(int index) {
    if (index < 0 || index >= widget.urls.length) {
      return;
    }
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      _controller.jumpToPage(index);
      return;
    }
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  String _title(AppLocalizations l10n) {
    final name = mediaFileName(widget.urls[_index]);
    return name.isEmpty ? l10n.mediaViewerTitle : name;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasPrevious = _index > 0;
    final hasNext = _index < widget.urls.length - 1;

    return Material(
      color: _viewerBackground,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: Sizes.header,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _close,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(Sizes.touch, Sizes.touch),
                        foregroundColor: _viewerForeground,
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 24,
                        semanticLabel: l10n.commonClose,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _title(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _viewerForeground,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_index + 1} / ${widget.urls.length}',
                      style: const TextStyle(
                        color: _viewerMutedForeground,
                        fontSize: 14,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  // 点按关闭挂在 PageView 外层：Scrollable 自己不处理 tap，
                  // 外层的 tap 手势会在没有拖动时赢得手势竞技场，拖动仍然翻页。
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: widget.urls.length,
                        onPageChanged: (index) =>
                            setState(() => _index = index),
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          // 图片自己吞掉 tap：原型里只有点空白处才关闭，点图片不关。
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: RemoteImage(
                              url: widget.urls[index],
                              foregroundColor: _viewerForeground,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (hasPrevious)
                    Positioned(
                      left: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ViewerNavButton(
                          label: l10n.mediaPrevious,
                          icon: Icons.chevron_left_rounded,
                          onPressed: () => _goTo(_index - 1),
                        ),
                      ),
                    ),
                  if (hasNext)
                    Positioned(
                      right: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ViewerNavButton(
                          label: l10n.mediaNext,
                          icon: Icons.chevron_right_rounded,
                          onPressed: () => _goTo(_index + 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerNavButton extends StatelessWidget {
  const _ViewerNavButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _viewerForeground.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox.square(
        dimension: 48,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            foregroundColor: _viewerForeground,
            minimumSize: const Size(48, 48),
          ),
          icon: Icon(icon, size: 26, semanticLabel: label),
        ),
      ),
    );
  }
}
