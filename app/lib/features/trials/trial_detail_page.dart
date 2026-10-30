import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../core/formatters.dart';
import '../../domain/models/trial.dart';
import '../../shared/widgets/panels.dart';
import 'trial_charts.dart';

class TrialDetailPage extends StatefulWidget {
  const TrialDetailPage({
    required this.dependencies,
    required this.patientId,
    required this.trial,
    this.onBack,
    this.headerActions = const [],
    this.embedded = false,
    super.key,
  });
  final AppDependencies dependencies;
  final String patientId;
  final Trial trial;
  final VoidCallback? onBack;
  final List<Widget> headerActions;
  final bool embedded;

  @override
  State<TrialDetailPage> createState() => _TrialDetailPageState();
}

class _TrialDetailPageState extends State<TrialDetailPage> {
  bool _busy = false;
  final GlobalKey _shareKey = GlobalKey();

  void _back() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _share() async {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      await widget.dependencies.csv.share(widget.trial, origin);
    } catch (exception) {
      if (mounted) await showProblem(context, exception);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirmAction(
      context,
      title: 'Delete trial?',
      message: 'This trial and all its recorded samples will be permanently deleted.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.dependencies.patients.deleteTrial(
        widget.patientId,
        widget.trial.id,
      );
      if (mounted) _back();
    } catch (exception) {
      if (mounted) await showProblem(context, exception);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.dependencies.recorder,
      widget.dependencies.patients,
    ]),
    builder: (context, _) {
      final trial = widget.trial;
      final header = FHeader.nested(
        title: const Text('Trial detail'),
        prefixes: [FHeaderAction.back(onPress: _back)],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.trash2),
            onPress:
                _busy ||
                    widget.dependencies.recorder.locked ||
                    widget.dependencies.patients.saving
                ? null
                : _delete,
          ),
          ...widget.headerActions,
        ],
      );
      final content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            key: PageStorageKey('trial-${widget.patientId}-${trial.id}'),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                dateTimeText(trial.startDate),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FBadge(
                    child: Text(
                      trial.source == DataSource.unknown
                          ? 'Legacy · source unknown'
                          : trial.source.name,
                    ),
                  ),
                  FBadge(child: Text(trial.completion.name)),
                  FBadge(child: Text('${trial.sampleCount} samples')),
                ],
              ),
              const SizedBox(height: 16),
              if (trial.interruptionReason != null) ...[
                NoticeBanner(
                  'Partial recording',
                  message: trial.interruptionReason,
                ),
                const SizedBox(height: 16),
              ],
              SectionCard(
                title: 'Time',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DetailRow('Start', timeText(trial.startDate)),
                    DetailRow(
                      'End',
                      trial.endDate == null ? '—' : timeText(trial.endDate!),
                    ),
                    DetailRow('Duration', durationText(trial.duration)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Distance & speed',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DetailRow(
                      'Total distance',
                      '${measurement(trial.totalDistance)} ft',
                    ),
                    DetailRow(
                      'Average speed',
                      '${measurement(trial.averageSpeed)} ft/s',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Weight',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DetailRow(
                      'Average left',
                      '${measurement(trial.averageWeightLeft)} lbs',
                    ),
                    DetailRow(
                      'Average right',
                      '${measurement(trial.averageWeightRight)} lbs',
                    ),
                    DetailRow(
                      'Average total',
                      '${measurement(trial.averageWeightTotal)} lbs',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TrialCharts(trial: trial),
              const SizedBox(height: 20),
              FButton(
                key: _shareKey,
                prefix: const Icon(FLucideIcons.share2),
                onPress: _busy ? null : _share,
                child: Text(_busy ? 'Working…' : 'Export CSV'),
              ),
            ],
          ),
        ),
      );
      if (widget.embedded) {
        return Column(
          children: [
            header,
            Expanded(child: content),
          ],
        );
      }
      return FScaffold(childPad: false, header: header, child: content);
    },
  );
}
