import 'battery_status.dart';
import 'radar_frame.dart';

enum SensorRole {
  leftFoot('SW-LeftFoot', 'Left foot'),
  rightFoot('SW-RightFoot', 'Right foot'),
  radar('SW-Radar', 'Radar');

  const SensorRole(this.deviceName, this.label);
  final String deviceName;
  final String label;
}

enum SensorPhase {
  disconnected,
  connecting,
  discovering,
  subscribing,
  waiting,
  ready,
  stale,
  error;

  String get label => switch (this) {
    SensorPhase.waiting => 'Waiting for data',
    SensorPhase.disconnected => 'Disconnected',
    SensorPhase.connecting => 'Connecting',
    SensorPhase.discovering => 'Discovering services',
    SensorPhase.subscribing => 'Subscribing',
    SensorPhase.ready => 'Ready',
    SensorPhase.stale => 'Stale data',
    SensorPhase.error => 'Error',
  };
}

enum AdapterState { unknown, resetting, unsupported, unauthorized, off, on }

class SensorStatus {
  SensorStatus(this.role);

  final SensorRole role;
  final BatteryStatus battery = BatteryStatus();
  SensorPhase phase = SensorPhase.disconnected;
  bool connected = false;
  String? deviceId;
  String? error;
  DateTime? lastReceived;
  int? lastReceiptMilliseconds;
  int? waitingSinceMilliseconds;
  double? value;
  double? speed;

  /// Valid speed from the current fresh radar frame, not the trial target lock.
  /// [speed] may remain cached for display after this becomes false.
  bool radarSpeedAvailable = false;
  RadarFrame? radarFrame;
  int radarSourceEpoch = 0;

  void clear() {
    battery.reset();
    phase = SensorPhase.disconnected;
    connected = false;
    deviceId = null;
    error = null;
    lastReceived = null;
    lastReceiptMilliseconds = null;
    waitingSinceMilliseconds = null;
    value = null;
    speed = null;
    radarSpeedAvailable = false;
    radarFrame = null;
    radarSourceEpoch = 0;
  }
}
