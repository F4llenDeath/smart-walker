import 'dart:math';

import '../domain/models/radar_frame.dart';

/// Trial-only range association. Speed selection never drives this calculation.
class RadarDistanceTracker {
  RadarDistanceTracker(RadarFrame frame, RadarPoint target)
    : session = frame.session,
      initialRangeMeters = target.rangeMeters,
      _previous = target,
      _lastFrame = frame,
      _filteredRange = target.rangeMeters,
      _ranges = [target.rangeMeters];

  static const metersToFeet = 3.28084;
  // Provisional hardware-tuning parameters, not demonstrated accuracy bounds.
  static const maximumSpeedMetersPerSecond = 1.5;
  static const rangeNoiseMeters = 0.15;
  static const maximumGapMilliseconds = 1000;

  final int session;
  final double initialRangeMeters;
  RadarPoint _previous;
  RadarFrame _lastFrame;
  double _filteredRange;
  final List<double> _ranges;
  String? failure;

  double? get distanceFt => failure == null
      ? max(0, initialRangeMeters - _filteredRange) * metersToFeet
      : null;

  void update(RadarFrame frame) {
    if (failure != null) return;
    if (frame.session != session) {
      failure = 'Radar source restarted during the trial.';
      return;
    }
    if (frame.number == _lastFrame.number) return;
    final delta = frame.acquiredMilliseconds - _lastFrame.acquiredMilliseconds;
    if (delta <= 0 || delta > maximumGapMilliseconds || frame.overflow) {
      failure = 'Radar target frame timing/data became unavailable.';
      return;
    }
    final rangeGate =
        rangeNoiseMeters + maximumSpeedMetersPerSecond * delta / 1000;
    final lateralGate = 0.3 + 0.2 * _previous.rangeMeters;
    RadarPoint? selected;
    var best = double.infinity;
    for (final point in frame.points) {
      if (!point.eligible) continue;
      final rangeChange = (point.rangeMeters - _previous.rangeMeters).abs();
      final lateralChange = sqrt(
        pow(point.x - _previous.x, 2) + pow(point.z - _previous.z, 2),
      );
      if (rangeChange > rangeGate || lateralChange > lateralGate) continue;
      final score = rangeChange / rangeGate + lateralChange / lateralGate;
      if (score < best) {
        selected = point;
        best = score;
      }
    }
    if (selected == null) {
      // Never relock to the nearest stranger, hold a fake sample, or extrapolate.
      failure = 'The trial radar target was lost or jumped outside its tracking window.';
      return;
    }
    _previous = selected;
    _lastFrame = frame;
    _ranges.add(selected.rangeMeters);
    if (_ranges.length > 3) _ranges.removeAt(0);
    final sorted = _ranges.toList()..sort();
    _filteredRange = sorted.length.isOdd
        ? sorted[sorted.length ~/ 2]
        : (sorted.first + sorted.last) / 2;
  }
}
