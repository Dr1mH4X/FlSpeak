import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/network_quality.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/features/workspace/widgets/network_status.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';
import 'package:flspeak/widgets/signal_ribbon.dart';

NetworkTelemetry _sample({
  double? latency = 30,
  double failure = 0,
  double? lossIn = 0,
  double? lossOut = 0,
  int? idleSeconds = 65,
}) => NetworkTelemetry(
  roundTripMs: latency,
  jitterMs: 5,
  recentFailurePercent: failure,
  probesSent: 10,
  probesFailed: failure > 0 ? 1 : 0,
  connectedSeconds: 65,
  idleSeconds: idleSeconds,
  lossInPercent: lossIn,
  lossOutPercent: lossOut,
  sampledAt: DateTime(2026, 11, 6, 12).millisecondsSinceEpoch,
);

class _Controller extends SessionController {
  int samples = 0;

  @override
  SessionView build() => SessionView(
    state: const CoreSessionState.connected(clientId: 1, channelId: 1),
    network: _sample(),
  );

  @override
  Future<void> sampleNetwork() async {
    samples++;
  }

  void setNetwork(NetworkTelemetry? value) =>
      state = state.copyWith(network: value);

  void bumpEpoch() =>
      state = state.copyWith(connectionEpoch: state.connectionEpoch + 1);
}

