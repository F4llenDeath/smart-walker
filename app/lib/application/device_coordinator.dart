import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/ble_protocol.dart';
import '../data/ble/ble_transport.dart';
import '../domain/models/sensor_status.dart';

class DeviceCoordinator extends ChangeNotifier {
  DeviceCoordinator(this.transport) {
    _adapterSubscription = transport.adapterChanges.listen(
      _adapterChanged,
      onError: (Object exception) {
        error = 'Bluetooth status: $exception';
        notifyListeners();
      },
    );
    _scanSubscription = transport.discoveries.listen(
      _discovered,
      onError: (Object exception) {
        error = 'Discovery: $exception';
        notifyListeners();
      },
    );
    _freshnessTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _checkFreshness(),
    );
  }

  final BleTransport transport;
  final Map<SensorRole, SensorStatus> sensors = {
    for (final role in SensorRole.values) role: SensorStatus(role),
  };
  final Stopwatch _clock = Stopwatch()..start();
  final Map<SensorRole, DiscoveredDevice> _known = {};
  final Map<SensorRole, Timer> _retries = {};
  final Map<SensorRole, int> _attempts = {};
  final Map<SensorRole, int> _generation = {};
  final Map<SensorRole, List<StreamSubscription<dynamic>>> _sessions = {};
  final Map<SensorRole, Future<void>> _recoveries = {};
  late final StreamSubscription<AdapterState> _adapterSubscription;
  late final StreamSubscription<DiscoveredDevice> _scanSubscription;
  late final Timer _freshnessTimer;
  Future<void> _transition = Future.value();
  Future<void> _scanTransition = Future.value();
  Future<void>? _connectWork;
  Timer? _scanRetry;
  bool _active = false;
  bool _requestedActive = false;
  bool _disposed = false;
  int _epoch = 0;
  AdapterState adapter = AdapterState.unknown;
  bool hasPermissions = false;
  bool scanning = false;
  String? error;

  bool get _canConnect =>
      _active && !_disposed && hasPermissions && adapter == AdapterState.on;
  bool get allReady =>
      sensors.values.every((status) => status.phase == SensorPhase.ready);
  int get readyCount => sensors.values
      .where((status) => status.phase == SensorPhase.ready)
      .length;

  Future<void> _serialize(Future<void> Function() action) {
    final result = _transition.then((_) => action());
    _transition = result.catchError((Object exception) {
      if (!_disposed) {
        error = '$exception';
        notifyListeners();
      }
    });
    return result;
  }

  Future<void> start({bool requestPermissions = false}) {
    if (_disposed) return Future.value();
    _requestedActive = true;
    final epoch = _epoch;
    bool current() => !_disposed && _requestedActive && epoch == _epoch;
    return _serialize(() async {
      // A suspend may invalidate a start while it waits behind native cleanup.
      if (!current()) return;
      _active = true;
      error = null;
      try {
        final permitted = await transport.permissions(
          request: requestPermissions,
        );
        if (!current()) return;
        hasPermissions = permitted;
        final state = await transport.availability();
        if (!current()) return;
        adapter = state;
        if (!hasPermissions) {
          error = 'Bluetooth permission is required. Grant it in Settings, then retry.';
        }
      } catch (exception) {
        if (!current()) return;
        hasPermissions = false;
        error = 'Bluetooth setup failed: $exception';
      }
      if (!current()) return;
      notifyListeners();
      await _ensureScan();
    });
  }

  void _adapterChanged(AdapterState state) {
    if (_disposed) return;
    adapter = state;
    if (state != AdapterState.on) {
      _epoch++;
      for (final timer in _retries.values) {
        timer.cancel();
      }
      _retries.clear();
      _scanRetry?.cancel();
      for (final status in sensors.values) {
        status.clear();
      }
      // Tear down native sessions as well; an adapter reset invalidates GATT state.
      unawaited(
        _serialize(() async {
          await _stopScan();
          await _connectWork;
          await _closeSessions();
          if (_canConnect) await _ensureScan();
        }),
      );
    } else if (_requestedActive) {
      unawaited(start());
    }
    notifyListeners();
  }

  void _discovered(DiscoveredDevice device) {
    final role = BleProtocol.roleFor(device.name);
    if (role == null || !_canConnect) return;
    _known[role] = device;
    _pump();
  }

  void _pump() {
    if (!_canConnect || _connectWork != null) return;
    for (final role in SensorRole.values) {
      final status = sensors[role]!;
      if (!_known.containsKey(role) ||
          _retries.containsKey(role) ||
          _recoveries.containsKey(role) ||
          (status.phase != SensorPhase.disconnected &&
              status.phase != SensorPhase.error)) {
        continue;
      }
      final future = _connect(role, _known[role]!);
      _connectWork = future;
      unawaited(
        future.whenComplete(() {
          _connectWork = null;
          if (_canConnect) {
            _pump();
            unawaited(_ensureScan());
          }
        }),
      );
      return;
    }
  }

  Future<void> _connect(SensorRole role, DiscoveredDevice device) async {
    final epoch = _epoch;
    final generation = (_generation[role] ?? 0) + 1;
    _generation[role] = generation;
    bool current() =>
        _canConnect && epoch == _epoch && _generation[role] == generation;
    final status = sensors[role]!;
    status.clear();
    status.deviceId = device.id;
    status.phase = SensorPhase.connecting;
    notifyListeners();
    try {
      await _stopScan();
      if (!current()) return;
      await _cancelListeners(role);
      if (!current()) return;
      _sessions[role] = [
        transport
            .connectionChanges(device.id)
            .listen(
              (connected) {
                if (!connected && current()) {
                  unawaited(_failed(role, generation, 'Device disconnected.'));
                }
              },
              onError: (Object exception) {
                if (current()) {
                  unawaited(_failed(role, generation, '$exception'));
                }
              },
            ),
      ];
      await transport.connect(device.id);
      if (!current()) return;
      status.phase = SensorPhase.discovering;
      notifyListeners();
      await transport.discover(device.id);
      if (!current()) return;
      status.phase = SensorPhase.subscribing;
      notifyListeners();
      _sessions[role]!.add(
        transport
            .notifications(device.id)
            .listen(
              (bytes) {
                if (!current()) return;
                final parsed = BleProtocol.parse(role, bytes);
                if (parsed == null) return;
                status.value = parsed.value;
                status.speed = parsed.speed;
                status.lastReceived = DateTime.now().toUtc();
                status.lastReceiptMilliseconds = _clock.elapsedMilliseconds;
                status.phase = SensorPhase.ready;
                status.error = null;
                _attempts[role] = 0;
                notifyListeners();
                if (allReady) unawaited(_stopScan());
              },
              onError: (Object exception) {
                if (current()) {
                  unawaited(_failed(role, generation, '$exception'));
                }
              },
            ),
      );
      await transport.subscribe(device.id);
      if (!current()) return;
      if (status.phase != SensorPhase.ready) status.phase = SensorPhase.waiting;
      status.waitingSinceMilliseconds = _clock.elapsedMilliseconds;
      notifyListeners();
    } catch (exception) {
      if (current()) {
        await _failed(role, generation, 'Connection failed: $exception');
      }
    } finally {
      // A disconnect, adapter reset, or suspension can invalidate setup while a
      // native connect/discovery/subscription operation is still in flight.
      // Clean up again after it settles, before another connection can start.
      if (!current()) {
        await _cancelListeners(role);
        await _safeDisconnect(device.id);
      }
    }
  }

  Future<void> _failed(SensorRole role, int generation, String reason) {
    if (_generation[role] != generation || !_canConnect) {
      return Future.value();
    }
    final pending = _recoveries[role];
    if (pending != null) return pending;
    _generation[role] = generation + 1;
    final epoch = _epoch;
    final future = _recover(role, generation + 1, epoch, reason);
    _recoveries[role] = future;
    unawaited(
      future.whenComplete(() {
        _recoveries.remove(role);
        if (_canConnect) {
          _pump();
          unawaited(_ensureScan());
        }
      }),
    );
    return future;
  }

  Future<void> _recover(
    SensorRole role,
    int generation,
    int epoch,
    String reason,
  ) async {
    final status = sensors[role]!;
    final id = status.deviceId;
    status.clear();
    status.phase = SensorPhase.error;
    status.error = reason;
    notifyListeners();
    await _cancelListeners(role);
    if (id != null) await _safeDisconnect(id);
    if (!_canConnect || epoch != _epoch || _generation[role] != generation) {
      return;
    }
    final attempts = (_attempts[role] ?? 0) + 1;
    _attempts[role] = attempts;
    _retries[role]?.cancel();
    _retries[role] = Timer(
      Duration(seconds: min(16, 1 << min(4, attempts - 1))),
      () {
        _retries.remove(role);
        if (!_canConnect || epoch != _epoch) return;
        status.phase = SensorPhase.disconnected;
        notifyListeners();
        _pump();
        unawaited(_ensureScan());
      },
    );
    await _ensureScan();
  }

  void _checkFreshness() {
    if (!_active || _disposed) return;
    bool changed = false;
    for (final status in sensors.values) {
      final receipt = status.lastReceiptMilliseconds;
      if (status.phase == SensorPhase.ready &&
          receipt != null &&
          _clock.elapsedMilliseconds - receipt >
              BleProtocol.freshness.inMilliseconds) {
        status.phase = SensorPhase.stale;
        changed = true;
      }
      final wait = receipt ?? status.waitingSinceMilliseconds;
      if ((status.phase == SensorPhase.waiting ||
              status.phase == SensorPhase.stale) &&
          wait != null &&
          _clock.elapsedMilliseconds - wait > 12000) {
        unawaited(
          _failed(
            status.role,
            _generation[status.role]!,
            'No valid telemetry received.',
          ),
        );
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _ensureScan() => _setScanning(true);

  Future<void> _stopScan() => _setScanning(false);

  // Start/stop share one queue: a scan completing during connection cleanup
  // must not leave the native scanner running with an incorrect UI state.
  Future<void> _setScanning(bool wanted) {
    final result = _scanTransition.then((_) async {
      final shouldScan =
          wanted && _canConnect && !allReady && _connectWork == null;
      if (shouldScan == scanning) return;
      if (!shouldScan) {
        try {
          await transport.stopScan();
        } catch (_) {
          // An adapter reset may already have stopped the native scanner.
        }
        scanning = false;
      } else {
        final epoch = _epoch;
        try {
          await transport.startScan();
          scanning = true;
          if (!_canConnect ||
              epoch != _epoch ||
              allReady ||
              _connectWork != null) {
            try {
              await transport.stopScan();
            } catch (_) {}
            scanning = false;
          }
        } catch (exception) {
          error = 'Scan failed: $exception';
          _scanRetry?.cancel();
          if (_canConnect) {
            _scanRetry = Timer(const Duration(seconds: 5), () {
              if (_canConnect) unawaited(_ensureScan());
            });
          }
        }
      }
      if (!_disposed) notifyListeners();
    });
    _scanTransition = result.catchError((Object exception) {
      if (!_disposed) {
        error = 'Bluetooth scanning failed: $exception';
        notifyListeners();
      }
    });
    return result;
  }

  Future<void> _cancelListeners(SensorRole role) async {
    final subscriptions = _sessions.remove(role) ?? [];
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }

  Future<void> _safeDisconnect(String id) async {
    try {
      await transport.disconnect(id);
    } catch (_) {
      /* Best-effort native cleanup. */
    }
  }

  Future<void> _closeSessions() async {
    // A retry may still be canceling listeners/disconnecting. Finish that work
    // before allowing a foreground resume or a source switch to reconnect.
    await Future.wait(_recoveries.values.toList());
    final ids = sensors.values
        .map((status) => status.deviceId)
        .whereType<String>()
        .toSet();
    // Known IDs include sessions invalidated by an adapter-state callback.
    ids.addAll(_known.values.map((device) => device.id));
    for (final role in SensorRole.values) {
      await _cancelListeners(role);
    }
    await Future.wait(ids.map(_safeDisconnect));
    for (final status in sensors.values) {
      status.clear();
    }
  }

  Future<void> suspend() {
    _requestedActive = false;
    _active = false;
    _epoch++;
    for (final timer in _retries.values) {
      timer.cancel();
    }
    _retries.clear();
    _scanRetry?.cancel();
    for (final status in sensors.values) {
      status.phase = SensorPhase.disconnected;
    }
    notifyListeners();
    return _serialize(() async {
      await _stopScan();
      await _connectWork;
      await _closeSessions();
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _requestedActive = false;
    _active = false;
    _epoch++;
    _freshnessTimer.cancel();
    _scanRetry?.cancel();
    for (final timer in _retries.values) {
      timer.cancel();
    }
    unawaited(_adapterSubscription.cancel());
    unawaited(_scanSubscription.cancel());
    unawaited(() async {
      await _stopScan();
      await _connectWork;
      await _closeSessions();
    }());
    super.dispose();
  }
}
