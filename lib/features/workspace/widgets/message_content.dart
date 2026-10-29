import 'dart:convert';

import 'package:flutter/material.dart';

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

/// 渲染聊天正文：TS6 Markdown + 官方附件占位。
///
/// 没有格式的普通文本仍然使用 [SelectableText]，避免破坏现有的查找/测试行为。
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
  /// 为 null 时保持旧的纯展示行为，调用方不需要关心图片交互。
  final ValueChanged<String>? onImageTap;

  @override
  Widget build(BuildContext context) {
    final attachment = parseTs6Attachment(text);
    if (attachment != null) {
      return _AttachmentCard(attachment: attachment, style: style);
    }
    if (parseImageUrl(text) == null && !_looksRich(text)) {
      return SelectableText(text, style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _blocks(context, text, style, onImageTap),
    );
  }
}

bool _looksRich(String text) {
  if (text.contains('\n')) {
    return true;
  }
  return RegExp(
    r'(\*\*|__|\+\+|~~|==|\|\||`|!\[[^\]]*\]\(|\[[^\]]+\]\(|\[img\]|^#|^>|^```|^:::|^\s*(?:[-*+]|\d+\.)\s+|^\|.*\|)',
    multiLine: true,
  ).hasMatch(text);
}

class _Palette {
  const _Palette({
    required this.link,
    required this.codeBackground,
    required this.highlight,
    required this.spoilerBackground,
    required this.muted,
    required this.outline,
  });

  factory _Palette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _Palette(
      link: scheme.primary,
      codeBackground: scheme.surfaceContainerHighest,
      // ==mark== 高亮：亮色沿用琥珀 40% 叠底（正文是深色，对比足够）；
      // 暗色下浅字浅底会崩，换成深琥珀实底，onSurface 对比仍在 7:1 以上。
      highlight: isDark ? const Color(0xFF514714) : const Color(0x66FFD54F),
      spoilerBackground: scheme.surfaceContainerHighest,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant,
    );
  }

  final Color link;
  final Color codeBackground;
  final Color highlight;
  final Color spoilerBackground;
  final Color muted;
  final Color outline;
}

List<Widget> _blocks(
  BuildContext context,
  String text,
  TextStyle style,
  ValueChanged<String>? onImageTap,
) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final palette = _Palette.of(context);
  final widgets = <Widget>[];
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];
    if (line.trim().isEmpty) {
      index++;
      continue;
    }

    final imageUrl = parseImageUrl(line);
    if (imageUrl != null) {
      widgets.add(_UrlImage(url: imageUrl, onTap: onImageTap));
      index++;
      continue;
    }

    final fence = RegExp(r'^```(.*)$').firstMatch(line);
    if (fence != null) {
      final code = <String>[];
      index++;
      while (index < lines.length && !lines[index].startsWith('```')) {
        code.add(lines[index]);
        index++;
      }
      if (index < lines.length) {
        index++;
      }
      widgets.add(_codeBlock(context, code.join('\n'), style));
      continue;
    }

    final trimmedLeft = line.trimLeft();
    if (trimmedLeft.startsWith(':::details')) {
      final summary = trimmedLeft.substring(':::details'.length).trim();
      final body = <String>[];
      index++;
      while (index < lines.length && lines[index].trim() != ':::') {
        body.add(lines[index]);
        index++;
      }
      if (index < lines.length) {
        index++;
      }
      widgets.add(
        _detailsBlock(
          context,
          summary.isEmpty ? 'Details' : summary,
          body.join('\n'),
          style,
          onImageTap,
        ),
      );
      continue;
    }

    if (trimmedLeft.startsWith(':::left')) {
      final body = <String>[];
      index++;
      while (index < lines.length && lines[index].trim() != ':::') {
        body.add(lines[index]);
        index++;
      }
      if (index < lines.length) {
        index++;
      }
      widgets.add(
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: _blocks(context, body.join('\n'), style, onImageTap),
          ),
        ),
      );
      continue;
    }

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final size = switch (level) {
        1 => 22.0,
        2 => 19.0,
        3 => 17.0,
        _ => 15.5,
      };
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: _rich(
            context,
            heading.group(2)!,
            style.copyWith(fontSize: size, fontWeight: FontWeight.w700),
            palette,
          ),
        ),
      );
      index++;
      continue;
    }

    if (RegExp(r'^\s*(?:---|\*\*\*|___)\s*$').hasMatch(line)) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: palette.outline),
        ),
      );
      index++;
      continue;
    }

    if (trimmedLeft.startsWith('>')) {
      final quote = <String>[];
      while (index < lines.length && lines[index].trimLeft().startsWith('>')) {
        quote.add(lines[index].trimLeft().substring(1).trimLeft());
        index++;
      }
      widgets.add(
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: palette.link, width: 3)),
          ),
          child: _rich(
            context,
            quote.join('\n'),
            style.copyWith(color: palette.muted, fontStyle: FontStyle.italic),
            palette,
          ),
        ),
      );
      continue;
    }

    if (_isTableStart(lines, index)) {
      final rows = <List<String>>[];
      while (index < lines.length && _isTableRow(lines[index])) {
        if (!_isTableSeparator(lines[index])) {
          rows.add(_tableCells(lines[index]));
        }
        index++;
      }
      if (rows.isNotEmpty) {
        widgets.add(_table(context, rows, style, palette));
        continue;
      }
    }

    if (RegExp(r'^\s*(?:[-*+]|\d+\.)\s+').hasMatch(line)) {
      final items = <(String, String)>[];
      while (index < lines.length) {
        final match = RegExp(r'^\s*([-*+]|\d+\.)\s+(.*)$')
            .firstMatch(lines[index]);
        if (match == null) {
          break;
        }
        items.add((match.group(1)!, match.group(2)!));
        index++;
      }
      widgets.add(_list(context, items, style, palette));
      continue;
    }

    final paragraph = <String>[];
    while (index < lines.length && !_isBlockStart(lines, index)) {
      paragraph.add(lines[index]);
      index++;
    }
    if (paragraph.isEmpty) {
      index++;
      continue;
    }
    widgets.add(_rich(context, paragraph.join('\n'), style, palette));
  }

  return widgets;
}

