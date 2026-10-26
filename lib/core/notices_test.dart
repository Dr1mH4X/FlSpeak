// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak/core/notices.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  NoticeCenter center() => container.read(noticeCenterProvider.notifier);
  List<AppNotice> notices() => container.read(noticeCenterProvider);

  test('新提示插到队首', () {
    center()
      ..show('first')
      ..show('second');

    expect(notices().map((notice) => notice.message), ['second', 'first']);
  });

  test('同文案同 tone 去重并刷新 id', () {
    center().show('same');
    final firstId = notices().single.id;

    center().show('same');

    expect(notices(), hasLength(1));
    expect(notices().single.id, isNot(firstId));
  });

  test('不同 tone 是两条提示', () {
    center()
      ..show('message')
      ..show('message', tone: NoticeTone.info);

    expect(notices(), hasLength(2));
  });

  test('超过上限时丢弃最旧的一条', () {
    center()
      ..show('one')
      ..show('two')
      ..show('three')
      ..show('four');

    expect(notices().map((notice) => notice.message), ['four', 'three', 'two']);
  });

  test('dismiss 只移除指定 id', () {
    center()
      ..show('one')
      ..show('two');
    final oldest = notices().last.id;

    center().dismiss(oldest);

    expect(notices().map((notice) => notice.message), ['two']);
  });

  test('空文案与纯空白被忽略', () {
    center()
      ..show('')
      ..show('   ');

    expect(notices(), isEmpty);
  });
}
