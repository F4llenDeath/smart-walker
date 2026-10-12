import 'package:universal_ble/universal_ble.dart';

import '../../core/ble_protocol.dart';
import '../../domain/models/sensor_status.dart';
import 'ble_transport.dart';

class UniversalBleTransport implements BleTransport {
  UniversalBleTransport() {
    UniversalBle.timeout = const Duration(seconds: 12);
    UniversalBle.queueType = QueueType.global;
  }

  AdapterState _map(AvailabilityState state) => switch (state) {
    AvailabilityState.unknown => AdapterState.unknown,
    AvailabilityState.resetting => AdapterState.resetting,
    AvailabilityState.unsupported => AdapterState.unsupported,
    AvailabilityState.unauthorized => AdapterState.unauthorized,
    AvailabilityState.poweredOff => AdapterState.off,
    AvailabilityState.poweredOn => AdapterState.on,
  };

  @override
  Stream<AdapterState> get adapterChanges =>
      UniversalBle.availabilityStream.map(_map);
  @override
  Stream<DiscoveredDevice> get discoveries => UniversalBle.scanStream.map(
    (device) => DiscoveredDevice(device.deviceId, device.name),
  );
  @override
  Stream<bool> connectionChanges(String id) =>
      UniversalBle.connectionStream(id);
  @override
  Stream<List<int>> notifications(String id) =>
      UniversalBle.characteristicValueStream(
        id,
        BleProtocol.characteristicUuid,
      );
  @override
  Future<AdapterState> availability() async =>
      _map(await UniversalBle.getBluetoothAvailabilityState());
  @override
  Future<bool> permissions({bool request = false}) async {
    if (request && !await UniversalBle.hasPermissions()) {
      await UniversalBle.requestPermissions();
    }
    return UniversalBle.hasPermissions();
  }

  @override
  Future<void> startScan() => UniversalBle.startScan(
    scanFilter: ScanFilter(withServices: [BleProtocol.serviceUuid]),
    platformConfig: PlatformConfig(
      android: AndroidOptions(legacy: true, requestLocationPermission: false),
    ),
  );
  @override
  Future<void> stopScan() => UniversalBle.stopScan();
  @override
  Future<void> connect(String id) => UniversalBle.connect(
    id,
    timeout: const Duration(seconds: 12),
    autoConnect: false,
  );
  @override
  Future<void> discover(String id) async {
    final services = await UniversalBle.discoverServices(id);
    final compatible = services.any(
      (service) =>
          service.uuid.toLowerCase() == BleProtocol.serviceUuid.toLowerCase() &&
          service.characteristics.any(
            (characteristic) =>
                characteristic.uuid.toLowerCase() ==
                    BleProtocol.characteristicUuid.toLowerCase() &&
                characteristic.properties.contains(
                  CharacteristicProperty.notify,
                ),
          ),
    );
    if (!compatible) {
      throw StateError(
        'Required notifying telemetry characteristic not found.',
      );
    }
  }

  @override
  Future<void> subscribe(String id) => UniversalBle.subscribeNotifications(
    id,
    BleProtocol.serviceUuid,
    BleProtocol.characteristicUuid,
  );
  @override
  Future<void> disconnect(String id) =>
      UniversalBle.disconnect(id, timeout: const Duration(seconds: 5));
}
