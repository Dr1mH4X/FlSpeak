import 'package:flspeak_ffi/flspeak_ffi.dart';

enum NetworkQuality { unknown, good, degraded, poor }

NetworkQuality networkQuality(NetworkTelemetry? telemetry) {
  if (telemetry == null) return NetworkQuality.unknown;
  final latency = telemetry.roundTripMs;
  if (latency == null ||
      latency >= 300 ||
      telemetry.recentFailurePercent >= 20) {
    return NetworkQuality.poor;
  }
  if (latency >= 150 ||
      (telemetry.jitterMs ?? 0) >= 50 ||
      telemetry.recentFailurePercent > 0) {
    return NetworkQuality.degraded;
  }
  return NetworkQuality.good;
}
