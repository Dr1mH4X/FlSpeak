import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/network_quality.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/features/workspace/widgets/network_status.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';

NetworkTelemetry _sample({double? latency = 30, double failure = 0}) =>
    NetworkTelemetry(
      roundTripMs: latency,
      jitterMs: 5,
      recentFailurePercent: failure,
      probesSent: 10,
      probesFailed: failure > 0 ? 1 : 0,
      connectedSeconds: 65,
      sampledAt: DateTime(2026, 11, 6, 12).millisecondsSinceEpoch,
    );

class _Controller extends SessionController {
  @override
  SessionView build() => SessionView(
    state: const CoreSessionState.connected(clientId: 1, channelId: 1),
    network: _sample(),
  );
  void setNetwork(NetworkTelemetry? value) =>
      state = state.copyWith(network: value);
}

void main() {
  test('quality distinguishes missing data, latency and failed probes', () {
    expect(networkQuality(null), NetworkQuality.unknown);
    expect(networkQuality(_sample()), NetworkQuality.good);
    expect(networkQuality(_sample(latency: 150)), NetworkQuality.degraded);
    expect(networkQuality(_sample(latency: 300)), NetworkQuality.poor);
    expect(networkQuality(_sample(latency: null)), NetworkQuality.poor);
    expect(networkQuality(_sample(failure: 20)), NetworkQuality.poor);
  });

  testWidgets(
    'wifi and label follow quality and clicking opens live telemetry',
    (tester) async {
      final container = ProviderContainer(
        overrides: [sessionViewProvider.overrideWith(_Controller.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: Consumer(
                  builder: (context, ref, _) => NetworkStatus(
                    view: ref.watch(sessionViewProvider),
                    channelLabel: 'Home',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Color? iconColor() =>
          tester.widget<IconButton>(find.byType(IconButton).first).color;
      final label = tester.widget<Text>(find.text('语音已连接'));
      expect(iconColor(), label.style!.color);
      final green = iconColor();
      final controller =
          container.read(sessionViewProvider.notifier) as _Controller;
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
      await tester.tap(find.byIcon(Icons.wifi_rounded));
      await tester.pumpAndSettle();
      expect(find.text('网络遥测'), findsOneWidget);
      expect(find.text('暂无数据'), findsOneWidget);
      controller.setNetwork(_sample(latency: 45));
      await tester.pumpAndSettle();
      expect(find.text('45.0 毫秒'), findsOneWidget);
      expect(find.text('0:01:05'), findsOneWidget);
      expect(find.text('最近响应失败率'), findsOneWidget);
    },
  );
}
