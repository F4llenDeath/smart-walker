import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models/data_point.dart';
import '../../domain/models/trial.dart';
import '../../shared/widgets/panels.dart';

class TrialCharts extends StatelessWidget {
  const TrialCharts({required this.trial, super.key});
  final Trial trial;

  @override
  Widget build(BuildContext context) {
    if (trial.sampleCount < 2) {
      return const SectionCard(
        title: 'Charts',
        child: Text('At least two samples are needed to draw a chart.'),
      );
    }
    return Column(
      children: [
        _TrialChart(trial: trial, weights: false),
        const SizedBox(height: 16),
        _TrialChart(trial: trial, weights: true),
      ],
    );
  }
}

class _TrialChart extends StatelessWidget {
  const _TrialChart({required this.trial, required this.weights});
  final Trial trial;
  final bool weights;

  @override
  Widget build(BuildContext context) {
    // Legacy Swift serialization may collapse five sample timestamps into one
    // second. Preserve every stored sample and allow repeated X coordinates.
    final indexed = trial.dataPoints.indexed.toList()
      ..sort((a, b) {
        final byTime = a.$2.timestamp.compareTo(b.$2.timestamp);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    final points = indexed.map((entry) => entry.$2).toList();
    List<FlSpot> spots(double Function(DataPoint) value) => points
        .map(
          (point) => FlSpot(
            max(
              0,
              point.timestamp.difference(trial.startDate).inMicroseconds /
                  1000000,
            ),
            value(point),
          ),
        )
        .toList();
    final lines = weights
        ? [
            spots((point) => point.weightLeft),
            spots((point) => point.weightRight),
          ]
        : [spots((point) => point.speedFtS)];
    final values = lines.expand((line) => line.map((spot) => spot.y));
    final lowest = min(0.0, values.reduce(min));
    final highest = max(0.0, values.reduce(max));
    final padding = max(1.0, (highest - lowest) * 0.12);
    final maxX = max(1.0, lines.first.last.x);
    final colors = [const Color(0xFF3B82F6), const Color(0xFFF97316)];
    final textColor = context.theme.colors.mutedForeground;
    final axisStyle = TextStyle(fontSize: 11, color: textColor);
    return SectionCard(
      title: weights ? 'Weight distribution' : 'Walking speed',
      subtitle: weights ? 'Left (blue) · Right (orange) · lbs' : 'ft/s',
      child: Column(
        children: [
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX,
                minY: lowest < 0 ? lowest - padding : 0,
                maxY: highest + padding,
                lineBarsData: [
                  for (var index = 0; index < lines.length; index++)
                    LineChartBarData(
                      spots: lines[index],
                      color: colors[index],
                      barWidth: 2,
                      isCurved: false,
                      dotData: const FlDotData(show: false),
                    ),
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
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
                      interval: maxX / 4,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          value.toStringAsFixed(maxX < 4 ? 1 : 0),
                          style: axisStyle,
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      interval:
                          (highest +
                              padding -
                              (lowest < 0 ? lowest - padding : 0)) /
                          4,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(value.toStringAsFixed(1), style: axisStyle),
                      ),
                    ),
                  ),
                ),
              ),
              duration: Duration.zero,
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
