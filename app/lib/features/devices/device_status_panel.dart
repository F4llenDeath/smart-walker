import 'dart:async';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../domain/models/sensor_status.dart';
import '../../shared/widgets/panels.dart';

class DeviceStatusPanel extends StatefulWidget {
  const DeviceStatusPanel({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  State<DeviceStatusPanel> createState() => _DeviceStatusPanelState();
}

class _DeviceStatusPanelState extends State<DeviceStatusPanel> {
  late final Timer _ageTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

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
      if (mounted) await showProblem(context, exception);
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
      final locked =
          widget.dependencies.recorder.locked || telemetry.switching || _busy;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Sensor connections',
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
              const SizedBox(height: 12),
              DetailRow('Bluetooth', switch (devices.adapter) {
                AdapterState.on => 'On',
                AdapterState.off => 'Off — enable in Settings',
                AdapterState.unauthorized => 'Permission denied',
                AdapterState.unsupported => 'Unsupported',
                AdapterState.resetting => 'Resetting',
                AdapterState.unknown => 'Unknown',
              }),
              DetailRow(
                'Permission',
                devices.hasPermissions ? 'Granted' : 'Required',
              ),
              DetailRow(
                'Discovery',
                devices.scanning ? 'Scanning…' : 'Not scanning',
              ),
              if (devices.error != null) ...[
                const SizedBox(height: 12),
                NoticeBanner(
                  'Bluetooth needs attention',
                  message: devices.error,
                  destructive: true,
                ),
              ],
              const SizedBox(height: 20),
              for (final status in devices.sensors.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SectionCard(
                    title: status.role.label,
                    subtitle: status.role.deviceName,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          telemetry.simulating
                              ? 'Simulated'
                              : status.phase.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (!telemetry.simulating &&
                            status.lastReceived != null)
                          Text(
                            'Last valid update ${DateTime.now().toUtc().difference(status.lastReceived!).inSeconds}s ago',
                            style: TextStyle(
                              color: context.theme.colors.mutedForeground,
                            ),
                          ),
                        if (!telemetry.simulating && status.error != null)
                          Text(status.error!),
                      ],
                    ),
                  ),
                ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: locked || telemetry.simulating ? null : _retry,
                child: Text(
                  _busy ? 'Reconnecting…' : 'Retry / request permission',
                ),
              ),
              const SizedBox(height: 24),
              FSwitch(
                value: telemetry.simulating,
                enabled: !locked,
                label: const Text('Simulation mode'),
                description: const Text(
                  'Disconnect hardware and generate sample telemetry. Saved trials are labeled simulated.',
                ),
                onChange: (value) async {
                  try {
                    await telemetry.setSimulation(value);
                  } catch (exception) {
                    if (context.mounted) await showProblem(context, exception);
                  }
                },
              ),
              if (widget.dependencies.recorder.locked) ...[
                const SizedBox(height: 12),
                const Text(
                  'Connection actions and source changes are locked until recording, saving, or recovery is resolved.',
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  @override
  void dispose() {
    _ageTimer.cancel();
    super.dispose();
  }
}
