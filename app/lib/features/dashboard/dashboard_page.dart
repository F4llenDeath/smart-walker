import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../devices/connection_status_button.dart';
import 'live_session_content.dart';
import 'trial_recording_bar.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) => FScaffold(
    childPad: false,
    scaffoldStyle: const FScaffoldStyleDelta.delta(
      footerDecoration: DecorationDelta.boxDelta(border: Border()),
    ),
    footer: TrialRecordingBar(recorder: dependencies.recorder),
    header: FHeader(
      title: const Text('Smart Walker'),
      suffixes: [ConnectionStatusButton(dependencies: dependencies)],
    ),
    child: LiveSessionContent(dependencies: dependencies),
  );
}
