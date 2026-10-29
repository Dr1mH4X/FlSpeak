import 'dart:typed_data';

import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 可见视图共用受控抓取结果；最后一个视图离开后释放图片字节。
final remoteImageProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, url) => fetchImage(url: url),
      retry: (retryCount, error) => null,
    );
