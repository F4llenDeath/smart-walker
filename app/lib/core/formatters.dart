import 'package:intl/intl.dart';

String measurement(double? value, {int decimals = 2}) =>
    value?.toStringAsFixed(decimals) ?? '—';

String elapsedText(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  final minutes = milliseconds ~/ 60000;
  final seconds = (milliseconds ~/ 1000) % 60;
  final centiseconds = (milliseconds ~/ 10) % 100;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${centiseconds.toString().padLeft(2, '0')}';
}

String durationText(Duration duration) {
  final seconds = duration.inSeconds;
  return seconds >= 60 ? '${seconds ~/ 60}m ${seconds % 60}s' : '${seconds}s';
}

String dateTimeText(DateTime date) =>
    DateFormat.yMMMd().add_jm().format(date.toLocal());

String timeText(DateTime date) => DateFormat.jms().format(date.toLocal());
