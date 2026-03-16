import Foundation
import CoreBluetooth

private let serviceUUID        = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
private let characteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABD")

private let leftFootName  = "SW-LeftFoot"
private let rightFootName = "SW-RightFoot"
private let radarName     = "SW-Radar"

class BluetoothManager: NSObject, ObservableObject {
    
    @Published var weightLeft: Double = 0.0     
    @Published var weightRight: Double = 0.0    
    @Published var distanceFt: Double = 0.0     
    @Published var speedFtS: Double = 0.0       
    
    var weightTotal: Double { weightLeft + weightRight }
    
    @Published var leftFootConnected: Bool = false
    @Published var rightFootConnected: Bool = false
    @Published var radarConnected: Bool = false
    
    @Published var isBluetoothOn: Bool = false
    @Published var isScanning: Bool = false
    
    private var centralManager: CBCentralManager!
    
    private var leftFootPeripheral: CBPeripheral?
    private var rightFootPeripheral: CBPeripheral?
    private var radarPeripheral: CBPeripheral?

    override init() {
        super.init()
        // queue: nil → callbacks on main thread
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        
        // Scan for peripherals advertising our service UUID
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
        print("[BLE] Scanning started...")
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        print("[BLE] Scanning stopped")
    }
    
    /// Check if all 3 devices are connected
    var allConnected: Bool {
        leftFootConnected && rightFootConnected && radarConnected
    }
    
    var connectedCount: Int {
        (leftFootConnected ? 1 : 0) +
        (rightFootConnected ? 1 : 0) +
        (radarConnected ? 1 : 0)
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    
    /// Called when Bluetooth state changes
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            isBluetoothOn = true
            print("[BLE] Bluetooth is ON")
            startScanning()
            
        case .poweredOff:
            isBluetoothOn = false
            isScanning = false
            print("[BLE] Bluetooth is OFF")
            
        case .unauthorized:
            isBluetoothOn = false
            print("[BLE] Bluetooth unauthorized — check app permissions")
            
        case .unsupported:
            isBluetoothOn = false
            print("[BLE] Bluetooth not supported on this device")
            
        default:
            print("[BLE] Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    /// Called when a peripheral is discovered during scanning
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let name = peripheral.name else { return }
        
        switch name {
        case leftFootName:
            guard leftFootPeripheral == nil else { return }  // already connecting/connected
            print("[BLE] Found \(name) (RSSI: \(RSSI))")
            leftFootPeripheral = peripheral
            centralManager.connect(peripheral, options: nil)
            
        case rightFootName:
            guard rightFootPeripheral == nil else { return }
            print("[BLE] Found \(name) (RSSI: \(RSSI))")
            rightFootPeripheral = peripheral
            centralManager.connect(peripheral, options: nil)
            
        case radarName:
            guard radarPeripheral == nil else { return }
            print("[BLE] Found \(name) (RSSI: \(RSSI))")
            radarPeripheral = peripheral
            centralManager.connect(peripheral, options: nil)
            
        default:
            break  // ignore unknown devices
        }
        
        // Stop scanning if all 3 are connected/connecting
        if leftFootPeripheral != nil && rightFootPeripheral != nil && radarPeripheral != nil {
            stopScanning()
        }
    }
    
    /// Called when a peripheral is successfully connected
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "Unknown"
        print("[BLE] Connected to \(name)")
        
        updateConnectionStatus(for: peripheral, connected: true)
        
        // Set ourselves as the peripheral's delegate and discover our service
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    /// Called when a connection attempt fails
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? "Unknown"
        print("[BLE] Failed to connect to \(name): \(error?.localizedDescription ?? "unknown error")")
        
        clearPeripheralReference(peripheral)
        startScanning()
    }
    
    /// Called when a peripheral disconnects
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? "Unknown"
        print("[BLE] Disconnected from \(name): \(error?.localizedDescription ?? "no error")")
        
        updateConnectionStatus(for: peripheral, connected: false)
        
        clearPeripheralReference(peripheral)
        startScanning()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    
    /// Called when services are discovered on a connected peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("[BLE] Error discovering services: \(error.localizedDescription)")
            return
        }
        
        let name = peripheral.name ?? "Unknown"
        
        for service in peripheral.services ?? [] {
            print("[BLE] \(name): found service \(service.uuid)")
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    /// Called when characteristics are discovered within a service
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("[BLE] Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        let name = peripheral.name ?? "Unknown"
        
        for characteristic in service.characteristics ?? [] {
            print("[BLE] \(name): found characteristic \(characteristic.uuid)")
            
            // Subscribe to notifications — this is what triggers didUpdateValueFor
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
                print("[BLE] \(name): subscribed to notifications")
            }
        }
    }
    
    /// Called every time the Arduino sends a BLE notify with new data
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BLE] Error receiving data: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value,
              let str = String(data: data, encoding: .utf8) else {
            return
        }
        
        // Route the data based on which peripheral sent it
        if peripheral === leftFootPeripheral {
            // Left foot sends
            if let weight = Double(str) {
                weightLeft = weight
            }
            
        } else if peripheral === rightFootPeripheral {
            // Right foot sends
            if let weight = Double(str) {
                weightRight = weight
            }
            
        } else if peripheral === radarPeripheral {
            // Radar sends, to be modified
            let parts = str.split(separator: ",")
            if parts.count == 2 {
                if let dist = Double(parts[0]) {
                    distanceFt = dist
                }
                if let speed = Double(parts[1]) {
                    speedFtS = speed
                }
            }
        }
    }
}


private extension BluetoothManager {
    
    /// Update the @Published connection status for a given peripheral
    func updateConnectionStatus(for peripheral: CBPeripheral, connected: Bool) {
        if peripheral === leftFootPeripheral {
            leftFootConnected = connected
        } else if peripheral === rightFootPeripheral {
            rightFootConnected = connected
        } else if peripheral === radarPeripheral {
            radarConnected = connected
        }
    }
    
    /// Clear our stored reference to a peripheral (so we can rediscover it)
    func clearPeripheralReference(_ peripheral: CBPeripheral) {
        if peripheral === leftFootPeripheral {
            leftFootPeripheral = nil
        } else if peripheral === rightFootPeripheral {
            rightFootPeripheral = nil
        } else if peripheral === radarPeripheral {
            radarPeripheral = nil
        }
    }
}