Future<void> _pumpStatus(
  WidgetTester tester,
  ProviderContainer container, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          PrismUiLocalizationsDelegate(),
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            PrismRootScope(brightness: Brightness.light, child: child!),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            disableAnimations: disableAnimations,
          ),
          child: const Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(width: 288, height: 600, child: ChannelPanel()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('quality distinguishes missing data, latency and failed probes', () {
    expect(networkQuality(null), NetworkQuality.unknown);
    expect(networkQuality(_sample()), NetworkQuality.good);
    expect(networkQuality(_sample(latency: 150)), NetworkQuality.degraded);
    expect(networkQuality(_sample(latency: 300)), NetworkQuality.poor);
    expect(networkQuality(_sample(latency: null)), NetworkQuality.poor);
    expect(networkQuality(_sample(failure: 20)), NetworkQuality.poor);
    expect(networkQuality(_sample(lossIn: 5)), NetworkQuality.poor);
    expect(networkQuality(_sample(lossOut: 1)), NetworkQuality.degraded);
  });

  testWidgets(
    'wifi extends the user card with connection stats, pins and releases',
    (tester) async {
      final container = ProviderContainer(
        overrides: [sessionViewProvider.overrideWith(_Controller.new)],
      );
      addTearDown(container.dispose);
      await _pumpStatus(tester, container);
      await tester.pumpAndSettle();

      Color? iconColor() => tester
          .widget<IconButton>(
            find
                .ancestor(
                  of: find.byIcon(Icons.wifi_rounded),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .style
          ?.foregroundColor
          ?.resolve({});
      final label = tester.widget<Text>(find.text('语音已连接'));
      expect(iconColor(), label.style!.color);
      final green = iconColor();
      final controller =
          container.read(sessionViewProvider.notifier) as _Controller;

      // 关闭状态只保留入口行，面板内容不构建。
      expect(find.text('网络状态'), findsNothing);
      expect(find.text('Ping'), findsNothing);

      controller.setNetwork(_sample(latency: 180));
      await tester.pumpAndSettle();
      expect(find.text('网络不稳定'), findsOneWidget);
      expect(iconColor(), isNot(green));
      controller.setNetwork(_sample(latency: null));
      await tester.pumpAndSettle();
      expect(find.text('网络质量差'), findsOneWidget);
      final scheme = Theme.of(tester.element(find.byType(NetworkStatus)))
          .colorScheme;
      expect(iconColor(), scheme.error);

      controller.setNetwork(
        _sample(latency: 45, idleSeconds: 3_725, lossIn: 0.5, lossOut: 1),
      );
      await tester.tap(find.byIcon(Icons.wifi_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(controller.samples, greaterThan(0));
      final samplesBeforeTick = controller.samples;
      await tester.pump(const Duration(seconds: 1));
      expect(controller.samples, samplesBeforeTick + 1);
      expect(find.text('网络状态'), findsOneWidget);
      expect(find.text('Ping'), findsOneWidget);
      expect(find.text('丢包（入）'), findsOneWidget);
      expect(find.text('丢包（出）'), findsOneWidget);
      expect(find.text('空闲时间'), findsOneWidget);
      expect(find.text('45 毫秒'), findsOneWidget);
      expect(find.text('0.5%'), findsOneWidget);
      expect(find.text('1%'), findsOneWidget);
      expect(find.text('00:01:02:05'), findsOneWidget);

      final panel = find.byKey(const ValueKey('network-telemetry-panel'));
      expect(
        find.descendant(of: panel, matching: find.byType(SignalRibbon)),
        findsNWidgets(3),
      );
      final panelSize = tester.getSize(panel);
      expect(panelSize.width, lessThanOrEqualTo(272));

      // 入口再次点击收起，卡片恢复原高度。
      await tester.tap(find.byIcon(Icons.wifi_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('网络状态'), findsNothing);
      await tester.tap(find.byIcon(Icons.wifi_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('网络状态'), findsOneWidget);

      // 固定后数据刷新不会收起；入口关闭时同时取消固定。
      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      expect(container.read(sessionViewProvider).networkPanelPinned, isTrue);
      controller.setNetwork(_sample(latency: 50));
      await tester.pump();
      expect(find.text('网络状态'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.wifi_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('网络状态'), findsNothing);
      expect(container.read(sessionViewProvider).networkPanelPinned, isFalse);

      // 关闭按钮收起面板，采样定时器随面板销毁。
      await tester.tap(find.byIcon(Icons.wifi_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('网络状态'), findsNothing);
      final samplesAtClose = controller.samples;
      await tester.pump(const Duration(seconds: 6));
      expect(controller.samples, samplesAtClose);
    },
  );

  testWidgets('new connection epoch collapses the expanded panel', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [sessionViewProvider.overrideWith(_Controller.new)],
    );
    addTearDown(container.dispose);
    await _pumpStatus(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.wifi_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('网络状态'), findsOneWidget);

    final controller =
        container.read(sessionViewProvider.notifier) as _Controller;
    controller.bumpEpoch();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('网络状态'), findsNothing);
  });

  testWidgets('unknown packet loss is rendered as a gap, not zero', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [sessionViewProvider.overrideWith(_Controller.new)],
    );
    addTearDown(container.dispose);
    await _pumpStatus(tester, container);
    await tester.pumpAndSettle();

    final controller =
        container.read(sessionViewProvider.notifier) as _Controller;
    controller.setNetwork(_sample(lossIn: null, lossOut: null));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.wifi_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final panel = find.byKey(const ValueKey('network-telemetry-panel'));
    expect(
      find.descendant(of: panel, matching: find.byType(SignalRibbon)),
      findsOneWidget,
    );

    controller.setNetwork(_sample(lossIn: 0.5, lossOut: 1));
    await tester.pump();

    final ribbons = tester
        .widgetList<SignalRibbon>(
          find.descendant(of: panel, matching: find.byType(SignalRibbon)),
        )
        .toList();
    expect(ribbons, hasLength(3));
    expect(ribbons[1].values.whereType<double>(), hasLength(1));
    expect(ribbons[2].values.whereType<double>(), hasLength(1));
    expect(ribbons[1].values.last, closeTo(0.316, 0.001));
  });

  testWidgets('closing the compact drawer disposes the panel timer', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [sessionViewProvider.overrideWith(_Controller.new)],
    );
    addTearDown(container.dispose);
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            PrismUiLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              PrismRootScope(brightness: Brightness.light, child: child!),
          home: Scaffold(
            key: scaffoldKey,
            drawer: const Drawer(child: ChannelPanel()),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.wifi_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('网络状态'), findsOneWidget);

    scaffoldKey.currentState!.closeDrawer();
    await tester.pumpAndSettle();
    expect(find.text('网络状态'), findsNothing);

    final controller =
        container.read(sessionViewProvider.notifier) as _Controller;
    final samplesAtClose = controller.samples;
    await tester.pump(const Duration(seconds: 6));
    expect(controller.samples, samplesAtClose);
  });

  testWidgets('reduced motion omits the signal ribbon', (tester) async {
    final container = ProviderContainer(
      overrides: [sessionViewProvider.overrideWith(_Controller.new)],
    );
    addTearDown(container.dispose);
    await _pumpStatus(tester, container, disableAnimations: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.wifi_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('网络状态'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('network-telemetry-panel')),
        matching: find.byType(SignalRibbon),
      ),
      findsNothing,
    );
  });
}
