import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/connect/connect_page.dart';
import 'package:flspeak/features/workspace/widgets/server_rail.dart';
import 'package:flspeak/features/workspace/workspace_page.dart';
import 'package:flspeak/features/workspace/workspace_shell.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';

import 'support/stub_session.dart';

/// 布局闸门：极长文案 + 各档窗口宽度 + 放大字号下都不能溢出，
/// 可点区域不能小于可用手指按到的尺寸。
///
/// 溢出在这类测试里会直接抛异常，所以这些用例本身就是「排版没有坏」的证据。
SessionView _stress() => SessionView(
  state: const CoreSessionState_Connected(clientId: 7, channelId: 3),
  servers: const [
    ServerProfileView(
      id: 'extremely-long-host-name-for-stress.example.com:9987',
      label: '一个非常非常长的服务器备注名称用来测试截断行为',
      host: 'extremely-long-host-name-for-stress.example.com',
      port: 9987,
    ),
    ServerProfileView(
      id: 'b:9987',
      label: 'B',
      host: 'b.example.com',
      port: 9987,
    ),
    ServerProfileView(
      id: 'c:9987',
      label: 'C',
      host: 'c.example.com',
      port: 9987,
    ),
    ServerProfileView(
      id: 'd:9987',
      label: 'D',
      host: 'd.example.com',
      port: 9987,
    ),
    ServerProfileView(
      id: 'e:9987',
      label: 'E',
      host: 'e.example.com',
      port: 9987,
    ),
  ],
  activeServerId: 'extremely-long-host-name-for-stress.example.com:9987',
  channels: const [
    ChannelView(id: 1, parentId: 0, name: '一个很长的根频道名称用来测试省略号', description: ''),
    ChannelView(id: 2, parentId: 1, name: '子频道', description: ''),
    ChannelView(id: 3, parentId: 2, name: '另一个很长的频道名称也要被截断掉', description: ''),
    ChannelView(id: 4, parentId: 3, name: '更深一层', description: ''),
    ChannelView(id: 5, parentId: 4, name: '再深一层', description: ''),
    ChannelView(id: 6, parentId: 5, name: '最深一层也没问题吧', description: ''),
  ],
  clients: const [
    ClientView(
      id: 7,
      nickname: '一个非常长的用户昵称同样需要被截断',
      uid: 'uid-1',
      channelId: 3,
    ),
    ClientView(id: 8, nickname: 'alice', uid: 'uid-2', channelId: 3),
    ClientView(id: 9, nickname: 'bob', uid: 'uid-3', channelId: 3),
  ],
  messages: [
    ChatMessage(
      from: 'alice',
      fromUid: 'uid-2',
      text: '一条很长的消息内容，用来确认气泡在窄栏里会换行而不是溢出。' * 3,
      at: DateTime(2026, 10, 8, 21),
      scope: ChatScope.channel,
      targetId: 3,
    ),
    ChatMessage(
      from: '一个非常长的用户昵称同样需要被截断',
      fromUid: 'uid-1',
      text: '短消息',
      at: DateTime(2026, 10, 8, 21, 5),
      scope: ChatScope.channel,
      targetId: 3,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  SessionView view,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionViewProvider.overrideWith(() => StubSessionController(view)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: buildAppTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _workspace() =>
    const WorkspaceShell(location: '/workspace', child: WorkspacePage());

void main() {
  const sizes = <String, Size>{
    '375x812 手机': Size(375, 812),
    '430x860 大手机': Size(430, 860),
    '600x900 窄窗': Size(600, 900),
    '719x900 紧凑断点下沿': Size(719, 900),
    '721x900 紧凑断点上沿': Size(721, 900),
    '1024x768 小桌面': Size(1024, 768),
    '1079x900 宽屏断点下沿': Size(1079, 900),
    '1081x900 宽屏断点上沿': Size(1081, 900),
    '1440x900 桌面': Size(1440, 900),
    '1920x1080 大桌面': Size(1920, 1080),
    '900x600 矮窗': Size(900, 600),
  };

  for (final entry in sizes.entries) {
    testWidgets('工作区在 ${entry.key} 下不溢出', (tester) async {
      await _pump(tester, _workspace(), _stress(), entry.value);
      expect(tester.takeException(), isNull);
    });

    testWidgets('连接界面在 ${entry.key} 下不溢出', (tester) async {
      await _pump(tester, const ConnectPage(), _stress(), entry.value);
      expect(tester.takeException(), isNull);
    });

    testWidgets('昵称步骤在 ${entry.key} 下不溢出', (tester) async {
      await _pump(
        tester,
        const ConnectPage(
          serverId: 'extremely-long-host-name-for-stress.example.com:9987',
        ),
        _stress(),
        entry.value,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('字号放大 $scale 倍后工作区不溢出', (tester) async {
      await _pump(
        tester,
        _workspace(),
        _stress(),
        const Size(1024, 900),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('字号放大 $scale 倍后连接界面不溢出', (tester) async {
      await _pump(
        tester,
        const ConnectPage(),
        _stress(),
        const Size(720, 900),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('宽屏并排三栏，服务器栏可展开', (tester) async {
    await _pump(tester, _workspace(), _stress(), const Size(1440, 900));

    expect(
      tester.getSize(find.byType(ServerRail)).width,
      ServerRail.expandedWidth,
    );
    // 频道栏与聊天栏同时在场。
    expect(find.text('频道'), findsWidgets);
    expect(find.text('聊天'), findsOneWidget);
  });

  testWidgets('窄屏收成图标栏，主区域只剩一栏', (tester) async {
    await _pump(tester, _workspace(), _stress(), const Size(600, 900));

    expect(
      tester.getSize(find.byType(ServerRail)).width,
      ServerRail.collapsedWidth,
    );
    // 标题栏出现「频道 / 聊天」切换，且默认只显示频道栏。
    expect(find.text('聊天'), findsOneWidget);
    expect(find.text('最深一层也没问题吧'), findsOneWidget);
  });

  testWidgets('可点区域：独立控件至少 44，行内次级控件至少 32x40', (tester) async {
    await _pump(tester, _workspace(), _stress(), const Size(1440, 900));

    final offenders = <String>[];
    for (final type in <Type>[
      IconButton,
      FilledButton,
      TextButton,
      OutlinedButton,
      SegmentedButton,
      PopupMenuButton,
      InkWell,
    ]) {
      for (final element in find.byType(type).evaluate()) {
        final box = element.renderObject;
        if (box is! RenderBox || !box.hasSize) {
          continue;
        }
        final interactive = switch (element.widget) {
          InkWell(:final onTap) => onTap != null,
          IconButton(:final onPressed) => onPressed != null,
          FilledButton(:final onPressed) => onPressed != null,
          TextButton(:final onPressed) => onPressed != null,
          OutlinedButton(:final onPressed) => onPressed != null,
          SegmentedButton() => true,
          PopupMenuButton() => true,
          _ => false,
        };
        if (!interactive) {
          continue;
        }

        // 按钮内部的 ink 区域不是落点本身，落点由按钮自己的盒子决定。
        if (element.widget is InkWell && _hasButtonAncestor(element)) {
          continue;
        }

        final inline = _isInsideRowRegion(element);
        final size = box.size;
        final ok = inline
            ? size.width >= 32 && size.height >= 40
            : size.width >= 44 && size.height >= 44;
        if (!ok) {
          offenders.add(
            '${element.widget.runtimeType} '
            '${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}'
            '${inline ? '（行内）' : '（独立）'}',
          );
        }
      }
    }

    expect(offenders, isEmpty, reason: '可点区域过小：$offenders');
  });

  testWidgets('键盘可以直接走到服务器栏的入口', (tester) async {
    await _pump(tester, _workspace(), _stress(), const Size(1440, 900));

    var reachedRail = false;
    for (var step = 0; step < 40 && !reachedRail; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused is! Element) {
        continue;
      }
      reachedRail = _hasAncestorType(focused, ServerRail);
    }

    expect(reachedRail, isTrue, reason: '按 Tab 走不到服务器栏');
  });
}

/// 是否是按钮内部的 ink 区域。这些盒子的尺寸小于按钮落点，不该单独判定。
bool _hasButtonAncestor(Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    final isButton = switch (ancestor.widget) {
      IconButton() => true,
      FilledButton() => true,
      TextButton() => true,
      OutlinedButton() => true,
      SegmentedButton() => true,
      PopupMenuButton() => true,
      _ => false,
    };
    if (isButton) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// 落在列表行里的控件：整行是行的主落点，行内的展开箭头这类次级控件
/// 只需要自己够按（≥32x40，远高于 WCAG 2.5.8 的 24x24 底线），
/// 不必再单独撑到 44x44。
bool _isInsideRowRegion(Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    final rowRegion = switch (widget) {
      InkWell() => true,
      GestureDetector(:final onTap) => onTap != null,
      _ => false,
    };
    if (rowRegion) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

bool _hasAncestorType(Element element, Type type) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget.runtimeType == type) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
