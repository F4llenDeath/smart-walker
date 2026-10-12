import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/ble_protocol.dart';
import '../data/storage/recording_draft_store.dart';
import '../domain/models/active_recording.dart';
import '../domain/models/data_point.dart';
import '../domain/models/patient.dart';
import '../domain/models/trial.dart';
import 'patient_controller.dart';
import 'telemetry_controller.dart';

enum RecorderState { idle, recording, saving, saveFailed }

class TrialRecorder extends ChangeNotifier {
  TrialRecorder(this.telemetry, this.patients, this.drafts) {
    telemetry.addListener(_telemetryChanged);
  }

  final TelemetryController telemetry;
  final PatientController patients;
  final RecordingDraftStore drafts;
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);
  final Stopwatch _clock = Stopwatch();
  final List<DataPoint> _points = [];
  Timer? _samples;
  Timer? _display;
  Timer? _checkpoint;
  RecorderState state = RecorderState.idle;
  RecordingDraft? recovered;
  String? error;
  String? notice;
  bool recoveryLoaded = false;
  String? _id;
  String? _patientId;
  String? patientName;
  DateTime? _start;
  double baseline = 0;
  double _lastAbsolute = 0;
  DataSource _source = DataSource.unknown;
  Trial? _completed;
  String? _successNotice;
  bool _checkpointBusy = false;
  bool _loadingRecovery = false;
  bool _disposed = false;
  bool _starting = false;
  String? _startInterruption;

  bool get recording => state == RecorderState.recording;
  bool get locked =>
      state != RecorderState.idle ||
      recovered != null ||
      !recoveryLoaded ||
      error != null;
  int get sampleCount => _points.length;
  double? get trialDistance => recording && telemetry.snapshot.radarReady
      ? max(0, telemetry.snapshot.distanceFt! - baseline)
      : null;

  String? get startUnavailable {
    if (!patients.ready) {
      return 'Patient storage must be loaded before recording.';
    }
    if (patients.saving) return 'Wait for the current save to finish.';
    if (locked) return 'Resolve the pending recording or recovery first.';
    if (telemetry.switching) return 'Wait for the telemetry source to switch.';
    if (!telemetry.snapshot.ready) {
      return 'All three sensor streams must be ready and fresh.';
    }
    return null;
  }

  Future<void> loadRecovery() async {
    if (_loadingRecovery || state != RecorderState.idle) return;
    _loadingRecovery = true;
    recoveryLoaded = false;
    notifyListeners();
    try {
      recovered = await drafts.load();
      if (recovered != null &&
          patients.ready &&
          patients.containsTrial(recovered!.trial.id)) {
        await drafts.clear();
        recovered = null;
      }
      error = null;
    } catch (exception) {
      error =
          'Unable to read the recording recovery file. It was not overwritten. $exception';
    } finally {
      _loadingRecovery = false;
      recoveryLoaded = true;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> start() async {
    final unavailable = startUnavailable;
    if (unavailable != null) throw StateError(unavailable);
    final snapshot = telemetry.snapshot;
    _id = const Uuid().v4();
    _patientId = patients.selected.id;
    patientName = patients.selected.name;
    _source = snapshot.source;
    _start = DateTime.now().toUtc();
    baseline = snapshot.distanceFt!;
    _lastAbsolute = baseline;
    _points.clear();
    _completed = null;
    _successNotice = null;
    error = null;
    notice = null;
    _starting = true;
    _startInterruption = null;
    state = RecorderState.saving;
    notifyListeners();
    try {
      await drafts.save(_draft());
    } catch (exception) {
      state = RecorderState.idle;
      error =
          'Recording could not start because its recovery file could not be saved. $exception';
      notifyListeners();
      rethrow;
    } finally {
      _starting = false;
    }
    // Startup writes are asynchronous: recheck sensors and lifecycle afterwards.
    if (_startInterruption != null ||
        !telemetry.snapshot.ready ||
        !telemetry.foreground ||
        telemetry.snapshot.source != _source) {
      final reason =
          _startInterruption ?? 'Telemetry became unavailable while starting.';
      _completed = _trial(
        end: DateTime.now().toUtc(),
        completion: TrialCompletion.interrupted,
        reason: reason,
      );
      _successNotice = 'Partial trial preserved: $reason';
      await _saveCompleted();
      return;
    }
    _clock.reset();
    _clock.start();
    elapsed.value = Duration.zero;
    state = RecorderState.recording;
    _samples = Timer.periodic(BleProtocol.sampleInterval, (_) => _sample());
    _display = Timer.periodic(const Duration(milliseconds: 30), (_) {
      elapsed.value = _clock.elapsed;
    });
    _checkpoint = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_saveCheckpoint());
    });
    notifyListeners();
  }

  Trial _trial({
    DateTime? end,
    TrialCompletion completion = TrialCompletion.completed,
    String? reason,
  }) => Trial(
    id: _id!,
    startDate: _start!,
    endDate: end,
    dataPoints: _points,
    source: _source,
    completion: completion,
    interruptionReason: reason,
  );

  RecordingDraft _draft({Trial? trial}) => RecordingDraft(
    patientId: _patientId!,
    patientName: patientName!,
    baseline: baseline,
    checkpoint: DateTime.now().toUtc(),
    trial: trial ?? _trial(),
  );

  void _telemetryChanged() {
    if (!recording) return;
    final snapshot = telemetry.snapshot;
    if (!snapshot.ready || snapshot.source != _source) {
      unawaited(
        stop(
          reason:
              'A required sensor disconnected or its telemetry became stale.',
        ),
      );
    } else if (snapshot.distanceFt! < _lastAbsolute - 0.005) {
      unawaited(stop(reason: 'Radar cumulative distance reset or regressed.'));
    } else {
      _lastAbsolute = snapshot.distanceFt!;
    }
  }

  void _sample() {
    _telemetryChanged();
    if (!recording) return;
    final snapshot = telemetry.snapshot;
    _points.add(
      DataPoint(
        timestamp: DateTime.now().toUtc(),
        weightLeft: snapshot.weightLeft!,
        weightRight: snapshot.weightRight!,
        distanceFt: max(0, snapshot.distanceFt! - baseline),
        speedFtS: snapshot.speedFtS!,
      ),
    );
  }

  Future<void> _saveCheckpoint() async {
    if (!recording || _checkpointBusy) return;
    _checkpointBusy = true;
    try {
      await drafts.save(_draft());
    } catch (exception) {
      if (recording) {
        await stop(reason: 'Recovery checkpoint failed: $exception');
      }
    } finally {
      _checkpointBusy = false;
    }
  }

  Future<void> stop({String? reason}) async {
    if (_starting) {
      // Never start sampling after a background/foreground round trip while the
      // initial recovery write is pending. The start operation preserves it.
      _startInterruption ??= reason ?? 'Recording stopped while starting.';
      return;
    }
    if (!recording) return;
    _cancelTimers();
    _completed = _trial(
      end: DateTime.now().toUtc(),
      completion: reason == null
          ? TrialCompletion.completed
          : TrialCompletion.interrupted,
      reason: reason,
    );
    _successNotice = reason == null
        ? 'Trial saved.'
        : 'Partial trial preserved: $reason';
    await _saveCompleted();
  }

  Future<void> _saveCompleted() async {
    state = RecorderState.saving;
    error = null;
    notice = null;
    notifyListeners();
    try {
      // Attempt a final checkpoint, but a failed checkpoint must not block the
      // authoritative patient-data save (e.g. a recovery-only filesystem issue).
      try {
        await drafts.save(_draft(trial: _completed!));
      } catch (_) {}
      await patients.saveTrial(_patientId!, _completed!);
      await drafts.clear();
      _completed = null;
      recovered = null;
      notice = _successNotice;
      _successNotice = null;
      state = RecorderState.idle;
    } catch (exception) {
      state = RecorderState.saveFailed;
      error =
          'The trial is retained. Retry saving before starting another trial. $exception';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> retrySave() async {
    if (state == RecorderState.saveFailed && _completed != null) {
      await _saveCompleted();
    }
  }

  Future<void> saveRecovered() async {
    if (recovered == null ||
        !patients.ready ||
        patients.saving ||
        state != RecorderState.idle) {
      return;
    }
    final draft = recovered!;
    _id = draft.trial.id;
    _patientId = patients.selectedById(draft.patientId) == null
        ? Patient.unassignedId
        : draft.patientId;
    patientName = draft.patientName;
    baseline = draft.baseline;
    _start = draft.trial.startDate;
    _source = draft.trial.source;
    _points
      ..clear()
      ..addAll(draft.trial.dataPoints);
    _completed = Trial(
      id: draft.trial.id,
      startDate: draft.trial.startDate,
      endDate: draft.trial.endDate ?? draft.checkpoint,
      dataPoints: draft.trial.dataPoints,
      source: draft.trial.source,
      completion: TrialCompletion.recovered,
      interruptionReason:
          draft.trial.interruptionReason ??
          'Recovered after application termination.',
    );
    _successNotice =
        'Recovered trial saved${_patientId == draft.patientId ? '' : ' to Unassigned'}.';
    await _saveCompleted();
  }

  Future<void> discardRecovery() async {
    if (state != RecorderState.idle || _loadingRecovery) return;
    state = RecorderState.saving;
    notifyListeners();
    try {
      await drafts.clear();
      recovered = null;
      error = null;
      recoveryLoaded = true;
    } catch (exception) {
      error = 'Could not discard recovery: $exception';
    } finally {
      state = RecorderState.idle;
      if (!_disposed) notifyListeners();
    }
  }

  void _cancelTimers() {
    _samples?.cancel();
    _samples = null;
    _display?.cancel();
    _display = null;
    _checkpoint?.cancel();
    _checkpoint = null;
    _clock.stop();
    elapsed.value = _clock.elapsed;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    telemetry.removeListener(_telemetryChanged);
    elapsed.dispose();
    super.dispose();
  }
}
