import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../domain/models/data_point.dart';
import 'panels.dart';

/// Shared presentation for a saved trial or a bounded live recording window.
/// Chart-only sorting and filtering never alter the recorder's stored samples.
class MeasurementCharts extends StatelessWidget {
  const MeasurementCharts({
    required this.startDate,
    required this.samples,
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
        _MeasurementChart(
          startDate: startDate,
          samples: points,
          weights: false,
          minSeconds: minSeconds,
          maxSeconds: right,
          live: live,
          height: chartHeight,
        ),
        const SizedBox(height: 16),
        _MeasurementChart(
          startDate: startDate,
          samples: points,
          weights: true,
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
    required this.minSeconds,
    required this.maxSeconds,
    required this.live,
    required this.height,
  });

  final DateTime startDate;
  final List<DataPoint> samples;
  final bool weights;
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
    final lines = widget.weights
        ? [
            widget.samples
                .map((point) => FlSpot(_seconds(point), point.weightLeft))
                .toList(),
            widget.samples
                .map((point) => FlSpot(_seconds(point), point.weightRight))
                .toList(),
          ]
        : [
            widget.samples
                .map((point) => FlSpot(_seconds(point), point.speedFtS))
                .toList(),
          ];
    final values = lines.expand((line) => line.map((spot) => spot.y)).toList();
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
    final colors = [const Color(0xFF3B82F6), const Color(0xFFF97316)];
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
      subtitle: widget.weights ? 'Left (blue) · Right (orange) · lbs' : 'ft/s',
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
                                  color: colors[spot.barIndex],
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
                            color: colors[index],
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
                if (widget.samples.isEmpty)
                  Center(
                    child: Text(
                      'Waiting for samples…',
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
