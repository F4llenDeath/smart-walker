import 'package:uuid/uuid.dart';

import 'json_values.dart';

class DataPoint {
  DataPoint({
    String? id,
    required this.timestamp,
    required this.weightLeft,
    required this.weightRight,
    required this.distanceFt,
    required this.speedFtS,
  }) : id = (id ?? const Uuid().v4()).toLowerCase();

  final String id;
  final DateTime timestamp;
  final double weightLeft;
  final double weightRight;
  final double distanceFt;
  final double speedFtS;

  double get weightTotal => weightLeft + weightRight;

  factory DataPoint.fromJson(Map<String, dynamic> json) => DataPoint(
    id: jsonString(json, 'id'),
    timestamp: jsonDate(json, 'timestamp'),
    weightLeft: jsonNumber(json, 'weightLeft'),
    weightRight: jsonNumber(json, 'weightRight'),
    distanceFt: jsonNumber(json, 'distanceFt'),
    speedFtS: jsonNumber(json, 'speedFtS'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'weightLeft': weightLeft,
    'weightRight': weightRight,
    'distanceFt': distanceFt,
    'speedFtS': speedFtS,
  };
}
