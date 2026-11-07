import 'package:flspeak_ffi/flspeak_ffi.dart';

enum NetworkQuality { unknown, good, degraded, poor }

NetworkQuality networkQuality(NetworkTelemetry? telemetry) {
  if (telemetry == null) return NetworkQuality.unknown;
  final latency = telemetry.roundTripMs;
  final lossIn = telemetry.lossInPercent ?? 0;
  final lossOut = telemetry.lossOutPercent ?? 0;
  final loss = lossIn > lossOut ? lossIn : lossOut;
  if (latency == null ||
      latency >= 300 ||
      telemetry.recentFailurePercent >= 20 ||
      loss >= 5) {
    return NetworkQuality.poor;
  }
  if (latency >= 150 ||
      (telemetry.jitterMs ?? 0) >= 50 ||
      telemetry.recentFailurePercent > 0 ||
      loss >= 1) {
    return NetworkQuality.degraded;
  }
  return NetworkQuality.good;
}
