import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../core/formatters.dart';
import '../../domain/models/trial.dart';
import '../../shared/widgets/panels.dart';
import '../patients/patient_actions.dart';

class PatientTrialSidebar extends StatelessWidget {
  const PatientTrialSidebar({
    required this.dependencies,
    required this.selectedTrialId,
    required this.onTrial,
    super.key,
  });

  final AppDependencies dependencies;
  final String? selectedTrialId;
  final ValueChanged<Trial> onTrial;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      dependencies.patients,
      dependencies.recorder,
    ]),
    builder: (context, _) {
      final patients = dependencies.patients;
      final editable =
          patients.ready && !patients.saving && !dependencies.recorder.locked;
      return FSidebar(
        style: const FSidebarStyleDelta.delta(
          constraints: BoxConstraints.tightFor(width: 280),
        ),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Smart Walker',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              // Rich select uses patient IDs, so duplicate names remain distinct.
              FSelect<String>.rich(
                label: const Text('Patient'),
                control: FSelectControl.lifted(
                  value: patients.selected.id,
                  onChange: (id) {
                    if (id == null) return;
                    try {
                      patients.select(id);
                    } catch (exception) {
                      showProblem(context, exception);
                    }
                  },
                ),
                enabled: editable,
                format: (id) => patients.selectedById(id)?.name ?? 'Unassigned',
                contentConstraints: const FAutoWidthPortalConstraints(
                  maxHeight: 320,
                ),
                children: [
                  for (final patient in patients.patients)
                    FSelectItem<String>(
                      title: Text(patient.name),
                      value: patient.id,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.ghost,
                      prefix: const Icon(FLucideIcons.plus),
                      onPress: editable
                          ? () => showAddPatientDialog(context, dependencies)
                          : null,
                      child: const Text('Add patient'),
                    ),
                  ),
                  FButton.icon(
                    variant: FButtonVariant.ghost,
                    semanticsLabel: 'Delete selected patient',
                    onPress: editable && !patients.selected.isUnassigned
                        ? () => deleteSelectedPatient(context, dependencies)
                        : null,
                    child: const Icon(FLucideIcons.trash2),
                  ),
                ],
              ),
            ],
          ),
        ),
        children: [
          FSidebarGroup(
            label: const Text('Past trials'),
            children: [
              if (patients.trials.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No trials yet',
                    style: TextStyle(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ),
              for (final trial in patients.trials)
                FSidebarItem(
                  key: ValueKey(trial.id),
                  selected: selectedTrialId == trial.id,
                  onPress: () => onTrial(trial),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateTimeText(trial.startDate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${durationText(trial.duration)} · ${trial.totalDistance.toStringAsFixed(1)} ft',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.theme.colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}
