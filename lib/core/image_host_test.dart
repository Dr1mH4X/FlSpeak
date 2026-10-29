// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'image_host.dart';

class _Api extends Fake implements RustLibApi {
  bool reject = false;
  Completer<void>? validation;
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
    'clipboard image input handles empty content and enforces the size limit',
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
      await expectLater(
        input.paste(),
        throwsA(
          isA<ImageInputException>().having(
            (e) => e.failure,
            'failure',
            ImageInputFailure.clipboardEmpty,
          ),
        ),
      );
      content = Uint8List.fromList([1, 2, 3]);
      expect((await input.paste()).bytes, [1, 2, 3]);
      content = Uint8List(maxChatImageBytes + 1);
      await expectLater(
        input.paste(),
        throwsA(
          isA<ImageInputException>().having(
            (e) => e.failure,
            'failure',
            ImageInputFailure.tooLarge,
          ),
        ),
      );
    },
  );
}
