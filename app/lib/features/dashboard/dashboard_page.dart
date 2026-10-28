import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../application/trial_recorder.dart';
import '../../core/formatters.dart';
import '../../shared/widgets/panels.dart';
import '../devices/device_status_panel.dart';
import '../patients/patient_picker.dart';
import '../trials/trial_detail_page.dart';
import 'live_trial_charts.dart';
import 'trial_recording_bar.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      dependencies.patients,
      dependencies.recorder,
    ]),
    builder: (context, _) {
      final patients = dependencies.patients;
      final telemetry = dependencies.telemetry;
      final recorder = dependencies.recorder;
      return FScaffold(
        childPad: false,
        scaffoldStyle: const FScaffoldStyleDelta.delta(
          footerDecoration: DecorationDelta.boxDelta(border: Border()),
        ),
        footer: TrialRecordingBar(recorder: recorder),
        header: FHeader(
          title: const Text('Smart Walker'),
          suffixes: [
            ListenableBuilder(
              listenable: telemetry,
              builder: (context, _) => FButton(
                variant: FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                prefix: const Icon(FLucideIcons.bluetooth),
                onPress: () => showPanel(
                  context,
                  DeviceStatusPanel(dependencies: dependencies),
                ),
                child: Text(
                  telemetry.simulating
                      ? 'SIM'
                      : '${telemetry.snapshot.readyCount}/3',
                ),
              ),
            ),
          ],
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ListenableBuilder(
                  listenable: telemetry,
                  builder: (context, _) => telemetry.simulating
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: NoticeBanner(
                            'Simulation mode',
                            message: 'These measurements are generated, not received from the walker.',
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (patients.error != null) ...[
                  NoticeBanner(
                    'Storage needs attention',
                    message: patients.error,
                    destructive: true,
                  ),
                  const SizedBox(height: 8),
                  if (!patients.ready)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FButton(
                          variant: FButtonVariant.outline,
                          mainAxisSize: MainAxisSize.min,
                          onPress:
                              patients.saving ||
                                  recorder.state != RecorderState.idle
                              ? null
                              : () async {
                                  await patients.initialize();
                                  if (patients.ready) {
                                    await recorder.loadRecovery();
                                  }
                                },
                          child: const Text('Reload data'),
                        ),
                        FButton(
                          variant: FButtonVariant.outline,
                          mainAxisSize: MainAxisSize.min,
                          onPress:
                              patients.saving ||
                                  recorder.state != RecorderState.idle
                              ? null
                              : () async {
                                  if (!await confirmAction(
                                    context,
                                    title: 'Restore previous backup?',
                                    message: 'Restore the previous successful save. The unreadable primary file is preserved separately.',
                                    action: 'Restore',
                                  )) {
                                    return;
                                  }
                                  await patients.initialize(
                                    restoreBackup: true,
                                  );
                                  if (patients.ready) {
                                    await recorder.loadRecovery();
                                  }
                                },
                          child: const Text('Restore backup'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                ],
                if (recorder.recovered != null &&
                    recorder.state == RecorderState.idle) ...[
                  SectionCard(
                    title: 'Interrupted recording found',
                    subtitle:
                        '${recorder.recovered!.patientName} · ${recorder.recovered!.trial.sampleCount} samples',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Save the recovered partial trial or discard it before starting a new one.',
                        ),
                        const SizedBox(height: 12),
                        FButton(
                          onPress: patients.ready && !patients.saving
                              ? recorder.saveRecovered
                              : null,
                          child: const Text('Save recovered trial'),
                        ),
                        const SizedBox(height: 8),
                        FButton(
                          variant: FButtonVariant.outline,
                          onPress: () async {
                            if (await confirmAction(
                              context,
                              title: 'Discard recovered recording?',
                              message: 'The recovered samples will be permanently deleted.',
                              action: 'Discard',
                            )) {
                              await recorder.discardRecovery();
                            }
                          },
                          child: const Text('Discard'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (recorder.error != null) ...[
                  NoticeBanner(
                    'Recording needs attention',
                    message: recorder.error,
                    destructive: true,
                  ),
                  const SizedBox(height: 8),
                  FButton(
                    variant: FButtonVariant.outline,
                    onPress: recorder.state == RecorderState.saveFailed
                        ? recorder.retrySave
                        : recorder.state == RecorderState.idle
                        ? recorder.loadRecovery
                        : null,
                    child: Text(
                      recorder.state == RecorderState.saveFailed
                          ? 'Retry save'
                          : 'Retry recovery loading',
                    ),
                  ),
                  if (recorder.state == RecorderState.idle &&
                      recorder.recovered == null) ...[
                    const SizedBox(height: 8),
                    FButton(
                      variant: FButtonVariant.outline,
                      onPress: () async {
                        if (await confirmAction(
                          context,
                          title: 'Remove unreadable recovery file?',
                          message: 'Only the pending recording file is removed. Saved patient data is not changed.',
                          action: 'Remove',
                        )) {
                          await recorder.discardRecovery();
                        }
                      },
                      child: const Text('Remove pending recovery'),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                if (recorder.notice != null) ...[
                  NoticeBanner(recorder.notice!),
                  const SizedBox(height: 16),
                ],
                FButton(
                  variant: FButtonVariant.outline,
                  prefix: const Icon(FLucideIcons.userRound),
                  suffix: const Icon(FLucideIcons.chevronDown),
                  onPress: !patients.ready || patients.saving || recorder.locked
                      ? null
                      : () => showPanel(
                          context,
                          PatientPicker(dependencies: dependencies),
                        ),
                  child: Text(
                    patients.selected.isUnassigned
                        ? 'Unassigned session'
                        : patients.selected.name,
                  ),
                ),
                const SizedBox(height: 20),
                ListenableBuilder(
                  listenable: telemetry,
                  builder: (context, _) {
                    final snapshot = telemetry.snapshot;
                    return FTileGroup.merge(
                      semanticsLabel: 'Live measurements',
                      physics: const NeverScrollableScrollPhysics(),
                      divider: FItemDivider.full,
                      children: [
                        FTileGroup(
                          divider: FItemDivider.none,
                          children: [
                            _metricTile(
                              context,
                              'Left weight',
                              snapshot.weightLeft,
                              'lbs',
                            ),
                            _metricTile(
                              context,
                              'Right weight',
                              snapshot.weightRight,
                              'lbs',
                            ),
                            _metricTile(
                              context,
                              'Total weight',
                              snapshot.weightTotal,
                              'lbs',
                            ),
                          ],
                        ),
                        FTileGroup(
                          divider: FItemDivider.none,
                          children: [
                            _metricTile(
                              context,
                              recorder.recording
                                  ? 'Trial distance'
                                  : 'Distance',
                              recorder.recording
                                  ? recorder.trialDistance
                                  : snapshot.distanceFt,
                              'ft',
                            ),
                            _metricTile(
                              context,
                              'Speed',
                              snapshot.speedFtS,
                              'ft/s',
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                if (recorder.recording) ...[
                  const SizedBox(height: 20),
                  LiveTrialCharts(recorder: recorder),
                ],
                const SizedBox(height: 24),
                Text(
                  'Past trials · ${patients.selected.name}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (patients.trials.isEmpty)
                  const SectionCard(
                    title: 'No trials yet',
                    child: Text(
                      'Record a session to view its measurements and charts here.',
                    ),
                  ),
                for (final trial in patients.trials)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FButton(
                      variant: FButtonVariant.outline,
                      suffix: const Icon(FLucideIcons.chevronRight),
                      onPress: () {
                        final patientId = patients.selected.id;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TrialDetailPage(
                              dependencies: dependencies,
                              patientId: patientId,
                              trial: trial,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dateTimeText(trial.startDate)),
                            const SizedBox(height: 4),
                            Text(
                              '${durationText(trial.duration)} · ${trial.totalDistance.toStringAsFixed(1)} ft · ${trial.source.name}',
                              style: const TextStyle(
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
    },
  );

  FTile _metricTile(
    BuildContext context,
    String label,
    double? value,
    String unit,
  ) {
    final title = Text(
      '$label ($unit)',
      overflow: TextOverflow.visible,
      style: TextStyle(color: context.theme.colors.mutedForeground),
    );
    final reading = Text(
      measurement(value),
      textAlign: TextAlign.end,
      style: TextStyle(
        color: context.theme.colors.foreground,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    // Keep one metric per row even when large text needs a taller layout.
    // FTile.raw avoids the standard title/details truncation in that case.
    if (MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(16) >= 24) {
      return FTile.raw(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [title, const SizedBox(height: 4), reading],
        ),
      );
    }
    return FTile(
      title: title,
      // Non-text details receive layout priority in Forui, so labels can wrap
      // instead of truncating a measurement when horizontal space is tight.
      details: Align(
        alignment: AlignmentDirectional.centerEnd,
        widthFactor: 1,
        heightFactor: 1,
        child: reading,
      ),
    );
  }
}
