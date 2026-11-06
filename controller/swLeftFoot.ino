#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "HX711.h"

#define SERVICE_UUID        "A7E8F0B1-3C54-4D92-9F3E-0A1B2C3D4E5F"
#define CHARACTERISTIC_UUID "B8F9E1C2-4D65-5EA3-A04F-1B2C3D4E5F60"
#define BATTERY_CHARACTERISTIC_UUID "C9A0F2D3-5E76-4FB4-B150-2C3D4E5F6071"

#define DEVICE_NAME         "SW-LeftFoot"
#define SEND_INTERVAL_MS    200
#define BATTERY_SAMPLE_INTERVAL_MS 1000
#define BATTERY_NOTIFY_INTERVAL_MS 10000

#define LOADCELL_DOUT_PIN  3
#define LOADCELL_SCK_PIN   2
#define CALIBRATION_FACTOR 18073.5
HX711 scale;

BLEServer*         pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
BLECharacteristic* pBatteryCharacteristic = nullptr;
bool               deviceConnected = false;
bool               oldDeviceConnected = false;
unsigned long      lastSendTime = 0;
unsigned long      lastBatterySampleTime = 0;
unsigned long      lastBatteryNotifyTime = 0;
uint16_t           batteryMillivolts = 0;
bool               batteryValid = false;

// Seeed XIAO ESP32-C5: GPIO26 enables the divider; GPIO6 measures BAT / 2.
// https://wiki.seeedstudio.com/xiao_esp32c5_getting_started/
void updateBattery() {
  uint32_t sum = 0;
  for (int i = 0; i < 16; i++) {
    sum += analogReadMilliVolts(BAT_VOLT_PIN);
  }
  uint32_t measured = (2 * sum + 8) / 16;
  bool valid = measured >= 2500 && measured <= 4500;
  if (valid) {
    // Smooth successive valid readings; never carry an old value across errors.
    batteryMillivolts = batteryValid
      ? (3 * batteryMillivolts + measured + 2) / 4
      : measured;
  } else {
    batteryMillivolts = 0;
  }
  batteryValid = valid;

  // Version 1, validity (0/1), uint16 little-endian battery millivolts.
  uint8_t packet[4] = {
    1, static_cast<uint8_t>(batteryValid),
    static_cast<uint8_t>(batteryMillivolts & 0xff),
    static_cast<uint8_t>(batteryMillivolts >> 8)
  };
  pBatteryCharacteristic->setValue(packet, sizeof(packet));
  Serial.print("Battery mV: ");
  Serial.println(batteryValid ? batteryMillivolts : 0);
}

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
  Serial.println("Starting SW-LeftFoot BLE...");

  pinMode(BAT_VOLT_PIN, INPUT);
  pinMode(BAT_VOLT_PIN_EN, OUTPUT);
  digitalWrite(BAT_VOLT_PIN_EN, HIGH);

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

  pBatteryCharacteristic = pService->createCharacteristic(
    BATTERY_CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pBatteryCharacteristic->addDescriptor(new BLE2902());
  updateBattery();
  lastBatterySampleTime = millis();

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

  // No extra delays: keep the weight send path first and independently timed.
  unsigned long now = millis();
  bool batteryValidityChanged = false;
  if (now - lastBatterySampleTime >= BATTERY_SAMPLE_INTERVAL_MS) {
    lastBatterySampleTime = now;
    bool wasValid = batteryValid;
    updateBattery();
    batteryValidityChanged = wasValid != batteryValid;
  }
  if (deviceConnected &&
      (batteryValidityChanged || now - lastBatteryNotifyTime >= BATTERY_NOTIFY_INTERVAL_MS)) {
    lastBatteryNotifyTime = now;
    pBatteryCharacteristic->notify();
  }

  //reconnection
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);  // give BLE stack time to settle
    BLEDevice::startAdvertising();
    Serial.println("Restarted advertising");
    oldDeviceConnected = false;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
  }
}
