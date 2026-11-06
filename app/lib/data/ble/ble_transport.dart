import '../../domain/models/sensor_status.dart';

class DiscoveredDevice {
  const DiscoveredDevice(this.id, this.name);
  final String id;
  final String? name;
}

class SensorCapabilities {
  const SensorCapabilities({this.battery = false});
  final bool battery;
}

abstract interface class BleTransport {
  Stream<AdapterState> get adapterChanges;
  Stream<DiscoveredDevice> get discoveries;
  Stream<bool> connectionChanges(String id);
  Stream<List<int>> notifications(String id);
  Stream<List<int>> batteryNotifications(String id);
  Future<AdapterState> availability();
  Future<bool> permissions({bool request = false});
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String id);
  Future<SensorCapabilities> discover(String id);
  Future<void> subscribe(String id);
  Future<void> subscribeBattery(String id);
  Future<List<int>> readBattery(String id);
  Future<void> disconnect(String id);
}
