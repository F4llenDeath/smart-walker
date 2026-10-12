import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../application/trial_recorder.dart';
import '../../core/formatters.dart';
import '../../shared/widgets/panels.dart';
import '../devices/device_status_panel.dart';
import '../patients/patient_picker.dart';
import '../trials/trial_detail_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.dependencies, super.key});
  final AppDependencies dependencies;

  Future<void> _perform(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (exception) {
      if (context.mounted) await showProblem(context, exception);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      dependencies.patients,
      dependencies.telemetry,
      dependencies.recorder,
    ]),
    builder: (context, _) {
      final patients = dependencies.patients;
      final telemetry = dependencies.telemetry;
      final recorder = dependencies.recorder;
      final snapshot = telemetry.snapshot;
      return FScaffold(
        childPad: false,
        header: FHeader(
          title: const Text('Smart Walker'),
          suffixes: [
            FButton(
              variant: FButtonVariant.outline,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.bluetooth),
              onPress: () => showPanel(
                context,
                DeviceStatusPanel(dependencies: dependencies),
              ),
              child: Text(
                telemetry.simulating ? 'SIM' : '${snapshot.readyCount}/3',
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
                if (telemetry.simulating) ...[
                  const NoticeBanner(
                    'Simulation mode',
                    message: 'These measurements are generated, not received from the walker.',
                  ),
                  const SizedBox(height: 16),
                ],
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    final columns = constraints.maxWidth >= 850 && scale < 1.4
                        ? 3
                        : constraints.maxWidth >= 350 && scale < 1.7
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children:
                          [
                                _Metric(
                                  'Left weight',
                                  measurement(snapshot.weightLeft),
                                  'lbs',
                                  FLucideIcons.footprints,
                                ),
                                _Metric(
                                  'Right weight',
                                  measurement(snapshot.weightRight),
                                  'lbs',
                                  FLucideIcons.footprints,
                                ),
                                _Metric(
                                  'Total weight',
                                  measurement(snapshot.weightTotal),
                                  'lbs',
                                  FLucideIcons.scale,
                                ),
                                _Metric(
                                  recorder.recording
                                      ? 'Trial distance'
                                      : 'Distance',
                                  measurement(
                                    recorder.recording
                                        ? recorder.trialDistance
                                        : snapshot.distanceFt,
                                  ),
                                  'ft',
                                  FLucideIcons.route,
                                ),
                                _Metric(
                                  'Speed',
                                  measurement(snapshot.speedFtS),
                                  'ft/s',
                                  FLucideIcons.gauge,
                                ),
                              ]
                              .map(
                                (metric) =>
                                    SizedBox(width: width, child: metric),
                              )
                              .toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),
                SectionCard(
                  title: recorder.recording
                      ? 'Recording for ${recorder.patientName}'
                      : 'Trial recording',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ValueListenableBuilder<Duration>(
                        valueListenable: recorder.elapsed,
                        builder: (context, elapsed, _) => Text(
                          elapsedText(elapsed),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FButton(
                        variant: recorder.recording
                            ? FButtonVariant.destructive
                            : FButtonVariant.primary,
                        prefix: Icon(
                          recorder.recording
                              ? FLucideIcons.square
                              : FLucideIcons.play,
                        ),
                        onPress: recorder.recording
                            ? () => _perform(context, recorder.stop)
                            : recorder.startUnavailable == null
                            ? () => _perform(context, recorder.start)
                            : null,
                        child: Text(
                          recorder.state == RecorderState.saving
                              ? 'Saving…'
                              : recorder.recording
                              ? 'Stop and save trial'
                              : 'Start trial',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        recorder.recording
                            ? 'Latest sensor values are captured every 200 ms.'
                            : recorder.startUnavailable ?? 'Ready to record. Units: pounds, feet, and feet/second.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
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
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.unit, this.icon);
  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) => FCard(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.theme.colors.mutedForeground),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(color: context.theme.colors.mutedForeground),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 6,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  unit,
                  style: TextStyle(color: context.theme.colors.mutedForeground),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
