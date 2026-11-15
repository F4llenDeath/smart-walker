import 'package:uuid/uuid.dart';

import 'json_values.dart';
import 'sensor_status.dart';

enum RadarMeasurement { distanceFt, speedFtS }

class DataPoint {
  DataPoint({
    String? id,
    required this.timestamp,
    this.weightLeft,
    this.weightRight,
    this.distanceFt,
    this.speedFtS,
    Iterable<RadarMeasurement> radarUnavailable = const [],
  }) : id = (id ?? const Uuid().v4()).toLowerCase(),
       radarUnavailable = Set.unmodifiable(radarUnavailable);

  final String id;
  final DateTime timestamp;
  final double? weightLeft;
  final double? weightRight;
  final double? distanceFt;
  final double? speedFtS;
  final Set<RadarMeasurement> radarUnavailable;

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
    bool allowRadarGaps = false,
  }) {
    final unavailable = <RadarMeasurement>{};
    if (json.containsKey('radarUnavailable')) {
      if (!allowRadarGaps || !sensors.contains(SensorRole.radar)) {
        throw const FormatException('Unexpected radar gap metadata.');
      }
      final names = jsonList(json, 'radarUnavailable');
      if (names.isEmpty) {
        throw const FormatException('Empty radar gap metadata.');
      }
      for (final name in names) {
        final matching = RadarMeasurement.values.where(
          (field) => field.name == name,
        );
        if (matching.isEmpty || !unavailable.add(matching.single)) {
          throw const FormatException('Invalid radar gap measurement.');
        }
        if (!json.containsKey(name) || json[name] != null) {
          throw const FormatException(
            'A radar gap must have an explicit null value.',
          );
        }
      }
    }
    return DataPoint(
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
        sensors.contains(SensorRole.radar) &&
            !unavailable.contains(RadarMeasurement.distanceFt),
      ),
      speedFtS: _measurement(
        json,
        'speedFtS',
        sensors.contains(SensorRole.radar) &&
            !unavailable.contains(RadarMeasurement.speedFtS),
      ),
      radarUnavailable: unavailable,
    );
  }

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
    if (radarUnavailable.isNotEmpty)
      'radarUnavailable': RadarMeasurement.values
          .where(radarUnavailable.contains)
          .map((field) => field.name)
          .toList(),
  };
}
