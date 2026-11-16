// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart'
    hide
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/models.dart';
import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/providers.dart';
import 'package:flspeak/core/voice_levels.dart';
import 'package:flspeak/features/workspace/widgets/channel_pane.dart';
import 'package:flspeak/features/workspace/widgets/chat_pane.dart';
import 'package:flspeak/features/workspace/widgets/members_pane.dart';
import 'package:flspeak/features/workspace/workspace_page.dart';
import 'package:flspeak/features/workspace/workspace_shell.dart';
import 'package:flspeak/l10n/app_localizations.dart';
import 'package:flspeak/theme/app_theme.dart';
import 'package:flspeak/widgets/prism.dart';

class _FakeCore extends Fake implements CoreSession {
  final _events = StreamController<CoreEvent>.broadcast();

  @override
  Stream<CoreEvent> events() => _events.stream;

  @override
  Future<List<ServerProfileView>> listServers() async => const [];

  @override
  Future<List<ServerIconView>> listServerIcons() async => const [];

  @override
  Future<AccessView> access() async => const AccessView();

  @override
  Future<Uint8List> fetchAvatar({required String uid}) async => Uint8List(0);

  @override
  Future<String> channelDescription({required int channelId}) async => '';

  Future<void> close() => _events.close();
}

class _PerfSession extends SessionController {
  _PerfSession(this._initial, this._levelStream);

  final SessionView _initial;
  final Stream<VoiceLevels> _levelStream;

  @override
  SessionView build() => _initial;

  @override
  Stream<VoiceLevels> get levels => _levelStream;

  void setView(SessionView next) {
    state = next;
  }
}

SessionView _seedView({
  int channelCount = 60,
  int clientCount = 150,
  int messageCount = 120,
}) {
  final channels = <ChannelView>[
    for (var i = 1; i <= channelCount; i++)
      ChannelView(
        id: i,
        parentId: i <= 5 ? 0 : ((i - 1) % 5) + 1,
        name: 'Channel $i',
        order: i == 1 ? 0 : i - 1,
        iconId: 0,
        description: '',
        passwordProtected: false,
      ),
  ];
  final clients = <ClientView>[
    for (var i = 1; i <= clientCount; i++)
      ClientView(
        id: i,
        channelId: i <= 8 ? 1 : ((i - 1) % channelCount) + 1,
        uid: 'uid-$i',
        nickname: 'User $i',
        away: false,
        awayMessage: '',
        inputMuted: false,
        outputMuted: false,
        clientType: ClientType.standard,
      ),
  ];
  final now = DateTime(2026, 1, 1, 12, 0);
  final messages = <ChatMessage>[
    for (var i = 0; i < messageCount; i++)
      ChatMessage(
        from: 'User ${(i % 10) + 1}',
        fromUid: 'uid-${(i % 10) + 1}',
        fromId: (i % 10) + 1,
        text: 'Message line $i with realistic chat content.',
        at: now.add(Duration(seconds: i)),
        scope: ChatScope.channel,
        targetId: 1,
      ),
  ];
  return SessionView(
    state: const CoreSessionState.connected(clientId: 1, channelId: 1),
    servers: const [
      ServerProfileView(
        id: 's1',
        label: 'Perf Server',
        host: '127.0.0.1',
        port: 9987,
      ),
    ],
    activeServerId: 's1',
    channels: channels,
    clients: clients,
    messages: messages,
    chatScope: ChatScope.channel,
    voiceInputReady: true,
    voiceOutputReady: true,
    connectionEpoch: 1,
    network: const NetworkTelemetry(
      roundTripMs: 24,
      jitterMs: 2,
      recentFailurePercent: 0,
      probesSent: 100,
      probesFailed: 0,
      connectedSeconds: 60,
      lossInPercent: 0,
      lossOutPercent: 0,
      sampledAt: 1000,
    ),
  );
}

