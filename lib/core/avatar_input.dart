import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _avatarTypeGroup = XTypeGroup(
  extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
  mimeTypes: ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
  uniformTypeIdentifiers: [
    'public.png',
    'public.jpeg',
    'com.compuserve.gif',
    'org.webmproject.webp',
  ],
);

enum AvatarInputFailure { tooLarge }

class AvatarInputException implements Exception {
  const AvatarInputException(this.failure);

  final AvatarInputFailure failure;
}

final avatarInputProvider = Provider<AvatarInput>((ref) => const AvatarInput());

void ensureAvatarSize(int length) {
  if (length > maxAvatarBytes()) {
    throw const AvatarInputException(AvatarInputFailure.tooLarge);
  }
}

class AvatarInput {
  const AvatarInput();

  /// 先读文件长度，超过上限的文件不会进入内存。
  Future<Uint8List?> pick() async {
    final file = await openFile(acceptedTypeGroups: const [_avatarTypeGroup]);
    if (file == null) return null;
    ensureAvatarSize(await file.length());
    final bytes = await file.readAsBytes();
    ensureAvatarSize(bytes.length);
    return bytes;
  }
}
