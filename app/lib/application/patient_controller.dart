import 'package:flutter/foundation.dart';

import '../data/storage/patient_repository.dart';
import '../domain/models/patient.dart';
import '../domain/models/trial.dart';

class PatientController extends ChangeNotifier {
  PatientController(this.repository);

  final PatientRepository repository;
  List<Patient> _patients = [];
  String _selectedId = Patient.unassignedId;
  bool ready = false;
  bool saving = false;
  String? error;
  bool Function() editingLocked = () => false;

  List<Patient> get patients {
    final sorted = _patients.where((patient) => !patient.isUnassigned).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      selectedById(Patient.unassignedId) ?? Patient.unassigned,
      ...sorted,
    ];
  }

  Patient get selected => selectedById(_selectedId) ?? Patient.unassigned;
  Patient? selectedById(String id) {
    for (final patient in _patients) {
      if (patient.id == id) return patient;
    }
    return null;
  }

  List<Trial> get trials =>
      selected.trials.toList()
        ..sort((a, b) => b.startDate.compareTo(a.startDate));

  Future<void> initialize({bool restoreBackup = false}) async {
    if (saving || (ready && editingLocked())) return;
    saving = true;
    ready = false;
    error = null;
    notifyListeners();
    try {
      _patients = await (restoreBackup
          ? repository.restoreBackup()
          : repository.load());
      if (selectedById(_selectedId) == null) _selectedId = Patient.unassignedId;
      ready = true;
    } catch (exception) {
      error =
          'Unable to load patient data. Existing files were not overwritten. $exception';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  void select(String id) {
    _requireEditable();
    if (selectedById(id) == null) throw StateError('Patient does not exist.');
    _selectedId = id;
    notifyListeners();
  }

  void _requireEditable() {
    if (!ready || saving || editingLocked()) {
      throw StateError(
        'Patient changes are unavailable during recording, recovery, or saving.',
      );
    }
  }

  Future<void> _commit(List<Patient> values, {String? selectId}) async {
    if (!ready || saving) throw StateError('Storage is not ready.');
    saving = true;
    error = null;
    notifyListeners();
    try {
      await repository.save(values);
      _patients = values;
      if (selectId != null) _selectedId = selectId;
    } catch (exception) {
      error = 'Save failed. Your previous saved data is unchanged. $exception';
      rethrow;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> add(String name) async {
    _requireEditable();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Enter a patient name.');
    final patient = Patient(name: trimmed, dateCreated: DateTime.now().toUtc());
    await _commit([..._patients, patient], selectId: patient.id);
  }

  Future<void> delete(String id) async {
    _requireEditable();
    if (id == Patient.unassignedId) {
      throw StateError('Unassigned cannot be deleted.');
    }
    await _commit(
      _patients.where((patient) => patient.id != id).toList(),
      selectId: _selectedId == id ? Patient.unassignedId : _selectedId,
    );
  }

  Future<void> saveTrial(String patientId, Trial trial) async {
    if (containsTrial(trial.id)) return;
    if (selectedById(patientId) == null) {
      throw StateError('The recording patient no longer exists.');
    }
    await _commit(
      _patients
          .map(
            (patient) => patient.id == patientId
                ? patient.withTrials([...patient.trials, trial])
                : patient,
          )
          .toList(),
    );
  }

  bool containsTrial(String id) =>
      _patients.any((patient) => patient.trials.any((trial) => trial.id == id));

  Future<void> deleteTrial(String patientId, String trialId) async {
    _requireEditable();
    await _commit(
      _patients
          .map(
            (patient) => patient.id == patientId
                ? patient.withTrials(
                    patient.trials
                        .where((trial) => trial.id != trialId)
                        .toList(),
                  )
                : patient,
          )
          .toList(),
    );
  }
}
