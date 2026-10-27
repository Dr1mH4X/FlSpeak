// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'preferences.dart';
import 'server_icon.dart';

void main() {
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
