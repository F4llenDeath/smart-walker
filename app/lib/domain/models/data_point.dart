import 'package:uuid/uuid.dart';

import 'json_values.dart';
import 'sensor_status.dart';

class DataPoint {
  DataPoint({
    String? id,
    required this.timestamp,
    this.weightLeft,
    this.weightRight,
    this.distanceFt,
    this.speedFtS,
  }) : id = (id ?? const Uuid().v4()).toLowerCase();

  final String id;
  final DateTime timestamp;
  final double? weightLeft;
  final double? weightRight;
  final double? distanceFt;
  final double? speedFtS;

  double? get weightTotal => weightLeft == null || weightRight == null
      ? null
      : weightLeft! + weightRight!;

  factory DataPoint.fromJson(
    Map<String, dynamic> json, {
    Set<SensorRole> sensors = const {
      SensorRole.leftFoot,
      SensorRole.rightFoot,
      SensorRole.radar,
    },
  }) => DataPoint(
    id: jsonString(json, 'id'),
    timestamp: jsonDate(json, 'timestamp'),
    weightLeft: _measurement(
      json,
      'weightLeft',
      sensors.contains(SensorRole.leftFoot),
    ),
    weightRight: _measurement(
      json,
      'weightRight',
      sensors.contains(SensorRole.rightFoot),
    ),
    distanceFt: _measurement(
      json,
      'distanceFt',
      sensors.contains(SensorRole.radar),
    ),
    speedFtS: _measurement(
      json,
      'speedFtS',
      sensors.contains(SensorRole.radar),
    ),
  );

  static double? _measurement(
    Map<String, dynamic> json,
    String key,
    bool included,
  ) {
    if (included) return jsonNumber(json, key);
    if (json[key] != null) {
      throw FormatException('Unexpected $key for an unrecorded sensor.');
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'weightLeft': weightLeft,
    'weightRight': weightRight,
    'distanceFt': distanceFt,
    'speedFtS': speedFtS,
  };
}
