// 用例与实现同目录，与应用入口没有引用关系；analyzer 不知道这一点，
// dev_dependency 的 flutter_test 在 lib/ 下会触发 depend_on_referenced_packages。
// ignore_for_file: depend_on_referenced_packages

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/workspace_state.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/features/workspace/widgets/voice_activity_ribbon.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定快照的控制器：不走 FFI，也不监听事件流。
class _FixedSessionController extends SessionController {
  _FixedSessionController(this.initial, {this.moves = true});

  final SessionView initial;

  /// `moveToChannel` 是否被接受；false 模拟密码错误、权限不足这类拒绝。
  final bool moves;

  final joined = <int>[];

  @override
  SessionView build() => initial;

  @override
  Future<bool> joinChannel(int channelId, {String? password}) async {
    joined.add(channelId);
    return moves;
  }
}

ChannelView _channel(
  int id, {
  int parent = 0,
  int? order,
  required String name,
  bool password = false,
}) => ChannelView(
  id: id,
  parentId: parent,
  order: order,
  name: name,
  description: '',
  passwordProtected: password,
);

ClientView _client(int id, String nickname, int channelId) =>
    ClientView(id: id, nickname: nickname, uid: 'uid$id', channelId: channelId);

SessionView _view(
  List<ChannelView> channels, {
  List<ClientView>? clients,
  int selfChannelId = 0,
  Set<int> speaking = const {},
}) => SessionView(
  state: CoreSessionState.connected(clientId: 1, channelId: selfChannelId),
  activeServerId: 's1',
  channels: channels,
  clients: clients ?? [_client(1, '自己', selfChannelId)],
  speaking: speaking,
);

Future<_FixedSessionController> _pumpPane(
  WidgetTester tester,
  SessionView view, {
  bool moves = true,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 800));
  final controller = _FixedSessionController(view, moves: moves);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionViewProvider.overrideWith(() => controller)],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChannelPanel()),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // 说话光环是循环动画，pumpAndSettle 永远等不到静止。
    await tester.pump();
  }
  return controller;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ChannelPanel)));

