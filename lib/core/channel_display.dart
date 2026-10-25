import 'package:flspeak_ffi/flspeak_ffi.dart';

/// TeamSpeak 的兄弟频道顺序由 `channel_order` 链表决定：它指向前一个兄弟的
/// 频道 id（0 表示第一个），不是可比较的排序键。沿链表恢复展示顺序；链不完整
/// 的部分（前驱缺失、重复、成环）按服务器给到的输入顺序兜底追加。
List<ChannelView> orderSiblings(List<ChannelView> siblings) {
  final ids = <int>{for (final channel in siblings) channel.id};
  final starts = <ChannelView>[];
  final successors = <int, List<ChannelView>>{};
  for (final channel in siblings) {
    final order = channel.order;
    if (order != null && order != 0 && ids.contains(order)) {
      successors.putIfAbsent(order, () => []).add(channel);
    } else {
      starts.add(channel);
    }
  }

  final out = <ChannelView>[];
  final seen = <int>{};
  // 显式栈代替递归：兄弟上千个的长链不能靠调用栈。
  void emitChain(ChannelView first) {
    final stack = <ChannelView>[first];
    while (stack.isNotEmpty) {
      final channel = stack.removeLast();
      if (!seen.add(channel.id)) {
        continue;
      }
      out.add(channel);
      final followers = successors[channel.id];
      if (followers != null) {
        for (final follower in followers.reversed) {
          stack.add(follower);
        }
      }
    }
  }

  for (final start in starts) {
    emitChain(start);
  }
  for (final channel in siblings) {
    if (!seen.contains(channel.id)) {
      emitChain(channel);
    }
  }
  return out;
}

/// 官方 spacer 频道命名：`[?spacer#]文本`，`?` 是对齐标记 l/c/r/*，
/// `#` 只为保证频道名唯一，可省略；前缀可以叠加。大小写不敏感。
final RegExp _spacerPrefix = RegExp(
  r'^(?:\[(?:(?:c|l|r|\*)?spacer)\d*\]\s*)+',
  caseSensitive: false,
);

final RegExp _spacerMarker = RegExp(
  r'\[([clr*]?)spacer\d*\]',
  caseSensitive: false,
);

/// 官方把纯 run 的这些字符画成线：`_` 实线、`-` 虚线、`.` 点线。
const Set<String> _lineChars = {'-', '_', '.'};

enum SpacerAlign { left, center, right, fill }

class ChannelSpacer {
  const ChannelSpacer({required this.align, required this.text});

  final SpacerAlign align;

  /// 去掉前缀后的显示文本；纯前缀频道为空字符串。
  final String text;

  /// 官方语义里画线而非显示文本的名字（如 `---`、`___`）；单字符不算，
  /// `[rSpacer0].` 这种「空白 spacer」技巧仍按文本显示。
  bool get isLine =>
      text.length >= 3 &&
      text.runes.every(
        (rune) => _lineChars.contains(String.fromCharCode(rune)),
      );
}

/// 识别 spacer 频道；名字不带 spacer 前缀时返回 null。
ChannelSpacer? parseChannelSpacer(String name) {
  final prefix = _spacerPrefix.firstMatch(name);
  if (prefix == null) {
    return null;
  }
  final prefixText = name.substring(prefix.start, prefix.end);
  final markers = _spacerMarker.allMatches(prefixText).toList();
  // 叠加前缀时最后一个标记生效；不带标记的 `[spacer#]` 按左对齐。
  final marker = markers.isEmpty ? '' : (markers.last.group(1) ?? '');
  final align = switch (marker.toLowerCase()) {
    'c' => SpacerAlign.center,
    'r' => SpacerAlign.right,
    '*' => SpacerAlign.fill,
    _ => SpacerAlign.left,
  };
  return ChannelSpacer(align: align, text: name.substring(prefix.end).trim());
}

/// 界面展示用的频道名：spacer 频道剥掉前缀只留正文；名字为空（纯前缀
/// spacer 或服务器给的空名）回退频道 id。频道树与聊天栏共用，避免两边
/// 各写一套过滤。
String channelDisplayName(ChannelView channel) {
  final name = parseChannelSpacer(channel.name)?.text ?? channel.name;
  return name.isEmpty ? channel.id.toString() : name;
}
