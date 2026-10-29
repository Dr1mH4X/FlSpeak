// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'preferences.dart';
import 'server_icon.dart';

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
}
