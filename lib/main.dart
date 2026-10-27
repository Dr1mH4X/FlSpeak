import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import 'app.dart';
import 'core/preferences.dart';
import 'core/providers.dart';
import 'core/store_path.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // Android 15 起系统强制 edge-to-edge；旧版本也统一成同一套 inset 行为，
    // 页面里的 SafeArea 才能在所有版本上对齐。
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  await RustLib.init();

  final storePath = await resolveStorePath();
  final session = CoreSession(storePath: storePath);
  final preferences = await PreferencesStore.load(
    PreferencesStore.pathFor(storePath),
  );

  runApp(
    ProviderScope(
      overrides: [
        coreSessionProvider.overrideWithValue(session),
        preferencesStoreProvider.overrideWithValue(preferences),
        storePathProvider.overrideWithValue(storePath),
      ],
      child: const TsClientApp(),
    ),
  );
}
