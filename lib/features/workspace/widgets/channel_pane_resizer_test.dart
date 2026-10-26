// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane_resizer.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _paneKey = Key('pane');

/// 铺一个最小三栏：被测的可拖频道栏 + 右侧占满的主区域。
Future<ProviderContainer> _pumpPane(
  WidgetTester tester, {
  double maxWidth = Sizes.channelPanelMax,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 600));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              ChannelPaneResizer(
                maxWidth: maxWidth,
                child: const SizedBox.expand(key: _paneKey),
              ),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(ChannelPaneResizer)),
  );
}

double _paneWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(_paneKey)).width;

/// 拖分隔条 [distance] 像素。先单独走一段把手势竞技场的死区喂掉，
/// 这样后面那一次位移是真被记入的，断言可以和坐标一一对上。
Future<void> _dragHandle(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(ChannelPaneResizer.handleKey)),
  );
  await gesture.moveBy(Offset(distance.sign * kDragSlopDefault, 0));
  await gesture.moveBy(Offset(distance, 0));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('拖动分隔条改频道栏宽度，松手写入偏好', (tester) async {
    final container = await _pumpPane(tester);
    expect(_paneWidth(tester), Sizes.channelPanel);

    await _dragHandle(tester, 60);

    expect(_paneWidth(tester), Sizes.channelPanel + 60);
    expect(
      container.read(preferencesProvider).channelPanelWidth,
      Sizes.channelPanel + 60,
    );
  });

  testWidgets('拖过上限时停在窗口允许的最大宽度', (tester) async {
    final container = await _pumpPane(tester, maxWidth: 320);

    await _dragHandle(tester, 400);

    expect(_paneWidth(tester), 320);
    expect(container.read(preferencesProvider).channelPanelWidth, 320);
  });

  testWidgets('静止时不显示握把，悬停与拖动时浮出', (tester) async {
    await _pumpPane(tester);
    final grip = find.byKey(ChannelPaneResizer.gripKey);
    expect(tester.getSize(grip).height, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    final center = tester.getCenter(find.byKey(ChannelPaneResizer.handleKey));
    await gesture.moveTo(center);
    await tester.pumpAndSettle();

    expect(tester.getSize(grip).width, 3);
    expect(tester.getSize(grip).height, 32);

    await gesture.down(center);
    await gesture.moveBy(const Offset(kDragSlopDefault, 0));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pumpAndSettle();

    expect(tester.getSize(grip).width, 4);
    expect(tester.getSize(grip).height, 48);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('双击恢复默认宽度并清掉偏好', (tester) async {
    final container = await _pumpPane(tester);
    final handle = find.byKey(ChannelPaneResizer.handleKey);

    await _dragHandle(tester, -80);
    expect(
      container.read(preferencesProvider).channelPanelWidth,
      Sizes.channelPanel - 80,
    );

    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(handle);
    await tester.pumpAndSettle();

    expect(_paneWidth(tester), Sizes.channelPanel);
    expect(container.read(preferencesProvider).channelPanelWidth, isNull);
  });

  test('频道栏宽度随 preferences 一起读写', () {
    const prefs = SessionPreferences(nickname: 'n', channelPanelWidth: 321);
    expect(SessionPreferences.fromJson(prefs.toJson()).channelPanelWidth, 321);
    expect(SessionPreferences.fromJson(const {}).channelPanelWidth, isNull);
  });

  test('音频显示声源随 preferences 一起读写', () {
    const prefs = SessionPreferences(
      nickname: 'n',
      voiceMeterSource: VoiceMeterSource.received,
    );
    expect(
      SessionPreferences.fromJson(prefs.toJson()).voiceMeterSource,
      VoiceMeterSource.received,
    );
    expect(
      SessionPreferences.fromJson(const {}).voiceMeterSource,
      VoiceMeterSource.microphone,
    );
  });
}
