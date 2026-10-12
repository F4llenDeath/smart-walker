import 'package:path_provider/path_provider.dart';

import '../application/device_coordinator.dart';
import '../application/patient_controller.dart';
import '../application/simulation_source.dart';
import '../application/telemetry_controller.dart';
import '../application/trial_recorder.dart';
import '../data/ble/universal_ble_transport.dart';
import '../data/export/csv_export_service.dart';
import '../data/storage/json_patient_repository.dart';
import '../data/storage/recording_draft_store.dart';

class AppDependencies {
  AppDependencies._({
    required this.patients,
    required this.devices,
    required this.simulator,
    required this.telemetry,
    required this.recorder,
  });

  final PatientController patients;
  final DeviceCoordinator devices;
  final SimulationSource simulator;
  final TelemetryController telemetry;
  final TrialRecorder recorder;
  final CsvExportService csv = CsvExportService();

  static Future<AppDependencies> create() async {
    final directory = await getApplicationDocumentsDirectory();
    final patients = PatientController(JsonPatientRepository(directory));
    await patients.initialize();
    final devices = DeviceCoordinator(UniversalBleTransport());
    final simulator = SimulationSource();
    final telemetry = TelemetryController(devices, simulator);
    final recorder = TrialRecorder(
      telemetry,
      patients,
      RecordingDraftStore(directory),
    );
    patients.editingLocked = () => recorder.locked;
    telemetry.sourceLocked = () => recorder.locked;
    await recorder.loadRecovery();
    return AppDependencies._(
      patients: patients,
      devices: devices,
      simulator: simulator,
      telemetry: telemetry,
      recorder: recorder,
    );
  }

  void dispose() {
    recorder.dispose();
    telemetry.dispose();
    simulator.dispose();
    devices.dispose();
    patients.dispose();
  }
}
