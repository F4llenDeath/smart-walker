import 'data_point.dart';

/// A display-only snapshot. The recorder separately retains every trial sample.
class LiveTrialSeries {
  LiveTrialSeries({
    required this.startDate,
    required Iterable<DataPoint> samples,
  }) : samples = List.unmodifiable(samples);

  static const visibleWindow = Duration(seconds: 30);

  final DateTime startDate;
  final List<DataPoint> samples;

  double get maxSeconds {
    final latest = samples.isEmpty ? startDate : samples.last.timestamp;
    final seconds = latest.difference(startDate).inMicroseconds / 1000000;
    return seconds > visibleWindow.inSeconds
        ? seconds
        : visibleWindow.inSeconds.toDouble();
  }

  double get minSeconds => maxSeconds - visibleWindow.inSeconds;
}
