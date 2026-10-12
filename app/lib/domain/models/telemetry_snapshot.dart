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

  bool get ready => leftReady && rightReady && radarReady;
  int get readyCount =>
      (leftReady ? 1 : 0) + (rightReady ? 1 : 0) + (radarReady ? 1 : 0);
  double? get weightTotal =>
      leftReady && rightReady ? weightLeft! + weightRight! : null;
}
