import 'sensor_status.dart';
import 'trial.dart';

class TelemetrySnapshot {
  const TelemetrySnapshot({
    required this.source,
    this.weightLeft,
    this.weightRight,
    this.distanceFt,
    this.speedFtS,
    this.leftReady = false,
    this.rightReady = false,
    this.radarReady = false,
  });

  final DataSource source;
  final double? weightLeft;
  final double? weightRight;
  final double? distanceFt;
  final double? speedFtS;
  final bool leftReady;
  final bool rightReady;
  final bool radarReady;

  bool isReady(SensorRole role) => switch (role) {
    SensorRole.leftFoot => leftReady && weightLeft?.isFinite == true,
    SensorRole.rightFoot => rightReady && weightRight?.isFinite == true,
    SensorRole.radar =>
      radarReady && distanceFt?.isFinite == true && speedFtS?.isFinite == true,
  };
  Set<SensorRole> get readySensors =>
      Set.unmodifiable(SensorRole.values.where(isReady));
  bool readyFor(Iterable<SensorRole> sensors) =>
      sensors.isNotEmpty && sensors.every(isReady);
  bool get ready => readyFor(SensorRole.values);
  int get readyCount => readySensors.length;
  double? get weightTotal =>
      isReady(SensorRole.leftFoot) && isReady(SensorRole.rightFoot)
      ? weightLeft! + weightRight!
      : null;

  /// A recording never absorbs measurements from a sensor that joined later.
  TelemetrySnapshot only(Set<SensorRole> sensors) {
    final left =
        sensors.contains(SensorRole.leftFoot) && isReady(SensorRole.leftFoot);
    final right =
        sensors.contains(SensorRole.rightFoot) && isReady(SensorRole.rightFoot);
    final radar =
        sensors.contains(SensorRole.radar) && isReady(SensorRole.radar);
    return TelemetrySnapshot(
      source: source,
      weightLeft: left ? weightLeft : null,
      weightRight: right ? weightRight : null,
      distanceFt: radar ? distanceFt : null,
      speedFtS: radar ? speedFtS : null,
      leftReady: left,
      rightReady: right,
      radarReady: radar,
    );
  }
}
