import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../domain/models/sensor_status.dart';
import '../../shared/widgets/panels.dart';

class DeviceStatusPanel extends StatefulWidget {
  const DeviceStatusPanel({
    required this.dependencies,
    this.onClose,
    super.key,
  });
  final AppDependencies dependencies;
  final VoidCallback? onClose;

  @override
  State<DeviceStatusPanel> createState() => _DeviceStatusPanelState();
}

class _DeviceStatusPanelState extends State<DeviceStatusPanel> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await widget.dependencies.devices.suspend();
      final telemetry = widget.dependencies.telemetry;
      if (telemetry.foreground &&
          !telemetry.simulating &&
          !telemetry.switching) {
        await widget.dependencies.devices.start(requestPermissions: true);
      }
    } catch (exception) {
      debugPrint('Sensor retry failed: $exception');
      if (mounted) {
        await showProblem(context, 'Unable to reconnect. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.dependencies.devices,
      widget.dependencies.telemetry,
      widget.dependencies.recorder,
    ]),
    builder: (context, _) {
      final devices = widget.dependencies.devices;
      final telemetry = widget.dependencies.telemetry;
      final snapshot = telemetry.snapshot;
      final locked =
          widget.dependencies.recorder.locked || telemetry.switching || _busy;
      final connectionHint =
          _busy ||
              snapshot.ready ||
              telemetry.simulating ||
              telemetry.switching ||
              !telemetry.foreground
          ? null
          : switch (devices.adapter) {
              AdapterState.off => 'Enable Bluetooth in Settings.',
              AdapterState.unauthorized =>
                'Allow Bluetooth access in Settings, then retry.',
              AdapterState.unsupported =>
                'Bluetooth is not supported on this device.',
              _ when devices.error != null && !devices.hasPermissions =>
                'Allow Bluetooth access in Settings, then retry.',
              _ when devices.error != null =>
                'Unable to connect. Please retry.',
              _ => null,
            };
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sensor connections',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                ),
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: widget.onClose ?? () => Navigator.pop(context),
                  child: const Icon(FLucideIcons.x),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FTileGroup(
              semanticsLabel: 'Sensor readiness',
              physics: const NeverScrollableScrollPhysics(),
              divider: FItemDivider.full,
              children: [
                _sensorTile(
                  context,
                  SensorRole.leftFoot,
                  snapshot.leftReady,
                  simulated: telemetry.simulating,
                ),
                _sensorTile(
                  context,
                  SensorRole.rightFoot,
                  snapshot.rightReady,
                  simulated: telemetry.simulating,
                ),
                _sensorTile(
                  context,
                  SensorRole.radar,
                  snapshot.radarReady,
                  simulated: telemetry.simulating,
                ),
              ],
            ),
            if (connectionHint != null) ...[
              const SizedBox(height: 12),
              NoticeBanner(connectionHint, destructive: true),
            ],
            const SizedBox(height: 16),
            FButton(
              variant: FButtonVariant.outline,
              onPress: locked || telemetry.simulating ? null : _retry,
              prefix: _busy
                  ? const FCircularProgress(
                      semanticsLabel: 'Retrying sensor connections',
                    )
                  : null,
              child: const Text('Retry'),
            ),
            const SizedBox(height: 24),
            FSwitch(
              value: telemetry.simulating,
              enabled: !locked,
              label: const Text('Simulation mode'),
              onChange: (value) async {
                try {
                  await telemetry.setSimulation(value);
                } catch (exception) {
                  debugPrint('Simulation mode change failed: $exception');
                  if (context.mounted) {
                    await showProblem(
                      context,
                      'Unable to change simulation mode. Please try again.',
                    );
                  }
                }
              },
            ),
          ],
        ),
      );
    },
  );

  FTile _sensorTile(
    BuildContext context,
    SensorRole role,
    bool ready, {
    required bool simulated,
  }) => FTile.raw(
    child: Semantics(
      container: true,
      label: role.label,
      value: ready ? (simulated ? 'Ready, simulated' : 'Ready') : 'Not ready',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(child: Text(role.label)),
          Icon(
            ready ? FLucideIcons.check : FLucideIcons.x,
            size: 20,
            color: ready
                ? (context.theme.colors.brightness == Brightness.dark
                      ? Colors.green.shade400
                      : Colors.green.shade700)
                : context.theme.colors.destructive,
          ),
        ],
      ),
    ),
  );
}
