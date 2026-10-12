import 'dart:convert';
import 'dart:io';

import '../../domain/models/json_values.dart';
import '../../domain/models/patient.dart';
import 'atomic_json_file.dart';
import 'patient_repository.dart';

class JsonPatientRepository implements PatientRepository {
  JsonPatientRepository(Directory documents)
    : _storage = AtomicJsonFile(
        File('${documents.path}/smart_walker_data.json'),
      );

  final AtomicJsonFile _storage;
  bool _writable = false;

  @override
  String get dataPath => _storage.file.path;

  List<Patient> _decode(String contents) {
    final decoded = jsonDecode(contents);
    if (decoded is! List) {
      throw const FormatException('Expected a patient array.');
    }
    final patients = decoded
        .map((value) => Patient.fromJson(jsonObject(value)))
        .toList();
    if (patients.map((patient) => patient.id).toSet().length !=
        patients.length) {
      throw const FormatException('Duplicate patient IDs.');
    }
    if (!patients.any((patient) => patient.isUnassigned)) {
      patients.insert(0, Patient.unassigned);
    }
    return patients;
  }

  @override
  Future<List<Patient>> load() async {
    _writable = false;
    if (!await _storage.file.exists()) {
      // A missing primary with a backup can indicate an interrupted migration.
      if (await File('$dataPath.bak').exists()) {
        throw const FileSystemException(
          'Primary data file is missing; restore the backup.',
        );
      }
      _writable = true;
      final patients = [Patient.unassigned];
      await save(patients);
      return patients;
    }
    final patients = _decode(await _storage.file.readAsString());
    _writable = true;
    return patients;
  }

  @override
  Future<void> save(List<Patient> patients) async {
    if (!_writable) {
      throw StateError(
        'Data could not be loaded. Existing files are protected.',
      );
    }
    await _storage.write(
      patients.map((patient) => patient.toJson()).toList(),
      backup: true,
    );
  }

  @override
  Future<List<Patient>> restoreBackup() async {
    final contents = await File('$dataPath.bak').readAsString();
    final patients = _decode(contents);
    await _storage.serialize(() async {
      if (await _storage.file.exists()) {
        await _storage.file.copy(
          '$dataPath.unreadable-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
    });
    // Do not replace the good backup with the unreadable primary.
    await _storage.write(patients.map((patient) => patient.toJson()).toList());
    _writable = true;
    return patients;
  }
}
