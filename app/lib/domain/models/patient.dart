import 'package:uuid/uuid.dart';

import 'json_values.dart';
import 'trial.dart';

class Patient {
  Patient({
    String? id,
    required this.name,
    required this.dateCreated,
    List<Trial> trials = const [],
  }) : id = (id ?? const Uuid().v4()).toLowerCase(),
       trials = List.unmodifiable(trials);

  static const unassignedId = '00000000-0000-0000-0000-000000000000';
  static Patient get unassigned => Patient(
    id: unassignedId,
    name: 'Unassigned',
    dateCreated: DateTime.utc(1),
  );

  final String id;
  final String name;
  final DateTime dateCreated;
  final List<Trial> trials;
  bool get isUnassigned => id == unassignedId;

  Patient withTrials(List<Trial> values) =>
      Patient(id: id, name: name, dateCreated: dateCreated, trials: values);

  factory Patient.fromJson(Map<String, dynamic> json) {
    final id = jsonString(json, 'id').toLowerCase();
    // Foundation's Date.distantPast can be outside ISO-8601's ordinary range.
    final created = id == unassignedId
        ? DateTime.utc(1)
        : jsonDate(json, 'dateCreated');
    final trials = jsonList(
      json,
      'trials',
    ).map((value) => Trial.fromJson(jsonObject(value))).toList();
    if (trials.map((trial) => trial.id).toSet().length != trials.length) {
      throw const FormatException('Duplicate trial IDs in patient data.');
    }
    return Patient(
      id: id,
      name: jsonString(json, 'name'),
      dateCreated: created,
      trials: trials,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'dateCreated': dateCreated.toUtc().toIso8601String(),
    'trials': trials.map((trial) => trial.toJson()).toList(),
  };
}