bool _isBlockStart(List<String> lines, int index) {
  final line = lines[index];
  if (line.trim().isEmpty) {
    return true;
  }
  if (parseImageUrl(line) != null) {
    return true;
  }
  if (line.trimLeft().startsWith('```') ||
      line.trimLeft().startsWith(':::') ||
      line.trimLeft().startsWith('>')) {
    return true;
  }
  if (RegExp(r'^(#{1,6})\s+').hasMatch(line) ||
      RegExp(r'^\s*(?:---|\*\*\*|___)\s*$').hasMatch(line) ||
      RegExp(r'^\s*(?:[-*+]|\d+\.)\s+').hasMatch(line)) {
    return true;
  }
  return _isTableStart(lines, index);
}

bool _isTableRow(String line) {
  final trimmed = line.trim();
  return trimmed.length >= 2 &&
      trimmed.startsWith('|') &&
      trimmed.endsWith('|');
}

bool _isTableSeparator(String line) {
  final cells = _tableCells(line);
  return cells.isNotEmpty &&
      cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.trim()));
}

bool _isTableStart(List<String> lines, int index) {
  return index + 1 < lines.length &&
      _isTableRow(lines[index]) &&
      _isTableSeparator(lines[index + 1]);
}

List<String> _tableCells(String line) {
  var trimmed = line.trim();
  if (trimmed.startsWith('|')) {
    trimmed = trimmed.substring(1);
  }
  if (trimmed.endsWith('|')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed.split('|').map((cell) => cell.trim()).toList();
}

Widget _table(
  BuildContext context,
  List<List<String>> rows,
  TextStyle style,
  _Palette palette,
) {
  final columns = rows
      .map((row) => row.length)
      .fold<int>(0, (a, b) => a > b ? a : b);
  if (columns == 0 || columns > 6) {
    return _rich(
      context,
      rows.map((row) => row.join(' | ')).join('\n'),
      style,
      palette,
    );
  }
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(color: palette.outline),
      children: [
        for (final row in rows)
          TableRow(
            children: [
              for (var i = 0; i < columns; i++)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: _rich(
                    context,
                    i < row.length ? row[i] : '',
                    i == 0
                        ? style.copyWith(fontWeight: FontWeight.w600)
                        : style,
                    palette,
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

Widget _list(
  BuildContext context,
  List<(String, String)> items,
  TextStyle style,
  _Palette palette,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (marker, item) in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  marker.endsWith('.') ? marker : '•',
                  style: style.copyWith(color: palette.muted),
                ),
              ),
              Expanded(child: _rich(context, item, style, palette)),
            ],
          ),
        ),
    ],
  );
}

Widget _detailsBlock(
  BuildContext context,
  String summary,
  String body,
  TextStyle style,
  ValueChanged<String>? onImageTap,
) {
  return Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
      title: Text(summary, style: style.copyWith(fontWeight: FontWeight.w600)),
      children: _blocks(context, body, style, onImageTap),
    ),
  );
}

Widget _codeBlock(BuildContext context, String code, TextStyle style) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(Radii.small),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText(
        code,
        style: style.copyWith(
          fontFamily: 'monospace',
          fontSize: (style.fontSize ?? 14) - 1,
        ),
      ),
    ),
  );
}

Widget _rich(
  BuildContext context,
  String text,
  TextStyle style,
  _Palette palette,
) {
  return SelectableText.rich(
    TextSpan(style: style, children: _inline(context, text, style, palette)),
    style: style,
  );
}

