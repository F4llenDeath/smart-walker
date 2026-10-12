import 'dart:convert';

import '../domain/models/sensor_status.dart';

abstract final class BleProtocol {
  static const serviceUuid = 'A7E8F0B1-3C54-4D92-9F3E-0A1B2C3D4E5F';
  static const characteristicUuid = 'B8F9E1C2-4D65-5EA3-A04F-1B2C3D4E5F60';
  static const sampleInterval = Duration(milliseconds: 200);
  static const freshness = Duration(seconds: 2);

  static SensorRole? roleFor(String? name) {
    for (final role in SensorRole.values) {
      if (role.deviceName == name?.trim()) return role;
    }
    return null;
  }

  static ({double value, double? speed})? parse(
    SensorRole role,
    List<int> bytes,
  ) {
    try {
      final text = utf8.decode(bytes).trim();
      final parts = text.split(',');
      if (parts.length != (role == SensorRole.radar ? 2 : 1)) return null;
      final value = double.tryParse(parts[0].trim());
      final speed = role == SensorRole.radar
          ? double.tryParse(parts[1].trim())
          : null;
      if (value == null || !value.isFinite) return null;
      if (role == SensorRole.radar &&
          (speed == null || !speed.isFinite || value < 0 || speed < 0)) {
        return null;
      }
      return (value: value, speed: speed);
    } on FormatException {
      return null;
    }
  }
}
