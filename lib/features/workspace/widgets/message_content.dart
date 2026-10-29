import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/remote_image.dart';

/// TS6 官方客户端发图时使用的消息结构。
///
/// 注意：这不是 URL。图片字节在 myTeamSpeak 的附件服务里，`file_id` 只是
/// 官方客户端的引用；没有 myTS 账号/媒体服务时无法下载。
class Ts6Attachment {
  const Ts6Attachment({
    required this.fileId,
    required this.chatUserId,
    required this.fileName,
    required this.fileSize,
    required this.body,
  });

  final String fileId;
  final String chatUserId;
  final String fileName;
  final int fileSize;
  final String body;
}

/// 只解析官方客户端的 `ts.file.myts` JSON；普通文本返回 null。
Ts6Attachment? parseTs6Attachment(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('{') || !trimmed.contains('"msg_type"')) {
    return null;
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    if (decoded['msg_type'] != 'ts.file.myts') {
      return null;
    }
    final fileId = _string(decoded['file_id']);
    final fileName = _string(decoded['file_name']);
    if (fileId.isEmpty || fileName.isEmpty) {
      return null;
    }
    return Ts6Attachment(
      fileId: fileId,
      chatUserId: _string(decoded['chat_user_id']),
      fileName: fileName,
      fileSize: _int(decoded['file_size']),
      body: _string(decoded['body']),
    );
  } on FormatException {
    return null;
  }
}

/// 从一条消息里提取显式的图片 URL。
///
/// 支持 TS6 Markdown 图片、TS3 风格 `[img]...[/img]`，以及整行裸图片 URL。
/// 普通链接不会触发抓取，避免把每条消息都变成网络请求。
String? parseImageUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final markdown = RegExp(r'^!\[[^\]]*\]\(\s*<?(\S+?)>?(?:\s+"[^"]*")?\s*\)$')
      .firstMatch(text);
  if (markdown != null) {
    return _httpImageUrl(markdown.group(1)!);
  }
  final bbcode = RegExp(
    r'^\[img\](.+?)\[/img\]$',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(text);
  if (bbcode != null) {
    return _httpImageUrl(bbcode.group(1)!.trim());
  }
  if (!text.contains('\n')) {
    final url = _httpImageUrl(text);
    if (url != null && _looksLikeImagePath(url)) {
      return url;
    }
  }
  return null;
}

String? _httpImageUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return uri.toString();
}

bool _looksLikeImagePath(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  return RegExp(r'\.(?:png|jpe?g|gif|webp|avif)$').hasMatch(path);
}

String _string(Object? value) => value is String ? value : '';

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

/// 渲染消息与频道内容：纯标准 Markdown + TS6 官方附件占位。
///
/// 前端解耦：不处理任何 BBCode 转换，只接收由 Rust 后端归一化后的标准 Markdown。
class MessageContent extends StatelessWidget {
  const MessageContent({
    required this.text,
    required this.style,
    this.onImageTap,
    super.key,
  });

  final String text;
  final TextStyle style;

  /// 点击正文图片时把 URL 交给上层（例如打开全屏浏览）。
  final ValueChanged<String>? onImageTap;

  @override
  Widget build(BuildContext context) {
    final attachment = parseTs6Attachment(text);
    if (attachment != null) {
      return _AttachmentCard(attachment: attachment, style: style);
    }

    final standaloneImage = parseImageUrl(text);
    if (standaloneImage != null) {
      return _UrlImage(url: standaloneImage, onTap: onImageTap);
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: style,
      code: style.copyWith(
        fontFamily: 'monospace',
        backgroundColor: scheme.surfaceContainerHighest,
        fontSize: (style.fontSize ?? 14) - 1,
      ),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
      a: style.copyWith(
        color: scheme.primary,
        decoration: TextDecoration.underline,
      ),
      h1: style.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      h2: style.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      h3: style.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
      h4: style.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600),
      h5: style.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      h6: style.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
    );

    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: sheet,
      imageBuilder: (uri, title, alt) {
        return _UrlImage(url: uri.toString(), onTap: onImageTap);
      },
    );
  }
}

class _UrlImage extends StatelessWidget {
  const _UrlImage({required this.url, required this.onTap});

  final String url;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final image = RemoteImage(url: url);
    return _ImageFrame(
      child: onTap == null
          ? image
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap!(url),
              child: image,
            ),
    );
  }
}

class _ImageFrame extends StatelessWidget {
  const _ImageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 360),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.medium),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment, required this.style});

  final Ts6Attachment attachment;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.medium),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.image_rounded, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.chatUnsupportedImage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${attachment.fileName} · ${l10n.chatTs6Attachment} · ${_formatBytes(attachment.fileSize)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (attachment.body.isNotEmpty &&
                    attachment.body != attachment.fileName) ...[
                  const SizedBox(height: 4),
                  Text(
                    attachment.body,
                    style: text.bodySmall?.copyWith(color: scheme.onSurface),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  l10n.chatTs6AttachmentPolicy,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}
