// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../core/file_export.dart';
import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import 'channel_files_pane.dart';

class _Core extends Fake implements CoreSession {
  final paths = <String>[];
  @override
  Future<List<ChannelFileView>> listFiles({
    required int channelId,
    required String path,
    String? password,
  }) async {
    expect(channelId, 5);
    paths.add(path);
    if (password != 'secret') {
      throw const CoreError.channelPasswordRequired(
        message: 'password required',
      );
    }
    return path == '/'
        ? const [
            ChannelFileView(
              name: 'folder',
              path: '/folder',
              directory: true,
              size: 0,
            ),
            ChannelFileView(
              name: 'fixture.txt',
              path: '/fixture.txt',
              directory: false,
              size: 5,
            ),
          ]
        : [];
  }
}

class _Controller extends SessionController {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  SessionView build() => const SessionView(
    state: CoreSessionState.connected(clientId: 1, channelId: 5),
  );
  @override
  Future<bool> downloadChannelFile(
    int channelId,
    String path,
    String localPath, {
    String? password,
    ValueChanged<int>? onStarted,
  }) async {
    expect(channelId, 5);
    expect(path, '/fixture.txt');
    expect(password, 'secret');
    started.complete();
    await release.future;
    await File(localPath).writeAsString('hello');
    return true;
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  testWidgets(
    'password-protected file list browses folders and exports verified bytes',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fls-file-ui-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(root.path);
      addTearDown(() => PathProviderPlatform.instance = previous);
      final core = _Core();
      var exported = false;
      final controller = _Controller();
      final container = ProviderContainer(
        overrides: [
          coreSessionProvider.overrideWithValue(core),
          sessionViewProvider.overrideWith(() => controller),
          fileExportProvider.overrideWithValue((path, name) async {
            expect(name, 'fixture.txt');
            expect(await File(path).readAsString(), 'hello');
            exported = true;
            return true;
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ChannelFilesPane(channelId: 5)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('频道需要密码'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('fixture.txt'), findsOneWidget);
      expect(find.text('5 字节'), findsOneWidget);
      await tester.tap(find.text('folder'));
      await tester.pumpAndSettle();
      expect(find.text('此频道暂无文件'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(find.text('fixture.txt'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.download_rounded));
      for (
        var attempt = 0;
        attempt < 50 && !controller.started.isCompleted;
        attempt++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(controller.started.isCompleted, isTrue);
      // Removing the file pane must not discard an already requested download.
      await tester.pumpWidget(const SizedBox());
      controller.release.complete();
      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        final remaining = await tester.runAsync(() => root.list().toList());
        if (exported && remaining!.isEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(exported, isTrue);
      expect(core.paths, ['/', '/', '/folder', '/']);
      final files = await tester.runAsync(() => root.list().toList());
      expect(files, isEmpty);
    },
  );
}
