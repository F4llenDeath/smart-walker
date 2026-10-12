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
  SensorPhase phase = SensorPhase.disconnected;
  String? deviceId;
  String? error;
  DateTime? lastReceived;
  int? lastReceiptMilliseconds;
  int? waitingSinceMilliseconds;
  double? value;
  double? speed;

  void clear() {
    phase = SensorPhase.disconnected;
    deviceId = null;
    error = null;
    lastReceived = null;
    lastReceiptMilliseconds = null;
    waitingSinceMilliseconds = null;
    value = null;
    speed = null;
  }
}
