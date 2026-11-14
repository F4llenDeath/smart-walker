import 'dart:math';

class RadarPoint {
  const RadarPoint(this.x, this.y, this.z, this.radialVelocity);

  final double x;
  final double y;
  final double z;
  final double radialVelocity;

  double get rangeMeters => sqrt(x * x + y * y + z * z);

  /// Matches the controlled forward-wall setup, not arbitrary environments.
  bool get eligible =>
      y >= 0.3 &&
      rangeMeters <= 9.7 &&
      atan2(x.abs(), y) <= 20 * pi / 180 &&
      atan2(z.abs(), sqrt(x * x + y * y)) <= 20 * pi / 180;
}

/// A complete new UART frame, never a repeat of a cached BLE measurement.
class RadarFrame {
  RadarFrame({
    required this.session,
    required this.number,
    required this.cpuCycles,
    required this.acquiredMilliseconds,
    required this.receivedMilliseconds,
    required Iterable<RadarPoint> points,
    this.overflow = false,
  }) : points = List.unmodifiable(points);

  final int session;
  final int number;
  final int cpuCycles;
  final int acquiredMilliseconds;
  final int receivedMilliseconds;
  final List<RadarPoint> points;
  final bool overflow;

  RadarPoint? get nearest {
    if (overflow) return null;
    RadarPoint? selected;
    for (final point in points) {
      if (point.eligible &&
          (selected == null || point.rangeMeters < selected.rangeMeters)) {
        selected = point;
      }
    }
    return selected;
  }
}
