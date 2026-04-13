//  Wiring (config is hardcoded in the mmWave sensor flash):
//    GPIO44 (RX) → Radar Data UART TX (921600 baud) J6 pin 5
//    GND         → Radar GND J6 pin 4


#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// BLE Configuration
#define DEVICE_NAME         "SW-Radar"
#define SERVICE_UUID        "A7E8F0B1-3C54-4D92-9F3E-0A1B2C3D4E5F"
#define CHARACTERISTIC_UUID "B8F9E1C2-4D65-5EA3-A04F-1B2C3D4E5F60"
#define BLE_SEND_INTERVAL_MS  200

BLEServer*         pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
bool               deviceConnected = false;
bool               oldDeviceConnected = false;
unsigned long      lastBLESend = 0;

// UART Pin Assignments
// Serial  (UART0) = USB-C debug (native USB CDC)
// Serial1 (UART1) = Radar Data UART at 921600
#define DATA_RX_PIN  44  // Arduino RX ← Radar Data TX (receive radar frames)
#define DATA_BAUD    921600

// Radar Frame Constants
static const uint8_t MAGIC_WORD[8] = {0x02, 0x01, 0x04, 0x03, 0x06, 0x05, 0x08, 0x07};
#define HEADER_SIZE             32
#define TLV_TYPE_DETECTED_POINTS 1
#define POINT_STRUCT_SIZE       16   // x(4) + y(4) + z(4) + velocity(4)

// Parser State Machine
enum ParserState {
  STATE_SYNC, STATE_HEADER, STATE_TLV_HEADER, STATE_TLV_PAYLOAD, STATE_SKIP_TLV
};

ParserState parserState = STATE_SYNC;
uint8_t  syncIdx = 0;
uint8_t  headerBuf[HEADER_SIZE];
uint8_t  tlvHeaderBuf[8];
uint16_t bufIdx = 0;
uint32_t numDetectedObj = 0;
uint32_t numTLVs = 0;
uint32_t tlvsProcessed = 0;
uint32_t currentTlvType = 0;
uint32_t currentTlvLength = 0;
uint32_t tlvBytesRead = 0;

uint8_t  pointBuf[POINT_STRUCT_SIZE];
uint16_t pointBufIdx = 0;

// Extracted Data
float closestRange = 0.0;
float closestVelocity = 0.0;

// Distance & Speed Tracking
float totalDistanceFt = 0.0;
float currentSpeedFtS = 0.0;
unsigned long lastFrameTime = 0;

// Debug 
uint32_t frameCount = 0;
unsigned long lastDebugPrint = 0;


// BLE Callbacks
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    deviceConnected = true;
    Serial.println("[BLE] Client connected");
  }
  void onDisconnect(BLEServer* s) override {
    deviceConnected = false;
    Serial.println("[BLE] Client disconnected");
  }
};

//  FRAME PARSER — byte-by-byte state machine
uint32_t readU32(const uint8_t* buf) {
  return (uint32_t)buf[0] | ((uint32_t)buf[1] << 8) |
         ((uint32_t)buf[2] << 16) | ((uint32_t)buf[3] << 24);
}

float readFloat(const uint8_t* buf) {
  float val;
  memcpy(&val, buf, 4);
  return val;
}

void resetParser() {
  parserState = STATE_SYNC;
  syncIdx = 0;
  bufIdx = 0;
  tlvsProcessed = 0;
}

void onFrameComplete() {
  frameCount++;
  unsigned long now = millis();

  if (closestRange < 9990.0) {
    float speedMs = fabsf(closestVelocity);
    currentSpeedFtS = speedMs * 3.28084;
    if (lastFrameTime > 0) {
      float dt = (now - lastFrameTime) / 1000.0;
      totalDistanceFt += currentSpeedFtS * dt;
    }
  } else {
    currentSpeedFtS = 0.0;
  }
  lastFrameTime = now;
}

