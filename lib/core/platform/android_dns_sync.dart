import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../logging/logger.dart';

/// 同步 Android 活跃网络的 DNS 上游地址到 Rust 解析器。
class AndroidDnsSync {
  AndroidDnsSync._();

  static const MethodChannel _methodChannel = MethodChannel(
    'flspeak/network_dns',
  );
  static const EventChannel _eventChannel = EventChannel(
    'flspeak/network_dns_events',
  );

  static StreamSubscription<dynamic>? _subscription;

  static Future<void> initialize({
    void Function(List<String> servers)? onUpdate,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final apply =
        onUpdate ?? (servers) => setAndroidDnsServers(servers: servers);

    try {
      final initial = await _methodChannel.invokeListMethod<String>(
        'getDnsServers',
      );
      if (initial != null) {
        apply(initial);
      }
    } on PlatformException catch (error) {
      logWarn(
        'failed to read initial Android DNS',
        target: 'app',
        error: error,
      );
    } on MissingPluginException {
      return;
    }

    await _subscription?.cancel();
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is List) {
          apply(event.whereType<String>().toList(growable: false));
        }
      },
      onError: (Object error) {
        logWarn(
          'failed to observe Android DNS changes',
          target: 'app',
          error: error,
        );
      },
    );
  }

  @visibleForTesting
  static Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
