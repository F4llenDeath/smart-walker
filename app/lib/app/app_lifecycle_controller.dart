import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_dependencies.dart';

class AppLifecycleController with WidgetsBindingObserver {
  AppLifecycleController(this.dependencies) {
    WidgetsBinding.instance.addObserver(this);
  }

  final AppDependencies dependencies;
  Future<void> _work = Future.value();
  bool _background = false;
  bool _disposed = false;
  int _generation = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
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
