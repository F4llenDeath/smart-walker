//  Wiring:
//    D0 (Serial1 RX) ←── Radar Data UART TX  (921600 baud, binary frames)
//    D2 (GPIO)        ──→ Radar CLI UART RX   (115200 baud, config commands)
//    GND              ─── Radar GND
//    USB              ─── PC (debug serial)

#include <ArduinoBLE.h>

#define DEVICE_NAME         "SW-Radar"
#define SERVICE_UUID        "A7E8F0B1-3C54-4D92-9F3E-0A1B2C3D4E5F"
#define CHARACTERISTIC_UUID "B8F9E1C2-4D65-5EA3-A04F-1B2C3D4E5F60"

BLEService radarService(SERVICE_UUID);
BLECharacteristic radarChar(CHARACTERISTIC_UUID,
                            BLERead | BLENotify, 32);  // max 32 bytes

#define CLI_TX_PIN  2       // Bit-banged software serial TX → Radar CLI RX
#define DATA_BAUD   921600  // Radar data UART baud rate

#define BLE_SEND_INTERVAL_MS  200   // Send BLE update every 200ms
#define FRAME_PERIOD_MS       100   // Radar outputs at 10 fps (100ms cfg)

// Radar Frame Constants
static const uint8_t MAGIC_WORD[8] = {0x02, 0x01, 0x04, 0x03, 0x06, 0x05, 0x08, 0x07};
#define HEADER_SIZE  32

// TLV type for detected points (xWR18xx OOB demo)
#define TLV_TYPE_DETECTED_POINTS  1

// Each detected point: x(float) + y(float) + z(float) + velocity(float) = 16 bytes
#define POINT_STRUCT_SIZE  16

enum ParserState {
  STATE_SYNC,           // Searching for magic word
  STATE_HEADER,         // Reading 32-byte frame header
  STATE_TLV_HEADER,     // Reading 8-byte TLV header (type + length)
  STATE_TLV_PAYLOAD,    // Reading TLV payload
  STATE_SKIP_TLV        // Skipping unwanted TLV payload bytes
};

ParserState parserState = STATE_SYNC;
uint8_t syncIdx = 0;                    // Progress through magic word matching
uint8_t headerBuf[HEADER_SIZE];         // Buffer for frame header
uint8_t tlvHeaderBuf[8];               // Buffer for TLV header
uint16_t bufIdx = 0;                    // Current position in buffer
uint32_t numDetectedObj = 0;            // From frame header
uint32_t numTLVs = 0;                   // From frame header
uint32_t tlvsProcessed = 0;             // TLVs processed in current frame
uint32_t currentTlvType = 0;            // Current TLV type
uint32_t currentTlvLength = 0;          // Current TLV payload length
uint32_t tlvBytesRead = 0;             // Bytes read in current TLV payload

// Point data buffer (read one point at a time)
uint8_t pointBuf[POINT_STRUCT_SIZE];
uint16_t pointBufIdx = 0;
uint16_t pointsRead = 0;

// Extracted Data 
float closestRange = 0.0;              // Range to closest detected object (m)
float closestVelocity = 0.0;           // Velocity of closest object (m/s)
bool  newFrameAvailable = false;       // Flag: new frame parsed

// Distance & Speed Tracking 
float totalDistanceFt = 0.0;           // Accumulated distance traveled (ft)
float currentSpeedFtS = 0.0;           // Current speed (ft/s)
unsigned long lastFrameTime = 0;       // Timestamp of last parsed frame

// BLE Timing 
unsigned long lastBLESend = 0;
bool bleConnected = false;

// Debug 
uint32_t frameCount = 0;               // Total frames parsed
uint32_t lastDebugPrint = 0;


