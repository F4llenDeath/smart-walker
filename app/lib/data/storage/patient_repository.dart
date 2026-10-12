import '../../domain/models/patient.dart';

abstract interface class PatientRepository {
  String get dataPath;
  Future<List<Patient>> load();
  Future<void> save(List<Patient> patients);
  Future<List<Patient>> restoreBackup();
}
