// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak/core/channel_display.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

ChannelView _channel(int id, {int? order, String name = ''}) => ChannelView(
  id: id,
  parentId: 0,
  order: order,
  name: name.isEmpty ? '频道$id' : name,
  description: '',
);

void main() {
  group('orderSiblings', () {
    test('沿前驱链表恢复顺序，与输入顺序无关', () {
      final ordered = orderSiblings([
        _channel(12, order: 3),
        _channel(3, order: 9),
        _channel(9, order: 0),
      ]);
      expect(ordered.map((c) => c.id), [9, 3, 12]);
    });

    test('order 为 0、null 或指向缺失频道时都当链首', () {
      final ordered = orderSiblings([
        _channel(5, order: 4), // 4 不在兄弟里
        _channel(7, order: 0),
        _channel(6),
        _channel(8, order: 5),
      ]);
      expect(ordered.map((c) => c.id), [5, 8, 7, 6]);
    });

    test('同一个前驱被多个频道认领时按输入序紧随其后', () {
      final ordered = orderSiblings([
        _channel(3, order: 1),
        _channel(1, order: 0),
        _channel(2, order: 1),
      ]);
      expect(ordered.map((c) => c.id), [1, 3, 2]);
    });

    test('成环的兄弟按输入序兜底', () {
      final ordered = orderSiblings([
        _channel(5, order: 4),
        _channel(4, order: 5),
      ]);
      expect(ordered.map((c) => c.id), [5, 4]);
    });

    test('链首后面的环接到已排部分之后', () {
      final ordered = orderSiblings([
        _channel(3, order: 2),
        _channel(1, order: 0),
        _channel(2, order: 3),
      ]);
      expect(ordered.map((c) => c.id), [1, 3, 2]);
    });

    test('order 指向自己不丢频道', () {
      final ordered = orderSiblings([_channel(7, order: 7)]);
      expect(ordered.map((c) => c.id), [7]);
    });

    test('空列表返回空', () {
      expect(orderSiblings(const []), isEmpty);
    });
  });

  group('parseChannelSpacer', () {
    test('c/l/r/* 四种对齐', () {
      expect(parseChannelSpacer('[cspacer0]欢迎')!.align, SpacerAlign.center);
      expect(parseChannelSpacer('[lspacer1]欢迎')!.align, SpacerAlign.left);
      expect(parseChannelSpacer('[rspacer2]欢迎')!.align, SpacerAlign.right);
      expect(parseChannelSpacer('[*spacer3]欢迎')!.align, SpacerAlign.fill);
    });

    test('大小写混合的前缀', () {
      final spacer = parseChannelSpacer('[cSpacer14]Hello');
      expect(spacer, isNotNull);
      expect(spacer!.align, SpacerAlign.center);
      expect(spacer.text, 'Hello');
    });

    test('不带对齐标记的 [spacer] 按左对齐', () {
      final spacer = parseChannelSpacer('[spacer5]x');
      expect(spacer!.align, SpacerAlign.left);
      expect(spacer.text, 'x');
    });

    test('叠加前缀取最后一个标记，文本只留正文', () {
      final spacer = parseChannelSpacer('[cspacer][cspacer1] hi ');
      expect(spacer!.align, SpacerAlign.center);
      expect(spacer.text, 'hi');
    });

    test('纯前缀频道文本为空', () {
      expect(parseChannelSpacer('[cspacer0]')!.text, isEmpty);
      expect(parseChannelSpacer('[cspacer0]   ')!.text, isEmpty);
    });

    test('普通名字不是 spacer，裸线也不是', () {
      expect(parseChannelSpacer('普通频道'), isNull);
      expect(parseChannelSpacer('---'), isNull);
    });

    test('官方画线字符的纯 run 才算线，单字符仍按文本', () {
      expect(parseChannelSpacer('[cspacer0]---')!.isLine, isTrue);
      expect(parseChannelSpacer('[cspacer0]___')!.isLine, isTrue);
      expect(parseChannelSpacer('[cspacer0]...')!.isLine, isTrue);
      expect(parseChannelSpacer('[cspacer0].-.')!.isLine, isTrue);
      expect(parseChannelSpacer('[cspacer0]--')!.isLine, isFalse);
      expect(parseChannelSpacer('[cspacer0]===')!.isLine, isFalse);
      expect(parseChannelSpacer('[rSpacer0].')!.isLine, isFalse);
      expect(parseChannelSpacer('[cspacer0]频-道')!.isLine, isFalse);
    });
  });

  group('channelDisplayName', () {
    test('spacer 频道剥前缀，普通频道原名', () {
      expect(channelDisplayName(_channel(7, name: '[cspacer1]大厅')), '大厅');
      expect(channelDisplayName(_channel(8, name: '游戏房')), '游戏房');
    });

    test('空名与纯前缀 spacer 回退频道 id', () {
      expect(channelDisplayName(_channel(9, name: '[cspacer0]')), '9');
      // helper 会给空名填默认值，这里直接构造真正的空名。
      expect(
        channelDisplayName(
          const ChannelView(id: 10, parentId: 0, name: '', description: ''),
        ),
        '10',
      );
    });
  });
}