List<InlineSpan> _inline(
  BuildContext context,
  String text,
  TextStyle style,
  _Palette palette, {
  int depth = 0,
}) {
  if (depth > 8 || text.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  var index = 0;

  void flush() {
    if (buffer.isEmpty) {
      return;
    }
    spans.add(TextSpan(text: buffer.toString(), style: style));
    buffer.clear();
  }

  while (index < text.length) {
    final rest = text.substring(index);

    if (rest.startsWith('`')) {
      final end = text.indexOf('`', index + 1);
      if (end > index) {
        flush();
        spans.add(
          TextSpan(
            text: text.substring(index + 1, end),
            style: style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: palette.codeBackground,
            ),
          ),
        );
        index = end + 1;
        continue;
      }
    }

    if (rest.startsWith('**')) {
      final end = text.indexOf('**', index + 2);
      if (end > index + 2) {
        flush();
        spans.addAll(
          _inline(
            context,
            text.substring(index + 2, end),
            style.copyWith(fontWeight: FontWeight.w700),
            palette,
            depth: depth + 1,
          ),
        );
        index = end + 2;
        continue;
      }
    }

    if (rest.startsWith('++')) {
      final end = text.indexOf('++', index + 2);
      if (end > index + 2) {
        flush();
        spans.addAll(
          _inline(
            context,
            text.substring(index + 2, end),
            style.copyWith(decoration: TextDecoration.underline),
            palette,
            depth: depth + 1,
          ),
        );
        index = end + 2;
        continue;
      }
    }

    if (rest.startsWith('~~')) {
      final end = text.indexOf('~~', index + 2);
      if (end > index + 2) {
        flush();
        spans.addAll(
          _inline(
            context,
            text.substring(index + 2, end),
            style.copyWith(decoration: TextDecoration.lineThrough),
            palette,
            depth: depth + 1,
          ),
        );
        index = end + 2;
        continue;
      }
    }

    if (rest.startsWith('==')) {
      final end = text.indexOf('==', index + 2);
      if (end > index + 2) {
        flush();
        spans.addAll(
          _inline(
            context,
            text.substring(index + 2, end),
            style.copyWith(backgroundColor: palette.highlight),
            palette,
            depth: depth + 1,
          ),
        );
        index = end + 2;
        continue;
      }
    }

    if (rest.startsWith('||')) {
      final end = text.indexOf('||', index + 2);
      if (end > index + 2) {
        flush();
        spans.add(
          TextSpan(
            text: text.substring(index + 2, end),
            style: style.copyWith(
              color: palette.spoilerBackground,
              backgroundColor: palette.spoilerBackground,
            ),
          ),
        );
        index = end + 2;
        continue;
      }
    }

    final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)').firstMatch(rest);
    if (link != null) {
      flush();
      spans.add(
        TextSpan(
          text: link.group(1),
          style: style.copyWith(
            color: palette.link,
            decoration: TextDecoration.underline,
          ),
        ),
      );
      index += link.group(0)!.length;
      continue;
    }

    if (rest.startsWith(r'$')) {
      final end = text.indexOf(r'$', index + 1);
      if (end > index + 1) {
        flush();
        spans.add(
          TextSpan(
            text: text.substring(index + 1, end),
            style: style.copyWith(
              fontFamily: 'monospace',
              fontStyle: FontStyle.italic,
            ),
          ),
        );
        index = end + 1;
        continue;
      }
    }

    if (rest.startsWith('*') && !rest.startsWith('**')) {
      final end = text.indexOf('*', index + 1);
      if (end > index + 1) {
        flush();
        spans.addAll(
          _inline(
            context,
            text.substring(index + 1, end),
            style.copyWith(fontStyle: FontStyle.italic),
            palette,
            depth: depth + 1,
          ),
        );
        index = end + 1;
        continue;
      }
    }

    final emoji = RegExp(r'^:([A-Za-z0-9_+\-]+):').firstMatch(rest);
    if (emoji != null) {
      final glyph = _emoji[emoji.group(1)];
      if (glyph != null) {
        flush();
        spans.add(TextSpan(text: glyph, style: style));
        index += emoji.group(0)!.length;
        continue;
      }
    }

    final url = RegExp(r'^(?:https?://|www\.)[^\s<>\[\]]+').firstMatch(rest);
    if (url != null) {
      flush();
      spans.add(
        TextSpan(
          text: url.group(0),
          style: style.copyWith(
            color: palette.link,
            decoration: TextDecoration.underline,
          ),
        ),
      );
      index += url.group(0)!.length;
      continue;
    }

    final length = _nextCharLength(text, index);
    buffer.write(text.substring(index, index + length));
    index += length;
  }

  flush();
  return spans;
}

int _nextCharLength(String text, int index) {
  final unit = text.codeUnitAt(index);
  if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) {
    return 2;
  }
  return 1;
}

const _emoji = <String, String>{
  '+1': '👍',
  '-1': '👎',
  'smile': '😄',
  'heart': '❤️',
  'rocket': '🚀',
  'tada': '🎉',
  'fire': '🔥',
  'eyes': '👀',
  'thinking': '🤔',
  'wave': '👋',
  'clap': '👏',
  'joy': '😂',
  'cry': '😢',
  'angry': '😠',
  'sunglasses': '😎',
};

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