void main() {
  testWidgets('底部用户卡只留控制按钮与电平条', (tester) async {
    await _pumpPane(tester, _view([_channel(1, name: '大厅')]));

    expect(find.byType(VoiceActivityRibbon), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
    expect(find.text('Offline'), findsNothing);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byIcon(Icons.headphones_rounded), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
  });

  testWidgets('说话状态只由头像表达，并带读屏标签', (tester) async {
    final view = _view(
      [_channel(1, name: '大厅')],
      clients: [_client(1, '自己', 1), _client(2, '张三', 1)],
      selfChannelId: 1,
      speaking: {2},
    );
    await _pumpPane(tester, view, settle: false);

    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '正在说话',
      ),
      findsOneWidget,
    );
  });

  testWidgets('200% 字号下频道树不溢出', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final view = _view(
      [_channel(1, name: '大厅')],
      clients: [_client(1, '自己', 1), _client(2, '张三', 1)],
      selfChannelId: 1,
    );
    await _pumpPane(tester, view);

    expect(tester.takeException(), isNull);
  });

  testWidgets('spacer 行与普通频道同尺寸，且点击/选中行为一致', (tester) async {
    final view = _view(
      [
        _channel(21, order: 0, name: '[cspacer1]公 会 大 厅'),
        _channel(22, order: 21, name: '[*spacer0]-'),
        _channel(23, order: 22, name: 't2a------- 二次元与日本文化区'),
        _channel(24, order: 23, name: '大厅', password: true),
        _channel(25, order: 24, name: '[cspacer0]'),
        _channel(26, parent: 24, order: 0, name: '子频道'),
      ],
      clients: [_client(1, '自己', 0), _client(2, '张三', 24)],
    );
    await _pumpPane(tester, view);

    // 乱序链 + spacer 的整体展示顺序。
    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data!)
        .where((data) => data.isNotEmpty)
        .toList();
    expect(
      names,
      containsAllInOrder(['公 会 大 厅', 't2a------- 二次元与日本文化区', '大厅', '子频道']),
    );

    // spacer 行与普通频道行共用同一个 48 高的行结构，只有名字画法不同。
    SizedBox rowOf(String text) => tester
        .widgetList<SizedBox>(
          find.ancestor(of: find.text(text), matching: find.byType(SizedBox)),
        )
        .firstWhere((box) => box.height == 48);
    expect(rowOf('公 会 大 厅').height, rowOf('大厅').height);

    final container = _container(tester);

    // 普通频道点击选中，且当场生效——不等双击判定窗口。
    await tester.tap(find.text('t2a------- 二次元与日本文化区'));
    await tester.pump();
    expect(container.read(selectedChannelProvider)?.channelId, 23);

    // spacer 行同样可点击选中（官方里装饰频道也能进入）。
    await tester.tap(find.text('公 会 大 厅'));
    await tester.pump();
    expect(container.read(selectedChannelProvider)?.channelId, 21);

    // 两次点击不在同一行，不构成双击，也不该加入频道。
    expect(_joinedChannels(container), isEmpty);
  });

  testWidgets('兜底活动频道跳过 spacer，选第一个普通根频道', (tester) async {
    final view = _view([
      _channel(31, order: 0, name: '[*spacer0]==='),
      _channel(32, order: 31, name: '大厅'),
    ], clients: []);
    await _pumpPane(tester, view);
    expect(_container(tester).read(activeChannelIdProvider), 32);
  });

  testWidgets('双击同一频道：加入一次，高亮与主区域都跟过去', (tester) async {
    final view = _view([
      _channel(41, order: 0, name: '大厅'),
      _channel(42, order: 1, name: '子区'),
    ]);
    final controller = await _pumpPane(tester, view);
    final container = _container(tester);

    // 先单击 41 建立「之前的高亮位置」，再双击 42。
    await tester.tap(find.text('大厅'));
    await tester.pump();
    expect(container.read(activeChannelIdProvider), 41);

    await tester.tap(find.text('子区'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('子区'));
    await tester.pump();

    expect(controller.joined, [42]);
    expect(container.read(selectedChannelProvider)?.channelId, 42);
    expect(container.read(activeChannelIdProvider), 42);
  });

  testWidgets('双击被服务端拒绝时高亮退回原频道', (tester) async {
    final view = _view([
      _channel(51, order: 0, name: '大厅'),
      _channel(52, order: 1, name: '上锁', password: true),
    ]);
    final controller = await _pumpPane(tester, view, moves: false);
    final container = _container(tester);

    await tester.tap(find.text('大厅'));
    await tester.pump();
    await tester.tap(find.text('上锁'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('上锁'));
    await tester.pumpAndSettle();

    expect(controller.joined, [52]);
    expect(container.read(selectedChannelProvider)?.channelId, 51);
    expect(container.read(activeChannelIdProvider), 51);
  });

  testWidgets('双击自己所在的频道不加入，只保持选中', (tester) async {
    final view = _view([_channel(61, order: 0, name: '大厅')], selfChannelId: 61);
    final controller = await _pumpPane(tester, view);
    final container = _container(tester);

    await tester.tap(find.text('大厅'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('大厅'));
    await tester.pump();

    expect(controller.joined, isEmpty);
    expect(container.read(activeChannelIdProvider), 61);
  });

  testWidgets('右键加入：被拒时退回点菜单前的高亮', (tester) async {
    final view = _view([
      _channel(71, order: 0, name: '大厅'),
      _channel(72, order: 1, name: '上锁', password: true),
      _channel(73, order: 2, name: '自己的房间'),
    ], selfChannelId: 73);
    await _pumpPane(tester, view, moves: false);
    final container = _container(tester);

    await tester.tap(find.text('大厅'));
    await tester.pump();
    expect(container.read(activeChannelIdProvider), 71);

    await tester.tap(find.text('上锁'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MenuItemButton));
    await tester.pumpAndSettle();

    // 自己待在 73：回退位置若丢成 null，主区域会落到那里，而不是点菜单前的 71。
    expect(container.read(selectedChannelProvider)?.channelId, 71);
    expect(container.read(activeChannelIdProvider), 71);
  });
}

/// 假控制器记录的加入请求；从容器里取回被测面板使用的那一份。
List<int> _joinedChannels(ProviderContainer container) => (container.read(
  sessionViewProvider.notifier,
) as _FixedSessionController).joined;