//  RADAR CONFIGURATION (.cfg file)
const char cfg_00[] PROGMEM = "sensorStop";
const char cfg_01[] PROGMEM = "flushCfg";
const char cfg_02[] PROGMEM = "dfeDataOutputMode 1";
const char cfg_03[] PROGMEM = "channelCfg 15 5 0";
const char cfg_04[] PROGMEM = "adcCfg 2 1";
const char cfg_05[] PROGMEM = "adcbufCfg -1 0 1 1 1";
const char cfg_06[] PROGMEM = "profileCfg 0 77 414 7 72.73 0 0 55 1 288 4449 0 0 30";
const char cfg_07[] PROGMEM = "chirpCfg 0 0 0 0 0 0 0 1";
const char cfg_08[] PROGMEM = "chirpCfg 1 1 0 0 0 0 0 4";
const char cfg_09[] PROGMEM = "frameCfg 0 1 32 0 100 1 0";
const char cfg_10[] PROGMEM = "lowPower 0 0";
const char cfg_11[] PROGMEM = "guiMonitor -1 1 1 0 0 0 1";
const char cfg_12[] PROGMEM = "cfarCfg -1 0 2 8 4 3 0 15 1";
const char cfg_13[] PROGMEM = "cfarCfg -1 1 0 8 4 4 1 15 1";
const char cfg_14[] PROGMEM = "multiObjBeamForming -1 1 0.5";
const char cfg_15[] PROGMEM = "clutterRemoval -1 0";
const char cfg_16[] PROGMEM = "calibDcRangeSig -1 0 -5 8 256";
const char cfg_17[] PROGMEM = "extendedMaxVelocity -1 0";
const char cfg_18[] PROGMEM = "lvdsStreamCfg -1 0 0 0";
const char cfg_19[] PROGMEM = "compRangeBiasAndRxChanPhase 0.0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0";
const char cfg_20[] PROGMEM = "measureRangeBiasAndRxChanPhase 0 1.5 0.2";
const char cfg_21[] PROGMEM = "CQRxSatMonitor 0 3 7 113 0";
const char cfg_22[] PROGMEM = "CQSigImgMonitor 0 95 6";
const char cfg_23[] PROGMEM = "analogMonitor 0 0";
const char cfg_24[] PROGMEM = "aoaFovCfg -1 -20 20 -20 20";
const char cfg_25[] PROGMEM = "cfarFovCfg -1 0 0 9.70";
const char cfg_26[] PROGMEM = "cfarFovCfg -1 1 -1 1.00";
const char cfg_27[] PROGMEM = "calibData 0 0 0";
const char cfg_28[] PROGMEM = "sensorStart";

const char* const cfgCommands[] PROGMEM = {
  cfg_00, cfg_01, cfg_02, cfg_03, cfg_04, cfg_05, cfg_06, cfg_07,
  cfg_08, cfg_09, cfg_10, cfg_11, cfg_12, cfg_13, cfg_14, cfg_15,
  cfg_16, cfg_17, cfg_18, cfg_19, cfg_20, cfg_21, cfg_22, cfg_23,
  cfg_24, cfg_25, cfg_26, cfg_27, cfg_28
};

#define NUM_CFG_COMMANDS  29

//  BIT-BANGED SOFTWARE SERIAL TX (115200 baud on CLI_TX_PIN)

// Bit period for 115200 baud ≈ 8.68 µs
// delayMicroseconds(8) + overhead ≈ 8.68 µs on ARM core
#define BIT_DELAY_US  8

void softSerialBegin() {
  pinMode(CLI_TX_PIN, OUTPUT);
  digitalWrite(CLI_TX_PIN, HIGH);  // Idle state is HIGH for UART
  delay(10);
}

void softSerialWriteByte(uint8_t b) {
  noInterrupts();
  
  // Start bit (LOW)
  digitalWrite(CLI_TX_PIN, LOW);
  delayMicroseconds(BIT_DELAY_US);
  
  // 8 data bits (LSB first)
  for (uint8_t i = 0; i < 8; i++) {
    digitalWrite(CLI_TX_PIN, (b >> i) & 1);
    delayMicroseconds(BIT_DELAY_US);
  }
  
  // Stop bit (HIGH)
  digitalWrite(CLI_TX_PIN, HIGH);
  delayMicroseconds(BIT_DELAY_US);
  
  interrupts();
}

void softSerialPrint(const char* str) {
  while (*str) {
    softSerialWriteByte((uint8_t)*str++);
  }
}

void softSerialPrintln(const char* str) {
  softSerialPrint(str);
  softSerialWriteByte('\n');
}

// Send radar config

void sendRadarConfig() {
  char lineBuf[128];  // Temporary buffer for reading from PROGMEM
  
  Serial.println("[Radar] Sending configuration...");
  
  for (int i = 0; i < NUM_CFG_COMMANDS; i++) {
    // Read command string from PROGMEM
    const char* cmdPtr = (const char*)pgm_read_ptr(&cfgCommands[i]);
    strcpy_P(lineBuf, cmdPtr);
    
    // Send via bit-banged serial
    softSerialPrintln(lineBuf);
    
    // Debug output
    Serial.print("[Radar] Sent: ");
    Serial.println(lineBuf);
    
    // Wait for radar to process command
    // sensorStart needs extra time
    if (i == NUM_CFG_COMMANDS - 1) {
      delay(100);  // Extra delay for sensorStart
    } else {
      delay(50);   // Normal delay between commands
    }
  }
  
  Serial.println("[Radar] Configuration complete!");
}

