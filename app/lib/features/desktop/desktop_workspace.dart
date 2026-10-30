import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../application/trial_recorder.dart';
import '../../domain/models/trial.dart';
import '../dashboard/live_session_content.dart';
import '../dashboard/trial_recording_bar.dart';
import '../devices/connection_status_button.dart';
import '../trials/trial_detail_page.dart';
import 'patient_trial_sidebar.dart';

/// Keeps desktop navigation inside the content pane, not around the sidebar.
class DesktopWorkspace extends StatefulWidget {
  const DesktopWorkspace({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  String? _trialId;
  late String _patientId;

  @override
  void initState() {
    super.initState();
    _patientId = widget.dependencies.patients.selected.id;
    widget.dependencies.patients.addListener(_patientsChanged);
    widget.dependencies.recorder.addListener(_recordingChanged);
  }

  Trial? get _selectedTrial {
    for (final trial in widget.dependencies.patients.selected.trials) {
      if (trial.id == _trialId) return trial;
    }
    return null;
  }

  void _patientsChanged() {
    final id = widget.dependencies.patients.selected.id;
    if (id != _patientId || (_trialId != null && _selectedTrial == null)) {
      setState(() {
        _patientId = id;
        _trialId = null;
      });
    }
  }

  void _showLive() {
    if (_trialId != null) setState(() => _trialId = null);
  }

  void _recordingChanged() {
    if (widget.dependencies.recorder.state == RecorderState.saveFailed) {
      _showLive();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.dependencies.patients,
    builder: (context, _) {
      final dependencies = widget.dependencies;
      final trial = _selectedTrial;
      final detailKey = trial == null
          ? null
          : ValueKey('$_patientId/${trial.id}');
      return FScaffold(
        childPad: false,
        scaffoldStyle: const FScaffoldStyleDelta.delta(
          footerDecoration: DecorationDelta.boxDelta(border: Border()),
        ),
        sidebar: PatientTrialSidebar(
          dependencies: dependencies,
          selectedTrialId: _trialId,
          onTrial: (trial) => setState(() => _trialId = trial.id),
        ),
        footer: TrialRecordingBar(
          recorder: dependencies.recorder,
          onStarted: _showLive,
        ),
        child: Navigator(
          pages: [
            MaterialPage<void>(
              key: const ValueKey('desktop-live'),
              child: Column(
                children: [
                  FHeader(
                    title: const Text('Live measurements'),
                    suffixes: [
                      ConnectionStatusButton(
                        dependencies: dependencies,
                        usePopover: true,
                      ),
                    ],
                  ),
                  Expanded(
                    child: LiveSessionContent(
                      dependencies: dependencies,
                      showPatientSelector: false,
                      showHistory: false,
                    ),
                  ),
                ],
              ),
            ),
            if (trial != null)
              MaterialPage<void>(
                key: detailKey,
                name: '/patients/$_patientId/trials/${trial.id}',
                child: TrialDetailPage(
                  key: detailKey,
                  dependencies: dependencies,
                  patientId: _patientId,
                  trial: trial,
                  embedded: true,
                  onBack: _showLive,
                  headerActions: [
                    ConnectionStatusButton(
                      dependencies: dependencies,
                      usePopover: true,
                    ),
                  ],
                ),
              ),
          ],
          onDidRemovePage: (page) {
            if (page.key == detailKey &&
                _trialId == trial?.id &&
                _trialId != null) {
              _showLive();
            }
          },
        ),
      );
    },
  );

  @override
  void dispose() {
    widget.dependencies.patients.removeListener(_patientsChanged);
    widget.dependencies.recorder.removeListener(_recordingChanged);
    super.dispose();
  }
}
