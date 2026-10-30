import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../shared/widgets/panels.dart';

Future<void> showAddPatientDialog(
  BuildContext context,
  AppDependencies dependencies,
) => showFDialog<void>(
  context: context,
  useRootNavigator: true,
  builder: (context, style, animation) => FDialog(
    style: style,
    animation: animation,
    clipBehavior: Clip.antiAlias,
    builder: (_, _) => _AddPatientForm(dependencies: dependencies),
  ),
);

Future<void> deleteSelectedPatient(
  BuildContext context,
  AppDependencies dependencies,
) async {
  final patient = dependencies.patients.selected;
  if (patient.isUnassigned ||
      dependencies.recorder.locked ||
      dependencies.patients.saving) {
    return;
  }
  if (!await confirmAction(
    context,
    title: 'Delete ${patient.name}?',
    message:
        'This permanently deletes this patient and ${patient.trials.length} associated trials.',
  )) {
    return;
  }
  if (!context.mounted) return;
  try {
    await dependencies.patients.delete(patient.id);
  } catch (exception) {
    if (context.mounted) await showProblem(context, exception);
  }
}

class _AddPatientForm extends StatefulWidget {
  const _AddPatientForm({required this.dependencies});
  final AppDependencies dependencies;

  @override
  State<_AddPatientForm> createState() => _AddPatientFormState();
}

class _AddPatientFormState extends State<_AddPatientForm> {
  final TextEditingController _name = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.dependencies.patients.add(_name.text);
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) setState(() => _error = '$exception');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.dependencies.patients,
      widget.dependencies.recorder,
    ]),
    builder: (context, _) {
      final enabled =
          !_busy &&
          widget.dependencies.patients.ready &&
          !widget.dependencies.patients.saving &&
          !widget.dependencies.recorder.locked;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add patient',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              NoticeBanner(
                'Patient action failed',
                message: _error,
                destructive: true,
              ),
              const SizedBox(height: 12),
            ],
            FTextField(
              control: FTextFieldControl.managed(
                controller: _name,
                onChange: (_) => setState(() {}),
              ),
              label: const Text('Patient name'),
              autofocus: true,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmit: (_) {
                if (enabled) _add();
              },
            ),
            const SizedBox(height: 16),
            FButton(
              onPress: enabled && _name.text.trim().isNotEmpty ? _add : null,
              child: Text(_busy ? 'Saving…' : 'Add patient'),
            ),
            const SizedBox(height: 8),
            FButton(
              variant: FButtonVariant.outline,
              onPress: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    },
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }
}
