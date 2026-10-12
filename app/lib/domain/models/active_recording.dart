import 'json_values.dart';
import 'trial.dart';

class RecordingDraft {
  const RecordingDraft({
    required this.patientId,
    required this.patientName,
    required this.baseline,
    required this.checkpoint,
    required this.trial,
  });

  final String patientId;
  final String patientName;
  final double baseline;
  final DateTime checkpoint;
  final Trial trial;

  factory RecordingDraft.fromJson(Map<String, dynamic> json) => RecordingDraft(
    patientId: jsonString(json, 'patientId').toLowerCase(),
    patientName: jsonString(json, 'patientName'),
    baseline: jsonNumber(json, 'baseline'),
    checkpoint: jsonDate(json, 'checkpoint'),
    trial: Trial.fromJson(jsonObject(json['trial'])),
  );

  Map<String, dynamic> toJson() => {
    'patientId': patientId,
    'patientName': patientName,
    'baseline': baseline,
    'checkpoint': checkpoint.toUtc().toIso8601String(),
    'trial': trial.toJson(),
  };
}