void main() {
  testWidgets(
    'workspace isolates high-frequency voice, network, speaking, and chat scroll rebuilds/repaints',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeCore = _FakeCore();
      addTearDown(fakeCore.close);
      final levelController = StreamController<VoiceLevels>.broadcast();
      addTearDown(levelController.close);

      final initialView = _seedView();
      final session = _PerfSession(initialView, levelController.stream);

      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(fakeCore),
          storePathProvider.overrideWithValue('/tmp/perf/prefs.json'),
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore.inMemory(
              preferences: const SessionPreferences(
                nickname: 'Perf',
                locale: 'zh',
              ),
            ),
          ),
          sessionViewProvider.overrideWith(() => session),
        ],
      );
      addTearDown(container.dispose);

      const shellBoundaryKey = Key('perf-shell');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.dark),
            locale: const Locale('zh'),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              PrismUiLocalizationsDelegate(),
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PrismRootScope(brightness: Brightness.dark, child: child!),
            home: const RepaintBoundary(
              key: shellBoundaryKey,
              child: WorkspaceShell(
                location: '/workspace',
                child: WorkspacePage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 默认关闭液态玻璃。
      expect(
        LiquidGlassScope.of(tester.element(find.byType(WorkspacePage))),
        isFalse,
      );

      final shellBoundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(shellBoundaryKey),
      );
      final channelBoundary = tester
          .renderObjectList<RenderRepaintBoundary>(
            find.ancestor(
              of: find.byType(ChannelPanel),
              matching: find.byType(RepaintBoundary),
            ),
          )
          .first;
      final pageBoundary = tester
          .renderObjectList<RenderRepaintBoundary>(
            find.ancestor(
              of: find.byType(WorkspacePage),
              matching: find.byType(RepaintBoundary),
            ),
          )
          .first;
      final membersBoundary = tester
          .renderObjectList<RenderRepaintBoundary>(
            find.ancestor(
              of: find.byType(MembersPane),
              matching: find.byType(RepaintBoundary),
            ),
          )
          .first;

      Future<({int rebuilds, int paintedBoundaries, int paintedObjects})>
      measure(Future<void> Function() action) async {
        var rebuilds = 0;
        var paintedObjects = 0;
        final boundaries = <RenderObject>{};
        shellBoundary.debugResetMetrics();
        channelBoundary.debugResetMetrics();
        pageBoundary.debugResetMetrics();
        membersBoundary.debugResetMetrics();
        final prevRebuild = debugOnRebuildDirtyWidget;
        final prevPaintFlag = debugProfilePaintsEnabled;
        final prevPaintCb = debugOnProfilePaint;
        debugOnRebuildDirtyWidget = (_, _) => rebuilds++;
        debugProfilePaintsEnabled = true;
        debugOnProfilePaint = (ro) {
          if (ro.isRepaintBoundary && !ro.debugNeedsPaint) return;
          paintedObjects++;
          RenderObject? b = ro;
          while (b != null && !b.isRepaintBoundary) {
            b = b.parent;
          }
          if (b != null) boundaries.add(b);
        };
        try {
          await action();
        } finally {
          debugOnRebuildDirtyWidget = prevRebuild;
          debugProfilePaintsEnabled = prevPaintFlag;
          debugOnProfilePaint = prevPaintCb;
        }
        return (
          rebuilds: rebuilds,
          paintedBoundaries: boundaries.length,
          paintedObjects: paintedObjects,
        );
      }

      int totalPaints(RenderRepaintBoundary boundary) =>
          boundary.debugSymmetricPaintCount +
          boundary.debugAsymmetricPaintCount;

      // 1. 50Hz 语音电平帧只重绘 SignalRibbon 内部边界。
      final voiceStats = await measure(() async {
        levelController.add(const VoiceLevels(mic: 0.8, received: 0.4));
        await tester.pump();
        await tester.pump();
      });
      expect(voiceStats.rebuilds, lessThanOrEqualTo(10));
      expect(voiceStats.paintedBoundaries, lessThanOrEqualTo(2));
      expect(totalPaints(shellBoundary), 0);
      expect(totalPaints(channelBoundary), 0);
      expect(totalPaints(pageBoundary), 0);
      expect(totalPaints(membersBoundary), 0);

      // 2. 1Hz 网络遥测更新在面板关闭时不触发大面积重建与重绘。
      session.setView(
        initialView.copyWith(
          network: const NetworkTelemetry(
            roundTripMs: 31,
            jitterMs: 3,
            recentFailurePercent: 0,
            probesSent: 110,
            probesFailed: 0,
            connectedSeconds: 61,
            lossInPercent: 0,
            lossOutPercent: 0,
            sampledAt: 1001,
          ),
        ),
      );
      final networkStats = await measure(() => tester.pump());
      expect(networkStats.rebuilds, lessThanOrEqualTo(25));
      expect(totalPaints(shellBoundary), 0);
      expect(totalPaints(channelBoundary), 0);
      expect(totalPaints(pageBoundary), 0);
      expect(totalPaints(membersBoundary), 0);

      // 3. 成员说话状态变化与稳态光环动画不连带祖先面板重建/重绘。
      session.setView(initialView.copyWith(speaking: const {2}));
      final speakSetStats = await measure(() => tester.pump());
      expect(speakSetStats.rebuilds, lessThanOrEqualTo(100));
      expect(totalPaints(shellBoundary), 0);
      expect(totalPaints(channelBoundary), 0);
      expect(totalPaints(pageBoundary), 0);

      await tester.pump(const Duration(milliseconds: 16));
      final steadyStats = await measure(
        () => tester.pump(const Duration(milliseconds: 16)),
      );
      expect(steadyStats.rebuilds, 0);
      expect(steadyStats.paintedBoundaries, lessThanOrEqualTo(2));
      expect(totalPaints(shellBoundary), 0);
      expect(totalPaints(channelBoundary), 0);
      expect(totalPaints(pageBoundary), 0);
      expect(totalPaints(membersBoundary), 0);

      // 清理说话状态。
      session.setView(initialView.copyWith(speaking: const {}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 4. 聊天列表按需虚拟化渲染，历史消息回滚不创建每行入场动画控制器。
      final mountedMessages = find.descendant(
        of: find.byType(ChatPane),
        matching: find.textContaining('Message line '),
      );
      expect(mountedMessages.evaluate().length, lessThan(30));

      final chatScroll = find
          .descendant(
            of: find.byType(ChatPane),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(chatScroll).position.jumpTo(2000);
      await tester.pump();

      expect(
        find.descendant(
          of: find.descendant(
            of: find.byType(ChatPane),
            matching: find.byType(PrismListView),
          ),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    },
  );
}
