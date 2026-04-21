#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "HX711.h"

#define SERVICE_UUID        "A7E8F0B1-3C54-4D92-9F3E-0A1B2C3D4E5F"
#define CHARACTERISTIC_UUID "B8F9E1C2-4D65-5EA3-A04F-1B2C3D4E5F60"

#define DEVICE_NAME         "SW-RightFoot"
#define SEND_INTERVAL_MS    200

#define LOADCELL_DOUT_PIN  3
#define LOADCELL_SCK_PIN   2
#define CALIBRATION_FACTOR 18073.5
HX711 scale;

BLEServer*         pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
bool               deviceConnected = false;
bool               oldDeviceConnected = false;
unsigned long      lastSendTime = 0;

//connection status
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    deviceConnected = true;
    Serial.println("Client connected");
  }
  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    Serial.println("Client disconnected");
  }
};

float readWeight() {
  if (scale.is_ready()) {
    return scale.get_units(1);  
  }
  return 0.0;
}

void setup() {
  Serial.begin(115200);
  Serial.println("Starting SW-RightFoot BLE...");

  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  scale.set_scale(CALIBRATION_FACTOR);  // -18760.0
  scale.tare();

  BLEDevice::init(DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started — waiting for connection...");
}

void loop() {
  if (deviceConnected && (millis() - lastSendTime >= SEND_INTERVAL_MS)) {
    lastSendTime = millis();

    float weight = readWeight();

    char buf[16];
    snprintf(buf, sizeof(buf), "%.2f", weight);

    pCharacteristic->setValue(buf);
    pCharacteristic->notify();

    Serial.print("Sent: ");
    Serial.println(buf);
  }

  //reconnection
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);  
    BLEDevice::startAdvertising();
    Serial.println("Restarted advertising");
    oldDeviceConnected = false;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
  }
}
