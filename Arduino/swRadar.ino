//  Wiring:
//    GPIO1  (Serial1/UART1 TX) → Radar CLI UART RX  (115200 baud)
//    GPIO2  (Serial1/UART1 RX) → Radar CLI UART TX  (for "Done" responses)
//    GPIO3  (Serial2/UART2 RX) → Radar Data UART TX (921600 baud)
//    GND                       → Radar GND


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
// Serial  (UART0) = USB-C debug
// Serial1 (UART1) = Radar CLI UART at 115200
#define CLI_RX_PIN   2   // Arduino RX ← Radar CLI TX (for "Done" responses)
#define CLI_TX_PIN   1   // Arduino TX → Radar CLI RX (send config commands)
// Serial2 (UART2) = Radar Data UART at 921600
#define DATA_RX_PIN  3   // Arduino RX ← Radar Data TX (receive radar frames)
#define DATA_TX_PIN  -1  // Not used (we only receive data)

#define CLI_BAUD    115200
#define DATA_BAUD   921600

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

// Radar Configuration (.cfg) stored in flash 
static const char* cfgCommands[] = {
  "sensorStop",
  "flushCfg",
  "dfeDataOutputMode 1",
  "channelCfg 15 5 0",
  "adcCfg 2 1",
  "adcbufCfg -1 0 1 1 1",
  "profileCfg 0 77 414 7 72.73 0 0 55 1 288 4449 0 0 30",
  "chirpCfg 0 0 0 0 0 0 0 1",
  "chirpCfg 1 1 0 0 0 0 0 4",
  "frameCfg 0 1 32 0 100 1 0",
  "lowPower 0 0",
  "guiMonitor -1 1 1 0 0 0 1",
  "cfarCfg -1 0 2 8 4 3 0 15 1",
  "cfarCfg -1 1 0 8 4 4 1 15 1",
  "multiObjBeamForming -1 1 0.5",
  "clutterRemoval -1 0",
  "calibDcRangeSig -1 0 -5 8 256",
  "extendedMaxVelocity -1 0",
  "lvdsStreamCfg -1 0 0 0",
  "compRangeBiasAndRxChanPhase 0.0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0",
  "measureRangeBiasAndRxChanPhase 0 1.5 0.2",
  "CQRxSatMonitor 0 3 7 113 0",
  "CQSigImgMonitor 0 95 6",
  "analogMonitor 0 0",
  "aoaFovCfg -1 -20 20 -20 20",
  "cfarFovCfg -1 0 0 9.70",
  "cfarFovCfg -1 1 -1 1.00",
  "calibData 0 0 0",
  "sensorStart"
};
#define NUM_CFG_COMMANDS  (sizeof(cfgCommands) / sizeof(cfgCommands[0]))

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

//  SEND RADAR CONFIGURATION via Serial1 (hardware UART1)
void sendRadarConfig() {
  Serial.println("[Radar] Sending configuration...");

  for (int i = 0; i < NUM_CFG_COMMANDS; i++) {
    Serial1.println(cfgCommands[i]);   // Send command + \n

    Serial.print("[Radar] Sent: ");
    Serial.println(cfgCommands[i]);

    // Wait for "Done" response or timeout
    unsigned long t0 = millis();
    String response = "";
    while (millis() - t0 < 200) {      // 200ms timeout per command
      while (Serial1.available()) {
        char c = Serial1.read();
        response += c;
      }
      if (response.indexOf("Done") >= 0) break;
    }

    if (response.indexOf("Done") >= 0) {
      Serial.println("  → Done");
    } else if (response.indexOf("Error") >= 0) {
      Serial.print("  → ERROR: ");
      Serial.println(response);
    } else {
      Serial.println("  → (no response, continuing)");
    }

    delay(20);  // Small gap between commands
  }

  Serial.println("[Radar] Configuration complete!");
}

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
  Serial.println("=====================================");
  Serial.println("  Smart Walker — Radar Module");
  Serial.println("  AWR1843BOOST + XIAO ESP32-S3");
  Serial.println("=====================================");

  // CLI UART (hardware UART1) — for sending config commands
  Serial1.begin(CLI_BAUD, SERIAL_8N1, CLI_RX_PIN, CLI_TX_PIN);
  Serial.println("[Radar] CLI UART (Serial1) started at 115200");

  // Wait for radar to boot
  Serial.println("[Radar] Waiting for radar to boot (3s)...");
  delay(3000);

  // Send configuration
  sendRadarConfig();
  delay(500);

  // Data UART (hardware UART2) — for receiving radar frames
  Serial2.begin(DATA_BAUD, SERIAL_8N1, DATA_RX_PIN);
  Serial.println("[Radar] Data UART (Serial2) started at 921600");

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
  while (Serial2.available()) {
    processByte((uint8_t)Serial2.read());
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