//  FRAME PARSER — Streaming state machine, processes bytes one at a time

// Helper: read a uint32_t from a byte buffer (little-endian)
uint32_t readU32(const uint8_t* buf) {
  return (uint32_t)buf[0] |
         ((uint32_t)buf[1] << 8) |
         ((uint32_t)buf[2] << 16) |
         ((uint32_t)buf[3] << 24);
}

// Helper: read a float from a byte buffer (little-endian, IEEE 754)
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

void processByte(uint8_t b) {
  switch (parserState) {
    
    // SYNC: Search for 8-byte magic word
    case STATE_SYNC:
      if (b == MAGIC_WORD[syncIdx]) {
        syncIdx++;
        if (syncIdx == 8) {
          // Magic word found! Move to header.
          parserState = STATE_HEADER;
          bufIdx = 0;
          syncIdx = 0;
        }
      } else {
        // Mismatch — restart sync
        syncIdx = (b == MAGIC_WORD[0]) ? 1 : 0;
      }
      break;
    
    // HEADER: Read 32-byte frame header 
    case STATE_HEADER:
      headerBuf[bufIdx++] = b;
      if (bufIdx >= HEADER_SIZE) {
        // Parse header fields
        // uint32_t version        = readU32(&headerBuf[0]);
        // uint32_t totalPacketLen = readU32(&headerBuf[4]);
        // uint32_t platform       = readU32(&headerBuf[8]);
        // uint32_t frameNumber    = readU32(&headerBuf[12]);
        // uint32_t timeCpuCycles  = readU32(&headerBuf[16]);
        numDetectedObj            = readU32(&headerBuf[20]);
        numTLVs                   = readU32(&headerBuf[24]);
        // uint32_t subFrameNumber = readU32(&headerBuf[28]);
        
        tlvsProcessed = 0;
        
        // Sanity check
        if (numTLVs > 0 && numTLVs <= 10) {
          parserState = STATE_TLV_HEADER;
          bufIdx = 0;
        } else {
          // Invalid — go back to sync
          resetParser();
        }
      }
      break;
    
    // ── TLV HEADER: Read 8-byte TLV header (type + length) ─────
    case STATE_TLV_HEADER:
      tlvHeaderBuf[bufIdx++] = b;
      if (bufIdx >= 8) {
        currentTlvType   = readU32(&tlvHeaderBuf[0]);
        currentTlvLength = readU32(&tlvHeaderBuf[4]);
        tlvBytesRead = 0;
        bufIdx = 0;
        
        // Sanity check on length
        if (currentTlvLength > 65535) {
          resetParser();
          break;
        }
        
        if (currentTlvType == TLV_TYPE_DETECTED_POINTS && numDetectedObj > 0) {
          // Parse detected points
          parserState = STATE_TLV_PAYLOAD;
          pointBufIdx = 0;
          pointsRead = 0;
          closestRange = 9999.0;  // Reset for this frame
          closestVelocity = 0.0;
        } else if (currentTlvLength > 0) {
          // Skip this TLV's payload
          parserState = STATE_SKIP_TLV;
        } else {
          // Zero-length TLV, move to next
          tlvsProcessed++;
          if (tlvsProcessed < numTLVs) {
            parserState = STATE_TLV_HEADER;
            bufIdx = 0;
          } else {
            // Frame complete
            onFrameComplete();
            resetParser();
          }
        }
      }
      break;
    
    // ── TLV PAYLOAD: Read detected points ───────────────────────
    case STATE_TLV_PAYLOAD:
      pointBuf[pointBufIdx++] = b;
      tlvBytesRead++;
      
      // One complete point (16 bytes)?
      if (pointBufIdx >= POINT_STRUCT_SIZE) {
        float x   = readFloat(&pointBuf[0]);
        float y   = readFloat(&pointBuf[4]);
        // float z = readFloat(&pointBuf[8]);   // Not needed for 2D range
        float vel = readFloat(&pointBuf[12]);
        
        // Compute 2D range (horizontal distance)
        float range = sqrtf(x * x + y * y);
        
        // Keep the closest detected point
        if (range < closestRange && range > 0.01) {
          closestRange = range;
          closestVelocity = vel;
        }
        
        pointsRead++;
        pointBufIdx = 0;
      }
      
      // Done with this TLV?
      if (tlvBytesRead >= currentTlvLength) {
        tlvsProcessed++;
        if (tlvsProcessed < numTLVs) {
          parserState = STATE_TLV_HEADER;
          bufIdx = 0;
        } else {
          onFrameComplete();
          resetParser();
        }
      }
      break;
    
    // ── SKIP TLV: Discard unwanted TLV payload bytes ────────────
    case STATE_SKIP_TLV:
      tlvBytesRead++;
      if (tlvBytesRead >= currentTlvLength) {
        tlvsProcessed++;
        if (tlvsProcessed < numTLVs) {
          parserState = STATE_TLV_HEADER;
          bufIdx = 0;
        } else {
          onFrameComplete();
          resetParser();
        }
      }
      break;
  }
}

