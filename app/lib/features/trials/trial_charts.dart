import 'package:material_ui/material_ui.dart';

import '../../domain/models/trial.dart';
import '../../shared/widgets/measurement_charts.dart';
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
    return MeasurementCharts(
      startDate: trial.startDate,
      samples: trial.dataPoints,
    );
  }
}
