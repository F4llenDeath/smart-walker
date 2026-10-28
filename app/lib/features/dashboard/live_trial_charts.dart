import 'package:material_ui/material_ui.dart';

import '../../application/trial_recorder.dart';
import '../../domain/models/live_trial_series.dart';
import '../../shared/widgets/measurement_charts.dart';

class LiveTrialCharts extends StatelessWidget {
  const LiveTrialCharts({required this.recorder, super.key});

  final TrialRecorder recorder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<LiveTrialSeries?>(
        valueListenable: recorder.liveSeries,
        builder: (context, series, _) {
          if (series == null) return const SizedBox.shrink();
          return RepaintBoundary(
            child: MeasurementCharts(
              key: ValueKey(series.startDate),
              startDate: series.startDate,
              samples: series.samples,
              minSeconds: series.minSeconds,
              maxSeconds: series.maxSeconds,
              live: true,
              chartHeight: 200,
            ),
          );
        },
      );
}
