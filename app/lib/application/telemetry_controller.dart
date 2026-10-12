import 'package:flutter/foundation.dart';

import '../domain/models/sensor_status.dart';
import '../domain/models/telemetry_snapshot.dart';
import '../domain/models/trial.dart';
import 'device_coordinator.dart';
import 'simulation_source.dart';

class TelemetryController extends ChangeNotifier {
  TelemetryController(this.devices, this.simulator) {
    devices.addListener(_changed);
    simulator.addListener(_changed);
  }

  final DeviceCoordinator devices;
  final SimulationSource simulator;
  bool simulating = false;
  bool switching = false;
  bool foreground = true;
  bool Function() sourceLocked = () => false;

  void _changed() => notifyListeners();

  TelemetrySnapshot get snapshot {
    if (switching || !foreground) {
      return TelemetrySnapshot(
        source: simulating ? DataSource.simulation : DataSource.hardware,
      );
    }
    if (simulating) return simulator.snapshot;
    final left = devices.sensors[SensorRole.leftFoot]!;
    final right = devices.sensors[SensorRole.rightFoot]!;
    final radar = devices.sensors[SensorRole.radar]!;
    return TelemetrySnapshot(
      source: DataSource.hardware,
      weightLeft: left.phase == SensorPhase.ready ? left.value : null,
      weightRight: right.phase == SensorPhase.ready ? right.value : null,
      distanceFt: radar.phase == SensorPhase.ready ? radar.value : null,
      speedFtS: radar.phase == SensorPhase.ready ? radar.speed : null,
      leftReady: left.phase == SensorPhase.ready,
      rightReady: right.phase == SensorPhase.ready,
      radarReady: radar.phase == SensorPhase.ready,
    );
  }

  Future<void> setSimulation(bool enabled) async {
    if (sourceLocked() || switching || enabled == simulating) return;
    switching = true;
    notifyListeners();
    try {
      if (enabled) {
        await devices.suspend();
        simulating = true;
        if (foreground) simulator.start();
      } else {
        simulator.stop();
        simulating = false;
        if (foreground) await devices.start(requestPermissions: true);
      }
    } finally {
      switching = false;
      notifyListeners();
    }
  }

  Future<void> suspend() async {
    foreground = false;
    simulator.stop(reset: false);
    notifyListeners();
    await devices.suspend();
  }

  Future<void> resume() async {
    foreground = true;
    if (simulating) {
      simulator.start();
    } else {
      await devices.start();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    devices.removeListener(_changed);
    simulator.removeListener(_changed);
    super.dispose();
  }
}
