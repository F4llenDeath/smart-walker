import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/ble_protocol.dart';
import '../domain/models/telemetry_snapshot.dart';
import '../domain/models/trial.dart';

class SimulationSource extends ChangeNotifier {
  final Random _random = Random();
  Timer? _timer;
  double _distance = 0;
  TelemetrySnapshot snapshot = const TelemetrySnapshot(
    source: DataSource.simulation,
  );

  void start() {
    _timer?.cancel();
    _emit();
    _timer = Timer.periodic(BleProtocol.sampleInterval, (_) => _emit());
  }

  void _emit() {
    final speed = 0.5 + _random.nextDouble() * 1.5;
    _distance += speed * 0.2;
    snapshot = TelemetrySnapshot(
      source: DataSource.simulation,
      weightLeft: 20 + _random.nextDouble() * 20,
      weightRight: 20 + _random.nextDouble() * 20,
      distanceFt: _distance,
      speedFtS: speed,
      leftReady: true,
      rightReady: true,
      radarReady: true,
    );
    notifyListeners();
  }

  void stop({bool reset = true}) {
    _timer?.cancel();
    _timer = null;
    if (reset) _distance = 0;
    snapshot = const TelemetrySnapshot(source: DataSource.simulation);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