//  FRAME COMPLETE — Called when a full frame has been parsed

void onFrameComplete() {
  frameCount++;
  unsigned long now = millis();
  
  if (closestRange < 9990.0) {
    // Valid detection — update speed and accumulate distance
    float speedMs = fabsf(closestVelocity);           // m/s (absolute)
    currentSpeedFtS = speedMs * 3.28084;              // Convert to ft/s
    
    // Accumulate distance traveled
    if (lastFrameTime > 0) {
      float dt = (now - lastFrameTime) / 1000.0;      // seconds since last frame
      totalDistanceFt += currentSpeedFtS * dt;         // distance = speed × time
    }
  } else {
    // No objects detected
    currentSpeedFtS = 0.0;
  }
  
  lastFrameTime = now;
  newFrameAvailable = true;
}

//  BLE SETUP & UPDATE

void setupBLE() {
  Serial.println("[BLE] Initializing...");
  
  if (!BLE.begin()) {
    Serial.println("[BLE] Failed to start BLE!");
    while (1);  // Halt
  }
  
  BLE.setLocalName(DEVICE_NAME);
  BLE.setAdvertisedService(radarService);
  radarService.addCharacteristic(radarChar);
  BLE.addService(radarService);
  
  // Set initial value
  radarChar.writeValue("0.00,0.00");
  
  BLE.advertise();
  Serial.println("[BLE] Advertising as SW-Radar");
}

void updateBLE() {
  BLE.poll();  // Process BLE events
  
  BLEDevice central = BLE.central();
  if (central) {
    if (!bleConnected) {
      Serial.print("[BLE] Connected: ");
      Serial.println(central.address());
      bleConnected = true;
    }
    
    unsigned long now = millis();
    if (now - lastBLESend >= BLE_SEND_INTERVAL_MS) {
      lastBLESend = now;
      
      // Format: "distance_ft,speed_ft_s"
      char buf[32];
      snprintf(buf, sizeof(buf), "%.2f,%.2f", totalDistanceFt, currentSpeedFtS);
      radarChar.writeValue(buf);
    }
  } else {
    if (bleConnected) {
      Serial.println("[BLE] Disconnected");
      bleConnected = false;
    }
  }
}

//  SETUP

void setup() {
  // USB Serial for debug
  Serial.begin(115200);
  delay(1000);
  Serial.println("  Smart Walker — Radar Module");
  
  // Initialize bit-banged CLI TX pin
  softSerialBegin();
  
  // Wait for radar to boot after power-up
  Serial.println("[Radar] Waiting for radar to boot (3s)...");
  delay(3000);
  
  // Send .cfg configuration to radar via CLI UART
  sendRadarConfig();
  
  // Small delay for radar to start processing
  delay(500);
  
  // Start Data UART at 921600 baud
  Serial1.begin(DATA_BAUD);
  Serial.println("[Radar] Data UART started at 921600 baud");
  
  // Initialize BLE
  setupBLE();
  
  // Initialize timing
  lastFrameTime = millis();
  lastBLESend = millis();
  lastDebugPrint = millis();
  
  Serial.println("[Radar] Ready — listening for radar data...");
}

//  MAIN LOOP

void loop() {
  // 1. Read all available bytes from radar Data UART 
  //    Must be done as fast as possible to avoid buffer overflow at 921600 baud
  while (Serial1.available()) {
    uint8_t b = Serial1.read();
    processByte(b);
  }
  
  // 2. Update BLE 
  updateBLE();
  
  // 3. Debug output every 1 second 
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
    Serial.println(bleConnected ? "connected" : "waiting");
  }
}
