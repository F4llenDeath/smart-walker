import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/trial_recorder.dart';
import '../../core/formatters.dart';
import '../../shared/widgets/panels.dart';

/// Dashboard-only controls pinned by FScaffold, outside its scrollable body.
class TrialRecordingBar extends StatelessWidget {
  const TrialRecordingBar({required this.recorder, super.key});

  final TrialRecorder recorder;

  Future<void> _toggle(BuildContext context) async {
    try {
      if (recorder.recording) {
        await recorder.stop();
      } else {
        await recorder.start();
      }
    } catch (exception) {
      if (context.mounted) await showProblem(context, exception);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      recorder,
      recorder.patients,
      recorder.telemetry,
    ]),
    builder: (context, _) {
      final recording = recorder.recording;
      final saving = recorder.state == RecorderState.saving;
      final enabled = recording || recorder.startUnavailable == null;
      return SizedBox(
        width: double.infinity,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: FCard(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (recording) ...[
                        ValueListenableBuilder<Duration>(
                          valueListenable: recorder.elapsed,
                          builder: (context, elapsed, _) => Text(
                            elapsedText(elapsed),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.theme.colors.foreground,
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FButton(
                        variant: recording
                            ? FButtonVariant.destructive
                            : FButtonVariant.primary,
                        prefix: saving
                            ? const FCircularProgress()
                            : Icon(
                                recording
                                    ? FLucideIcons.square
                                    : FLucideIcons.play,
                              ),
                        onPress: enabled ? () => _toggle(context) : null,
                        child: Text(
                          saving
                              ? 'Saving…'
                              : recording
                              ? 'Stop and save trial'
                              : 'Start trial',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
