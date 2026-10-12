import 'dart:math';

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'data_point.dart';
import 'json_values.dart';

enum DataSource { hardware, simulation, unknown }

enum TrialCompletion { completed, interrupted, recovered }

class Trial {
  Trial({
    String? id,
    required this.startDate,
    this.endDate,
    required List<DataPoint> dataPoints,
    this.source = DataSource.unknown,
    this.completion = TrialCompletion.completed,
    this.interruptionReason,
  }) : id = (id ?? const Uuid().v4()).toLowerCase(),
       dataPoints = List.unmodifiable(dataPoints);

  final String id;
  final DateTime startDate;
  final DateTime? endDate;
  final List<DataPoint> dataPoints;
  final DataSource source;
  final TrialCompletion completion;
  final String? interruptionReason;

  Duration get duration {
    final end =
        endDate ?? (dataPoints.isEmpty ? startDate : dataPoints.last.timestamp);
    return Duration(
      microseconds: max(0, end.difference(startDate).inMicroseconds),
    );
  }

  double get totalDistance => dataPoints.isEmpty
      ? 0
      : max(0, dataPoints.last.distanceFt - dataPoints.first.distanceFt);

  double _average(double Function(DataPoint) value) => dataPoints.isEmpty
      ? 0
      : dataPoints.fold<double>(0, (sum, point) => sum + value(point)) /
            dataPoints.length;

  double get averageSpeed => _average((point) => point.speedFtS);
  double get averageWeightLeft => _average((point) => point.weightLeft);
  double get averageWeightRight => _average((point) => point.weightRight);
  double get averageWeightTotal => averageWeightLeft + averageWeightRight;
  int get sampleCount => dataPoints.length;

  factory Trial.fromJson(Map<String, dynamic> json) => Trial(
    id: jsonString(json, 'id'),
    startDate: jsonDate(json, 'startDate'),
    endDate: json['endDate'] == null ? null : jsonDate(json, 'endDate'),
    dataPoints: jsonList(
      json,
      'dataPoints',
    ).map((value) => DataPoint.fromJson(jsonObject(value))).toList(),
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'startDate': startDate.toUtc().toIso8601String(),
    if (endDate != null) 'endDate': endDate!.toUtc().toIso8601String(),
    'dataPoints': dataPoints.map((point) => point.toJson()).toList(),
    'source': source.name,
    'completion': completion.name,
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
          point.weightLeft.toStringAsFixed(2),
          point.weightRight.toStringAsFixed(2),
          point.weightTotal.toStringAsFixed(2),
          point.distanceFt.toStringAsFixed(2),
          point.speedFtS.toStringAsFixed(2),
        ].join(','),
      );
    }
    return csv.toString();
  }

  String get csvFilename =>
      'trial_${DateFormat('yyyy-MM-dd_HH-mm-ss').format(startDate.toLocal())}.csv';
}
