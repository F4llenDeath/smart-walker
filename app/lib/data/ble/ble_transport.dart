import '../../domain/models/sensor_status.dart';

class DiscoveredDevice {
  const DiscoveredDevice(this.id, this.name);
  final String id;
  final String? name;
}

abstract interface class BleTransport {
  Stream<AdapterState> get adapterChanges;
  Stream<DiscoveredDevice> get discoveries;
  Stream<bool> connectionChanges(String id);
  Stream<List<int>> notifications(String id);
  Future<AdapterState> availability();
  Future<bool> permissions({bool request = false});
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String id);
  Future<void> discover(String id);
  Future<void> subscribe(String id);
  Future<void> disconnect(String id);
}
