enum BatteryLevel { unknown, high, medium, low }

enum BatteryAvailability { waiting, available, unsupported, unavailable, stale }

/// Live, optional device status. Never participates in recording readiness.
class BatteryStatus {
  static const freshness = Duration(seconds: 45);
  // Provisional loaded-cell voltage bands, not a calibrated state-of-charge curve.
  static const lowMillivolts = 3600;
  static const highMillivolts = 3900;
  static const hysteresisMillivolts = 100;

  BatteryLevel level = BatteryLevel.unknown;
  BatteryAvailability availability = BatteryAvailability.waiting;
  int? millivolts;
  int? lastReceiptMilliseconds;

  void receive(int? value, int nowMilliseconds) {
    if (value == null) {
      reset(BatteryAvailability.unavailable);
      return;
    }
    millivolts = value;
    lastReceiptMilliseconds = nowMilliseconds;
    availability = BatteryAvailability.available;
    level = switch (value) {
      <= lowMillivolts => BatteryLevel.low,
      >= highMillivolts => BatteryLevel.high,
      _
          when level == BatteryLevel.low &&
              value < lowMillivolts + hysteresisMillivolts =>
        BatteryLevel.low,
      _
          when level == BatteryLevel.high &&
              value >= highMillivolts - hysteresisMillivolts =>
        BatteryLevel.high,
      _ => BatteryLevel.medium,
    };
  }

  bool expire(int nowMilliseconds) {
    final receipt = lastReceiptMilliseconds;
    if (receipt == null ||
        nowMilliseconds - receipt <= freshness.inMilliseconds) {
      return false;
    }
    reset(BatteryAvailability.stale);
    return true;
  }

  void reset([BatteryAvailability state = BatteryAvailability.waiting]) {
    level = BatteryLevel.unknown;
    availability = state;
    millivolts = null;
    lastReceiptMilliseconds = null;
  }
}
