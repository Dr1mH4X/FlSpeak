import 'dart:async';
import 'dart:ui';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:flspeak/core/image_host.dart';
import 'package:flspeak/core/models.dart';
import 'package:flspeak/l10n/app_localizations.dart';

class _Api extends Fake implements RustLibApi {
  bool reject = false;
  Completer<void>? validation;
  @override
  int crateApiSessionMaxChatImageBytes() => 20 * 1024 * 1024;

  @override
  Future<void> crateApiSessionValidateImageHost({
    required String uploadBase,
    required String publicBase,
  }) async {
    await validation?.future;
    if (reject) throw const CoreError.invalidAddress(message: 'invalid host');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    final values = <String, String>{};
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return values[key];
            case 'write':
              values[key] = args['value'] as String;
              return null;
            case 'delete':
              values.remove(key);
              return null;
            default:
              throw StateError('Unexpected storage method: ${call.method}');
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    api.reject = false;
    api.validation = null;
  });

  test(
    'closing the provider during host validation stops the deferred save',
    () async {
      final container = ProviderContainer();
      await container.read(imageHostProvider.future);
      final validation = Completer<void>();
      api.validation = validation;
      final saving = container
          .read(imageHostProvider.notifier)
          .save(
            const ImageHostConfiguration(
              uploadBase: 'https://upload.example.com/',
              publicBase: 'https://images.example.com/',
            ),
          );
      container.dispose();
      validation.complete();
      await saving;
      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      expect(await reopened.read(imageHostProvider.future), isNull);
    },
  );

  test(
    'configuration round trips only through secure storage and can be removed',
    () async {
      final first = ProviderContainer();
      addTearDown(first.dispose);
      expect(await first.read(imageHostProvider.future), isNull);
      await first
          .read(imageHostProvider.notifier)
          .save(
            const ImageHostConfiguration(
              uploadBase: 'https://upload.example.com/',
              publicBase: 'https://images.example.com/',
              token: 'test-secret',
            ),
          );
      final second = ProviderContainer();
      addTearDown(second.dispose);
      final loaded = await second.read(imageHostProvider.future);
      expect(loaded!.token, 'test-secret');
      expect(loaded.uploadBase, 'https://upload.example.com/');
      api.reject = true;
      await expectLater(
        second
            .read(imageHostProvider.notifier)
            .save(
              const ImageHostConfiguration(
                uploadBase: 'invalid',
                publicBase: 'invalid',
              ),
            ),
        throwsA(isA<CoreError>()),
      );
      expect(second.read(imageHostProvider).requireValue!.token, 'test-secret');
      await second.read(imageHostProvider.notifier).save(null);
      final third = ProviderContainer();
      addTearDown(third.dispose);
      expect(await third.read(imageHostProvider.future), isNull);
    },
  );
  test(
    'clipboard image input returns null when empty and raw bytes when present',
    () async {
      Object? content;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('pasteboard'), (
            call,
          ) async {
            expect(call.method, 'image');
            return content;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('pasteboard'), null),
      );
      const input = ImageInput();
      expect(await input.readClipboardImageBytes(), isNull);
      content = Uint8List.fromList([1, 2, 3]);
      expect(await input.readClipboardImageBytes(), [1, 2, 3]);
    },
  );

  test(
    'describeCoreError maps typed chat image errors in Chinese and English',
    () {
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(const Locale('zh'));

      final tooLarge = CoreError.imageTooLarge(maxBytes: maxChatImageBytes());
      expect(describeCoreError(tooLarge, en), contains('20.0 MiB'));
      expect(describeCoreError(tooLarge, zh), contains('20.0 MiB'));

      const unsupported = CoreError.imageUnsupportedFormat();
      expect(describeCoreError(unsupported, en), en.chatImageUnsupportedFormat);
      expect(describeCoreError(unsupported, zh), zh.chatImageUnsupportedFormat);
    },
  );
}
