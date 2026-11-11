import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../domain/models/data_point.dart';
import '../../domain/models/sensor_status.dart';
import 'panels.dart';

/// Shared presentation for a saved trial or a bounded live recording window.
/// Chart-only sorting and filtering never alter the recorder's stored samples.
class MeasurementCharts extends StatelessWidget {
  const MeasurementCharts({
    required this.startDate,
    required this.samples,
    required this.sensors,
    this.minSeconds = 0,
    this.maxSeconds,
    this.live = false,
    this.chartHeight = 240,
    super.key,
  }) : assert(minSeconds >= 0),
       assert(maxSeconds == null || maxSeconds > minSeconds),
       assert(chartHeight > 0);

  final DateTime startDate;
  final List<DataPoint> samples;
  final Set<SensorRole> sensors;
  final double minSeconds;
  final double? maxSeconds;
  final bool live;
  final double chartHeight;

  @override
  Widget build(BuildContext context) {
    // Legacy Swift serialization may assign the same timestamp to several
    // samples. Preserve their recorded order when timestamps compare equal.
    final indexed = samples.indexed.toList()
      ..sort((a, b) {
        final byTime = a.$2.timestamp.compareTo(b.$2.timestamp);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    final points = indexed.map((entry) => entry.$2).toList();
    final latestSeconds = points.isEmpty
        ? 0.0
        : max(
            0.0,
            points.last.timestamp.difference(startDate).inMicroseconds /
                1000000,
          );
    final right = maxSeconds ?? max(minSeconds + 1, latestSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sensors.contains(SensorRole.radar))
          _MeasurementChart(
            startDate: startDate,
            samples: points,
            weights: false,
            sensors: sensors,
            minSeconds: minSeconds,
            maxSeconds: right,
            live: live,
            height: chartHeight,
          ),
        if (sensors.contains(SensorRole.radar) &&
            (sensors.contains(SensorRole.leftFoot) ||
                sensors.contains(SensorRole.rightFoot)))
          const SizedBox(height: 16),
        if (sensors.contains(SensorRole.leftFoot) ||
            sensors.contains(SensorRole.rightFoot))
          _MeasurementChart(
            startDate: startDate,
            samples: points,
            weights: true,
            sensors: sensors,
            minSeconds: minSeconds,
            maxSeconds: right,
            live: live,
            height: chartHeight,
          ),
      ],
    );
  }
}

class _MeasurementChart extends StatefulWidget {
  const _MeasurementChart({
    required this.startDate,
    required this.samples,
    required this.weights,
    required this.sensors,
    required this.minSeconds,
    required this.maxSeconds,
    required this.live,
    required this.height,
  });

  final DateTime startDate;
  final List<DataPoint> samples;
  final bool weights;
  final Set<SensorRole> sensors;
  final double minSeconds;
  final double maxSeconds;
  final bool live;
  final double height;

  @override
  State<_MeasurementChart> createState() => _MeasurementChartState();
}

class _MeasurementChartState extends State<_MeasurementChart> {
  double? _liveMinY;
  double? _liveMaxY;

  @override
  void didUpdateWidget(covariant _MeasurementChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate ||
        oldWidget.weights != widget.weights ||
        oldWidget.live != widget.live) {
      _liveMinY = null;
      _liveMaxY = null;
    }
  }

  double _seconds(DataPoint point) => max(
    0.0,
    point.timestamp.difference(widget.startDate).inMicroseconds / 1000000,
  );

  @override
  Widget build(BuildContext context) {
    final series = <(String, Color, double? Function(DataPoint))>[
      if (widget.weights) ...[
        if (widget.sensors.contains(SensorRole.leftFoot))
          ('Left', const Color(0xFF3B82F6), (point) => point.weightLeft),
        if (widget.sensors.contains(SensorRole.rightFoot))
          ('Right', const Color(0xFFF97316), (point) => point.weightRight),
      ] else
        ('Speed', const Color(0xFF3B82F6), (point) => point.speedFtS),
    ];
    final lines = [
      for (final (_, _, value) in series)
        widget.samples.map((point) {
          final measurement = value(point);
          return measurement == null
              ? FlSpot.nullSpot
              : FlSpot(_seconds(point), measurement);
        }).toList(),
    ];
    final values = lines
        .expand(
          (line) =>
              line.where((spot) => spot.isNotNull()).map((spot) => spot.y),
        )
        .toList();
    final lowest = values.fold<double>(0, min);
    final highest = values.fold<double>(0, max);
    final padding = max(1.0, (highest - lowest) * 0.12);
    var minY = lowest < 0 ? lowest - padding : 0.0;
    var maxY = highest + padding;

    if (widget.live) {
      // Expand to rounded bounds when necessary, but do not shrink on each new
      // sample. This prevents the live Y-axis from jumping at 5 Hz.
      final step = widget.weights ? 10.0 : 1.0;
      final proposedMin = (minY / step).floor() * step;
      final proposedMax = (maxY / step).ceil() * step;
      if (values.isNotEmpty) {
        _liveMinY = min(_liveMinY ?? proposedMin, proposedMin);
        _liveMaxY = max(_liveMaxY ?? proposedMax, proposedMax);
      }
      minY = _liveMinY ?? 0;
      maxY = _liveMaxY ?? (widget.weights ? 100 : 5);
    }

    final span = widget.maxSeconds - widget.minSeconds;
    final textColor = context.theme.colors.mutedForeground;
    final axisStyle = TextStyle(fontSize: 11, color: textColor);
    final visibleCount = widget.samples
        .where(
          (point) =>
              _seconds(point) >= widget.minSeconds &&
              _seconds(point) <= widget.maxSeconds,
        )
        .length;

    return SectionCard(
      title: widget.weights ? 'Weight distribution' : 'Walking speed',
      subtitle: widget.weights
          ? '${series.map((line) => '${line.$1} (${line.$1 == 'Left' ? 'blue' : 'orange'})').join(' · ')} · lbs'
          : 'ft/s',
      child: Column(
        children: [
          SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: LineChart(
                    LineChartData(
                      minX: widget.minSeconds,
                      maxX: widget.maxSeconds,
                      minY: minY,
                      maxY: maxY,
                      clipData: const FlClipData.all(),
                      lineTouchData: LineTouchData(
                        enabled: !widget.live,
                        touchTooltipData: LineTouchTooltipData(
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItems: (spots) => [
                            for (final spot in spots)
                              LineTooltipItem(
                                measurement(spot.y),
                                TextStyle(
                                  color: series[spot.barIndex].$2,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                          ],
                        ),
                      ),
                      lineBarsData: [
                        for (var index = 0; index < lines.length; index++)
                          LineChartBarData(
                            spots: lines[index],
                            color: series[index].$2,
                            barWidth: 2,
                            isCurved: false,
                            dotData: FlDotData(show: visibleCount == 1),
                          ),
                      ],
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: (maxY - minY) / 4,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: context.theme.colors.border,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: widget.live ? 10 : span / 4,
                            minIncluded: !widget.live,
                            maxIncluded: !widget.live,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text(
                                value.toStringAsFixed(span < 4 ? 1 : 0),
                                style: axisStyle,
                              ),
                            ),
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 48,
                            interval: (maxY - minY) / 4,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text(
                                value.toStringAsFixed(1),
                                style: axisStyle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    duration: Duration.zero,
                  ),
                ),
                if (values.isEmpty)
                  Center(
                    child: Text(
                      widget.samples.isEmpty
                          ? 'Waiting for samples…'
                          : 'No measurements recorded',
                      style: TextStyle(color: textColor),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            'Elapsed time (seconds)',
            style: TextStyle(color: textColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
