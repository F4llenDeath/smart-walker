import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import '../application/trial_recorder.dart';
import 'app_dependencies.dart';
import 'app_platform.dart';

class AppLifecycleController with WidgetsBindingObserver {
  AppLifecycleController(this.dependencies) {
    WidgetsBinding.instance.addObserver(this);
  }

  final AppDependencies dependencies;
  Future<void> _work = Future.value();
  bool _background = false;
  bool _disposed = false;
  bool _exiting = false;
  int _generation = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (_exiting) return;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_background) return;
      _background = true;
      _generation++;
      // Stop synchronously before a lifecycle suspension can delay timers.
      final save = dependencies.recorder.stop(
        reason: 'Application entered the background.',
      );
      final suspend = dependencies.telemetry.suspend();
      _enqueue(() async {
        await save;
        await suspend;
      });
    } else if (state == AppLifecycleState.resumed && _background) {
      _background = false;
      final generation = ++_generation;
      _enqueue(() async {
        // A resume can wait behind a save while a newer background transition
        // has already suspended telemetry. Never replay that obsolete resume.
        if (!_background && generation == _generation) {
          await dependencies.telemetry.resume();
        }
      });
    }
  }

  Future<void> _waitForSave(Listenable source, bool Function() saving) async {
    if (!saving()) return;
    final finished = Completer<void>();
    void changed() {
      if (!saving() && !finished.isCompleted) finished.complete();
    }

    source.addListener(changed);
    try {
      changed();
      await finished.future.timeout(const Duration(seconds: 20));
    } finally {
      source.removeListener(changed);
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!isMacOSApp || _disposed) return AppExitResponse.exit;
    if (_exiting) return AppExitResponse.cancel;
    _exiting = true;
    _generation++;
    var canExit = false;
    try {
      await dependencies.recorder
          .stop(reason: 'Application was closed.')
          .timeout(const Duration(seconds: 20));
      await _waitForSave(
        dependencies.recorder,
        () => dependencies.recorder.state == RecorderState.saving,
      );
      await _waitForSave(
        dependencies.patients,
        () => dependencies.patients.saving,
      );
      canExit = dependencies.recorder.state != RecorderState.saveFailed;
    } catch (exception) {
      debugPrint('Exit delayed: $exception');
    } finally {
      if (!canExit) _exiting = false;
    }
    // A failed save leaves the window open with Retry available. Force quit and
    // power loss still depend on the existing periodic recovery checkpoints.
    return canExit ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  void _enqueue(Future<void> Function() action) {
    _work = _work
        .then((_) async {
          if (!_disposed) await action();
        })
        .catchError((Object exception) {
          debugPrint('Lifecycle operation failed: $exception');
        });
  }

  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
  }
}
