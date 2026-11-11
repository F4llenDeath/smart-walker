import 'data_point.dart';
import 'sensor_status.dart';

/// A display-only snapshot. The recorder separately retains every trial sample.
class LiveTrialSeries {
  LiveTrialSeries({
    required this.startDate,
    required Iterable<DataPoint> samples,
    required Iterable<SensorRole> sensors,
  }) : samples = List.unmodifiable(samples),
       sensors = Set.unmodifiable(sensors);

  static const visibleWindow = Duration(seconds: 30);

  final DateTime startDate;
  final List<DataPoint> samples;
  final Set<SensorRole> sensors;

  double get maxSeconds {
    final latest = samples.isEmpty ? startDate : samples.last.timestamp;
    final seconds = latest.difference(startDate).inMicroseconds / 1000000;
    return seconds > visibleWindow.inSeconds
        ? seconds
        : visibleWindow.inSeconds.toDouble();
  }

  double get minSeconds => maxSeconds - visibleWindow.inSeconds;
}
