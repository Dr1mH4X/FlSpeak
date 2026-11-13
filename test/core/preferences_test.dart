// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/preferences.dart';
import 'package:flspeak/core/server_icon.dart';

class _RenameFailure extends Fake implements File {
  _RenameFailure(this.file);
  final File file;
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await file.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    return this;
  }

  @override
  Future<File> rename(String newPath) =>
      Future.error(FileSystemException('rename failed', newPath));
}

void main() {
  test('a failed rename preserves the existing preferences file', () async {
    final directory = await Directory.systemTemp.createTemp('flspeak-rename-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/preferences.json';
    final store = await PreferencesStore.load(path);
    await store.save(const SessionPreferences(nickname: 'preserve me'));
    final destination = File(path);
    final temporary = _RenameFailure(File('$path.tmp'));
    await IOOverrides.runZoned(() async {
      await expectLater(
        store.save(const SessionPreferences(nickname: 'replacement')),
        throwsA(isA<FileSystemException>()),
      );
    }, createFile: (name) => name == path ? destination : temporary);
    expect((await PreferencesStore.load(path)).current.nickname, 'preserve me');
  });

  test(
    'concurrent preference saves preserve the last submitted snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flspeak-preferences-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/preferences.json';
      final store = await PreferencesStore.load(path);
      await Future.wait([
        for (var index = 0; index < 30; index++)
          store.save(SessionPreferences(nickname: 'name-$index')),
      ]);
      expect((await PreferencesStore.load(path)).current.nickname, 'name-29');
      expect(await File('$path.tmp').exists(), isFalse);
    },
  );

  test('a failed preference save does not block later saves', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flspeak-preferences-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final blocker = File('${directory.path}/parent');
    await blocker.writeAsString('not a directory');
    final path = '${blocker.path}/preferences.json';
    final store = await PreferencesStore.load(path);
    await expectLater(
      store.save(const SessionPreferences(nickname: 'first')),
      throwsA(isA<FileSystemException>()),
    );
    await blocker.delete();
    await store.save(const SessionPreferences(nickname: 'second'));
    expect((await PreferencesStore.load(path)).current.nickname, 'second');
  });

  test(
    'server icons persist independently and survive reopening the store',
    () async {
      final directory = await Directory.systemTemp.createTemp('flspeak-icons-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/preferences.json';
      final store = await PreferencesStore.load(path);
      await store.save(
        store.current.copyWith(
          serverIcons: const {
            'server-a': ServerIcon.gaming,
            'server-b': ServerIcon.music,
          },
        ),
      );
      final reopened = await PreferencesStore.load(path);
      expect(reopened.current.serverIcons, {
        'server-a': ServerIcon.gaming,
        'server-b': ServerIcon.music,
      });
      expect(
        SessionPreferences.fromJson({'nickname': 'test'}).serverIcons,
        isEmpty,
      );
    },
  );

  test(
    'motion preference serializes, deserializes, and falls back to system',
    () {
      for (final mode in AppMotionPreference.values) {
        final json = SessionPreferences(
          nickname: 'test',
          motion: mode,
        ).toJson();
        expect(json['motion'], mode.id);
        final restored = SessionPreferences.fromJson(json);
        expect(restored.motion, mode);
      }

      expect(
        SessionPreferences.fromJson({'nickname': 'test'}).motion,
        AppMotionPreference.system,
      );
      expect(
        SessionPreferences.fromJson({
          'nickname': 'test',
          'motion': 'invalid_mode',
        }).motion,
        AppMotionPreference.system,
      );
    },
  );

  test(
    'saving preferences preserves existing servers array and custom fields',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flspeak-preserve-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/preferences.json';
      final initial = {
        'schema': 3,
        'servers': [
          {
            'id': 'ts.example.com:9987',
            'label': 'Example',
            'host': 'ts.example.com',
            'port': 9987,
          },
        ],
        'nickname': 'Initial',
      };
      await File(path).writeAsString(jsonEncode(initial));

      final store = await PreferencesStore.load(path);
      expect(store.current.nickname, 'Initial');

      await store.save(store.current.copyWith(nickname: 'Updated'));

      final decoded = jsonDecode(await File(path).readAsString()) as Map;
      expect(decoded['nickname'], 'Updated');
      expect(decoded['servers'], isA<List>());
      expect((decoded['servers'] as List).first['label'], 'Example');
      expect(decoded['schema'], 3);
    },
  );

  test('streamViewerHeight serializes, deserializes and ignores non-finite numbers', () {
    final prefs = const SessionPreferences(nickname: 'TestUser')
        .copyWith(streamViewerHeight: 320.5);
    final json = prefs.toJson();
    expect(json['streamViewerHeight'], 320.5);

    final restored = SessionPreferences.fromJson(json);
    expect(restored.streamViewerHeight, 320.5);

    final invalid = SessionPreferences.fromJson(const {
      'streamViewerHeight': 'invalid',
    });
    expect(invalid.streamViewerHeight, isNull);

    final infinite = SessionPreferences.fromJson(const {
      'streamViewerHeight': double.infinity,
    });
    expect(infinite.streamViewerHeight, isNull);
  });

  test(
    'autoCheckUpdate and logLevel serialize, deserialize, and fall back safely',
    () {
      const defaults = SessionPreferences(nickname: 'TestUser');
      expect(defaults.autoCheckUpdate, isTrue);
      expect(defaults.logLevel, AppLogLevel.defaultForBuild);

      for (final level in AppLogLevel.values) {
        final json = SessionPreferences(
          nickname: 'TestUser',
          autoCheckUpdate: false,
          logLevel: level,
        ).toJson();
        final restored = SessionPreferences.fromJson(json);
        expect(restored.autoCheckUpdate, isFalse);
        expect(restored.logLevel, level);
      }

      final fallback = SessionPreferences.fromJson(const {
        'autoCheckUpdate': 'not-a-bool',
        'logLevel': 'verbose',
      });
      expect(fallback.autoCheckUpdate, isTrue);
      expect(fallback.logLevel, AppLogLevel.defaultForBuild);
    },
  );

  test('screen share preferences default to 720p, 30fps, h264, maintainFramerate and round-trip', () {
    const defaults = SessionPreferences(nickname: 'TestUser');
    expect(defaults.screenShareResolution, ScreenShareResolutionPreset.p720);
    expect(defaults.screenShareFrameRate, ScreenShareFrameRatePreset.fps30);
    expect(defaults.screenShareCodec, ScreenShareCodecPreference.h264);
    expect(
      defaults.screenShareDegradation,
      ScreenShareDegradationPreference.maintainFramerate,
    );

    final missingFields = SessionPreferences.fromJson(const {});
    expect(
      missingFields.screenShareResolution,
      ScreenShareResolutionPreset.p720,
    );
    expect(
      missingFields.screenShareFrameRate,
      ScreenShareFrameRatePreset.fps30,
    );
    expect(missingFields.screenShareCodec, ScreenShareCodecPreference.h264);
    expect(
      missingFields.screenShareDegradation,
      ScreenShareDegradationPreference.maintainFramerate,
    );

    final roundTripped = SessionPreferences.fromJson(
      const SessionPreferences(
        nickname: 'TestUser',
        screenShareResolution: ScreenShareResolutionPreset.p1080,
        screenShareFrameRate: ScreenShareFrameRatePreset.fps60,
        screenShareCodec: ScreenShareCodecPreference.vp8,
        screenShareDegradation:
            ScreenShareDegradationPreference.maintainResolution,
      ).toJson(),
    );
    expect(
      roundTripped.screenShareResolution,
      ScreenShareResolutionPreset.p1080,
    );
    expect(roundTripped.screenShareFrameRate, ScreenShareFrameRatePreset.fps60);
    expect(roundTripped.screenShareCodec, ScreenShareCodecPreference.vp8);
    expect(
      roundTripped.screenShareDegradation,
      ScreenShareDegradationPreference.maintainResolution,
    );
  });
}
