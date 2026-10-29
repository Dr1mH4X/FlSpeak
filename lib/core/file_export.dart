import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fileExportProvider = Provider<Future<bool> Function(String, String)>(
  (ref) => exportDownloadedFile,
);

Future<bool> exportDownloadedFile(String path, String name) async {
  if (Platform.isAndroid) {
    return await const MethodChannel(
          'flspeak/files',
        ).invokeMethod<String>('saveDownload', {'path': path, 'name': name}) !=
        null;
  }
  final location = await getSaveLocation(suggestedName: name);
  if (location == null) return false;
  await XFile(path).saveTo(location.path);
  return true;
}
