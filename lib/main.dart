import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import 'app.dart';
import 'core/preferences.dart';
import 'core/providers.dart';
import 'core/store_path.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
