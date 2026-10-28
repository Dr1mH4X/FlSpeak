import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pasteboard/pasteboard.dart';

const maxChatImageBytes = 20 * 1024 * 1024;
const _storageKey = 'flspeak.image-host';

class ImageHostConfiguration {
  const ImageHostConfiguration({
    required this.uploadBase,
    required this.publicBase,
    this.token = '',
  });
  final String uploadBase;
  final String publicBase;
  final String token;
}

final imageHostStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => Platform.isMacOS
      ? const FlutterSecureStorage(
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        )
      : const FlutterSecureStorage(),
);

final imageHostProvider =
    AsyncNotifierProvider<ImageHostController, ImageHostConfiguration?>(
      ImageHostController.new,
    );

class ImageHostController extends AsyncNotifier<ImageHostConfiguration?> {
  @override
  Future<ImageHostConfiguration?> build() async {
    final raw = await ref.read(imageHostStorageProvider).read(key: _storageKey);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return ImageHostConfiguration(
      uploadBase: data['uploadBase'] as String,
      publicBase: data['publicBase'] as String,
      token: data['token'] as String,
    );
  }

  Future<void> save(ImageHostConfiguration? config) async {
    if (config == null) {
      await ref.read(imageHostStorageProvider).delete(key: _storageKey);
    } else {
      await validateImageHost(
        uploadBase: config.uploadBase,
        publicBase: config.publicBase,
      );
      await ref
          .read(imageHostStorageProvider)
          .write(
            key: _storageKey,
            value: jsonEncode({
              'uploadBase': config.uploadBase,
              'publicBase': config.publicBase,
              'token': config.token,
            }),
          );
    }
    if (ref.mounted) state = AsyncData(config);
  }
}

class PickedChatImage {
  const PickedChatImage({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

enum ImageInputFailure { tooLarge, clipboardEmpty }

class ImageInputException implements Exception {
  const ImageInputException(this.failure);
  final ImageInputFailure failure;
}

final imageInputProvider = Provider<ImageInput>((ref) => const ImageInput());

class ImageInput {
  const ImageInput();
  Future<PickedChatImage?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'avif'],
          mimeTypes: [
            'image/png',
            'image/jpeg',
            'image/gif',
            'image/webp',
            'image/avif',
          ],
          uniformTypeIdentifiers: [
            'public.png',
            'public.jpeg',
            'com.compuserve.gif',
            'org.webmproject.webp',
            'public.avif',
          ],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxChatImageBytes) {
      throw const ImageInputException(ImageInputFailure.tooLarge);
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxChatImageBytes) {
      throw const ImageInputException(ImageInputFailure.tooLarge);
    }
    return PickedChatImage(bytes: bytes, name: file.name);
  }

  Future<PickedChatImage> paste() async {
    final bytes = await Pasteboard.image;
    if (bytes == null || bytes.isEmpty) {
      throw const ImageInputException(ImageInputFailure.clipboardEmpty);
    }
    if (bytes.length > maxChatImageBytes) {
      throw const ImageInputException(ImageInputFailure.tooLarge);
    }
    return PickedChatImage(bytes: bytes, name: 'clipboard.png');
  }
}
