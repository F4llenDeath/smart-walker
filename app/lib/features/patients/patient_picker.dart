import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../domain/models/patient.dart';
import '../../shared/widgets/panels.dart';

class PatientPicker extends StatefulWidget {
  const PatientPicker({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  State<PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends State<PatientPicker> {
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

  Future<void> _delete(Patient patient) async {
    if (!await confirmAction(
      context,
      title: 'Delete ${patient.name}?',
      message:
          'This permanently deletes this patient and ${patient.trials.length} associated trials.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.dependencies.patients.delete(patient.id);
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
      final patients = widget.dependencies.patients;
      final enabled =
          !_busy && !patients.saving && !widget.dependencies.recorder.locked;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select patient',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: () => Navigator.pop(context),
                    child: const Icon(FLucideIcons.x),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                NoticeBanner(
                  'Patient action failed',
                  message: _error,
                  destructive: true,
                ),
                const SizedBox(height: 12),
              ],
              for (final patient in patients.patients)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FButton(
                          variant: FButtonVariant.outline,
                          prefix: Icon(
                            patient.isUnassigned
                                ? FLucideIcons.userRound
                                : FLucideIcons.user,
                          ),
                          suffix: patients.selected.id == patient.id
                              ? const Icon(FLucideIcons.check)
                              : null,
                          onPress: !enabled
                              ? null
                              : () {
                                  try {
                                    patients.select(patient.id);
                                    Navigator.pop(context);
                                  } catch (exception) {
                                    setState(() => _error = '$exception');
                                  }
                                },
                          child: Text(
                            patient.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (!patient.isUnassigned) ...[
                        const SizedBox(width: 8),
                        FButton.icon(
                          variant: FButtonVariant.ghost,
                          semanticsLabel: 'Delete ${patient.name}',
                          onPress: enabled ? () => _delete(patient) : null,
                          child: const Icon(FLucideIcons.trash2),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              FTextField(
                control: FTextFieldControl.managed(
                  controller: _name,
                  onChange: (_) => setState(() {}),
                ),
                label: const Text('New patient'),
                hint: 'Patient name',
                enabled: enabled,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmit: (_) => _add(),
              ),
              const SizedBox(height: 12),
              FButton(
                onPress: enabled && _name.text.trim().isNotEmpty ? _add : null,
                prefix: const Icon(FLucideIcons.plus),
                child: Text(_busy ? 'Saving…' : 'Add patient'),
              ),
            ],
          ),
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