void processByte(uint8_t b) {
  switch (parserState) {

    case STATE_SYNC:
      if (b == MAGIC_WORD[syncIdx]) {
        syncIdx++;
        if (syncIdx == 8) {
          parserState = STATE_HEADER;
          bufIdx = 0;
          syncIdx = 0;
        }
      } else {
        syncIdx = (b == MAGIC_WORD[0]) ? 1 : 0;
      }
      break;

    case STATE_HEADER:
      headerBuf[bufIdx++] = b;
      if (bufIdx >= HEADER_SIZE) {
        numDetectedObj = readU32(&headerBuf[20]);
        numTLVs        = readU32(&headerBuf[24]);
        tlvsProcessed  = 0;
        if (numTLVs > 0 && numTLVs <= 10) {
          parserState = STATE_TLV_HEADER;
          bufIdx = 0;
        } else {
          resetParser();
        }
      }
      break;

    case STATE_TLV_HEADER:
      tlvHeaderBuf[bufIdx++] = b;
      if (bufIdx >= 8) {
        currentTlvType   = readU32(&tlvHeaderBuf[0]);
        currentTlvLength = readU32(&tlvHeaderBuf[4]);
        tlvBytesRead = 0;
        bufIdx = 0;
        if (currentTlvLength > 65535) { resetParser(); break; }
        if (currentTlvType == TLV_TYPE_DETECTED_POINTS && numDetectedObj > 0) {
          parserState = STATE_TLV_PAYLOAD;
          pointBufIdx = 0;
          closestRange = 9999.0;
          closestVelocity = 0.0;
        } else if (currentTlvLength > 0) {
          parserState = STATE_SKIP_TLV;
        } else {
          tlvsProcessed++;
          if (tlvsProcessed < numTLVs) { parserState = STATE_TLV_HEADER; bufIdx = 0; }
          else { onFrameComplete(); resetParser(); }
        }
      }
      break;

    case STATE_TLV_PAYLOAD:
      pointBuf[pointBufIdx++] = b;
      tlvBytesRead++;
      if (pointBufIdx >= POINT_STRUCT_SIZE) {
        float x   = readFloat(&pointBuf[0]);
        float y   = readFloat(&pointBuf[4]);
        float vel = readFloat(&pointBuf[12]);
        float range = sqrtf(x * x + y * y);
        if (range < closestRange && range > 0.01) {
          closestRange = range;
          closestVelocity = vel;
        }
        pointBufIdx = 0;
      }
      if (tlvBytesRead >= currentTlvLength) {
        tlvsProcessed++;
        if (tlvsProcessed < numTLVs) { parserState = STATE_TLV_HEADER; bufIdx = 0; }
        else { onFrameComplete(); resetParser(); }
      }
      break;

    case STATE_SKIP_TLV:
      tlvBytesRead++;
      if (tlvBytesRead >= currentTlvLength) {
        tlvsProcessed++;
        if (tlvsProcessed < numTLVs) { parserState = STATE_TLV_HEADER; bufIdx = 0; }
        else { onFrameComplete(); resetParser(); }
      }
      break;
  }
}

//  SETUP
void setup() {
  // USB debug
  Serial.begin(115200);
  delay(1000);
  Serial.println("  Smart Walker — Radar Module");

  // Wait for radar to boot (config is hardcoded in sensor flash)
  Serial.println("[Radar] Waiting for radar to boot...");
  delay(2000);

  // Data UART (hardware UART1) — for receiving radar frames
  Serial1.begin(DATA_BAUD, SERIAL_8N1, DATA_RX_PIN);
  Serial.println("[Radar] Data UART (Serial1) started at 921600 on GPIO44");

  // BLE setup (same pattern as swLeftFoot / swRightFoot)
  Serial.println("[BLE] Initializing...");
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

  BLEAdvertising* pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->setMinPreferred(0x06);
  pAdv->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("[BLE] Advertising as SW-Radar");

  lastFrameTime = millis();
  lastBLESend = millis();
  lastDebugPrint = millis();
  Serial.println("[Radar] Ready — listening for radar data...");
}

//  MAIN LOOP
void loop() {
  // 1. Read all available bytes from Data UART (fast, non-blocking)
  while (Serial1.available()) {
    processByte((uint8_t)Serial1.read());
  }

  // 2. BLE notify every 200ms
  if (deviceConnected && (millis() - lastBLESend >= BLE_SEND_INTERVAL_MS)) {
    lastBLESend = millis();
    char buf[32];
    snprintf(buf, sizeof(buf), "%.2f,%.2f", totalDistanceFt, currentSpeedFtS);
    pCharacteristic->setValue(buf);
    pCharacteristic->notify();
  }

  // 3. BLE reconnection handling
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Restarted advertising");
    oldDeviceConnected = false;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
  }

  // 4. Debug print every 1 second
  unsigned long now = millis();
  if (now - lastDebugPrint >= 1000) {
    lastDebugPrint = now;
    Serial.print("[Radar] Frames: ");
    Serial.print(frameCount);
    Serial.print(" | Distance: ");
    Serial.print(totalDistanceFt, 2);
    Serial.print(" ft | Speed: ");
    Serial.print(currentSpeedFtS, 2);
    Serial.print(" ft/s | Range: ");
    Serial.print(closestRange < 9990 ? closestRange * 3.28084 : 0.0, 2);
    Serial.print(" ft | BLE: ");
    Serial.println(deviceConnected ? "connected" : "waiting");
  }
}
