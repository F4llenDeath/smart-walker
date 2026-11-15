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
  RadarFrame? _pending;
  RadarFrame? _lastSeen;
  String? pauseReason;
  String? failure;

  bool get available => pauseReason == null && failure == null;
  double get displayDistanceFt =>
      max(0, initialRangeMeters - _filteredRange) * metersToFeet;
  double? get distanceFt => available ? displayDistanceFt : null;

  void pause(String reason) {
    pauseReason = failure ?? reason;
    _pending = null;
  }

  void sourceRestarted() {
    failure =
        'Radar source restarted; distance remains paused until the next trial.';
    pause(failure!);
  }

  void update(RadarFrame frame) {
    if (failure != null) return;
    if (frame.session != session) {
      sourceRestarted();
      return;
    }
    if (frame.number == _lastSeen?.number ||
        frame.number == _lastFrame.number) {
      return;
    }
    _lastSeen = frame;
    final delta = frame.acquiredMilliseconds - _lastFrame.acquiredMilliseconds;
    if (delta <= 0) {
      sourceRestarted();
      return;
    }
    if (frame.overflow) {
      pause('Radar point overflow; distance paused.');
      return;
    }
    if (delta > maximumGapMilliseconds && pauseReason == null) {
      pause('Radar frame gap; waiting for a consistent target.');
    }
    // Cap the gate even after a long outage; never absorb a distant stranger.
    final rangeGate =
        rangeNoiseMeters +
        maximumSpeedMetersPerSecond * min(delta, maximumGapMilliseconds) / 1000;
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
      pause('Trial target unavailable; distance paused.');
      return;
    }
    if (pauseReason != null) {
      final pending = _pending;
      if (pending == null) {
        _pending = RadarFrame(
          session: frame.session,
          number: frame.number,
          cpuCycles: frame.cpuCycles,
          acquiredMilliseconds: frame.acquiredMilliseconds,
          receivedMilliseconds: frame.receivedMilliseconds,
          points: [selected],
        );
        return;
      }
      final step = frame.acquiredMilliseconds - pending.acquiredMilliseconds;
      final candidate = pending.points.single;
      if (step <= 0 ||
          step > maximumGapMilliseconds ||
          (selected.rangeMeters - candidate.rangeMeters).abs() >
              rangeNoiseMeters + maximumSpeedMetersPerSecond * step / 1000 ||
          sqrt(
                pow(selected.x - candidate.x, 2) +
                    pow(selected.z - candidate.z, 2),
              ) >
              lateralGate) {
        pause('Waiting for two consistent target frames.');
        return;
      }
      _pending = null;
      pauseReason = null;
      _ranges.clear();
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
