import 'dart:math';

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'data_point.dart';
import 'json_values.dart';
import 'sensor_status.dart';

enum DataSource { hardware, simulation, unknown }

enum TrialCompletion { completed, interrupted, recovered }

enum DistanceMethod { integrated, wallRange }

class Trial {
  Trial({
    String? id,
    required this.startDate,
    this.endDate,
    required List<DataPoint> dataPoints,
    this.source = DataSource.unknown,
    this.completion = TrialCompletion.completed,
    this.interruptionReason,
    Iterable<SensorRole> sensors = SensorRole.values,
    this.distanceMethod = DistanceMethod.integrated,
  }) : id = (id ?? const Uuid().v4()).toLowerCase(),
       dataPoints = List.unmodifiable(dataPoints),
       sensors = Set.unmodifiable(sensors);

  final String id;
  final DateTime startDate;
  final DateTime? endDate;
  final List<DataPoint> dataPoints;
  final DataSource source;
  final TrialCompletion completion;
  final String? interruptionReason;
  final DistanceMethod distanceMethod;

  /// Frozen at Start. Missing metadata in historical files means all three.
  final Set<SensorRole> sensors;
  bool get hasAllSensors => sensors.length == SensorRole.values.length;
  String get sensorLabel => SensorRole.values
      .where(sensors.contains)
      .map((role) => role.label)
      .join(', ');

  Duration get duration {
    final end =
        endDate ?? (dataPoints.isEmpty ? startDate : dataPoints.last.timestamp);
    return Duration(
      microseconds: max(0, end.difference(startDate).inMicroseconds),
    );
  }

  double? get totalDistance {
    final distances = dataPoints
        .map((point) => point.distanceFt)
        .whereType<double>();
    if (distances.isEmpty) return null;
    if (distanceMethod == DistanceMethod.wallRange) {
      return max(0, distances.last);
    }
    return max(0, distances.last - distances.first);
  }

  double? _average(double? Function(DataPoint) value) {
    var sum = 0.0;
    var count = 0;
    for (final point in dataPoints) {
      final measurement = value(point);
      if (measurement != null) {
        sum += measurement;
        count++;
      }
    }
    return count == 0 ? null : sum / count;
  }

  double? get averageSpeed => _average((point) => point.speedFtS);
  double? get averageWeightLeft => _average((point) => point.weightLeft);
  double? get averageWeightRight => _average((point) => point.weightRight);
  double? get averageWeightTotal => _average((point) => point.weightTotal);
  int get sampleCount => dataPoints.length;

  factory Trial.fromJson(Map<String, dynamic> json) {
    final sensors = _readSensors(json);
    return Trial(
      id: jsonString(json, 'id'),
      startDate: jsonDate(json, 'startDate'),
      endDate: json['endDate'] == null ? null : jsonDate(json, 'endDate'),
      dataPoints: jsonList(json, 'dataPoints')
          .map(
            (value) => DataPoint.fromJson(jsonObject(value), sensors: sensors),
          )
          .toList(),
      sensors: sensors,
      distanceMethod: json['distanceMethod'] == null
          ? DistanceMethod.integrated
          : DistanceMethod.values.firstWhere(
              (method) => method.name == json['distanceMethod'],
              orElse: () =>
                  throw const FormatException('Unknown distance method.'),
            ),
      source: DataSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => DataSource.unknown,
      ),
      completion: TrialCompletion.values.firstWhere(
        (value) => value.name == json['completion'],
        orElse: () => json['endDate'] == null
            ? TrialCompletion.interrupted
            : TrialCompletion.completed,
      ),
      interruptionReason: json['interruptionReason'] as String?,
    );
  }

  static Set<SensorRole> _readSensors(Map<String, dynamic> json) {
    if (!json.containsKey('sensors')) return SensorRole.values.toSet();
    final names = jsonList(json, 'sensors');
    final sensors = <SensorRole>{};
    for (final name in names) {
      final matches = SensorRole.values.where((role) => role.name == name);
      if (matches.isEmpty || !sensors.add(matches.single)) {
        throw const FormatException('Invalid or duplicate trial sensor.');
      }
    }
    if (sensors.isEmpty) throw const FormatException('Trial has no sensors.');
    return sensors;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startDate': startDate.toUtc().toIso8601String(),
    if (endDate != null) 'endDate': endDate!.toUtc().toIso8601String(),
    'dataPoints': dataPoints.map((point) => point.toJson()).toList(),
    'source': source.name,
    'completion': completion.name,
    if (distanceMethod != DistanceMethod.integrated)
      'distanceMethod': distanceMethod.name,
    'sensors': SensorRole.values
        .where(sensors.contains)
        .map((role) => role.name)
        .toList(),
    if (interruptionReason != null) 'interruptionReason': interruptionReason,
  };

  String toCsv() {
    final csv = StringBuffer(
      'timestamp,weightLeft,weightRight,weightTotal,distanceFt,speedFtS\n',
    );
    for (final point in dataPoints) {
      csv.writeln(
        [
          point.timestamp.toUtc().toIso8601String(),
          point.weightLeft?.toStringAsFixed(2) ?? '',
          point.weightRight?.toStringAsFixed(2) ?? '',
          point.weightTotal?.toStringAsFixed(2) ?? '',
          point.distanceFt?.toStringAsFixed(2) ?? '',
          point.speedFtS?.toStringAsFixed(2) ?? '',
        ].join(','),
      );
    }
    return csv.toString();
  }

  String get csvFilename =>
      'trial_${DateFormat('yyyy-MM-dd_HH-mm-ss').format(startDate.toLocal())}.csv';
}
