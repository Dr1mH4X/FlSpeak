import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/workspace_state.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定快照的控制器：不走 FFI，也不监听事件流。
class _FixedSessionController extends SessionController {
  _FixedSessionController(this.initial);

  final SessionView initial;

  @override
  SessionView build() => initial;
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

Future<void> _pumpPane(WidgetTester tester, SessionView view) async {
  await tester.binding.setSurfaceSize(const Size(480, 800));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionViewProvider.overrideWith(() => _FixedSessionController(view)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChannelPanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('spacer 行与普通频道同尺寸，且点击/选中行为一致', (tester) async {
    final view = SessionView(
      state: const CoreSessionState.connected(clientId: 1, channelId: 0),
      activeServerId: 's1',
      channels: [
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChannelPanel)),
    );

    // 普通频道点击选中。
    await tester.tap(find.text('t2a------- 二次元与日本文化区'));
    // 行上挂着双击加入，单击要等双击判定超时后才派发。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(container.read(selectedChannelProvider)?.channelId, 23);

    // spacer 行同样可点击选中（官方里装饰频道也能进入）。
    await tester.tap(find.text('公 会 大 厅'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(container.read(selectedChannelProvider)?.channelId, 21);
  });

  testWidgets('兜底活动频道跳过 spacer，选第一个普通根频道', (tester) async {
    final view = SessionView(
      state: const CoreSessionState.connected(clientId: 1, channelId: 0),
      activeServerId: 's1',
      channels: [
        _channel(31, order: 0, name: '[*spacer0]==='),
        _channel(32, order: 31, name: '大厅'),
      ],
      clients: [],
    );
    await _pumpPane(tester, view);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChannelPanel)),
    );
    expect(container.read(activeChannelIdProvider), 32);
  });
}
