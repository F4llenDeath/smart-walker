# Radar parsing code based on AWR1843-Read-Data-Python by Ibai Gorordo
# Original: https://github.com/ibaiGorordo/AWR1843-Read-Data-Python-MMWAVE-SDK-3-
# Licensed under MIT License
# Modified for Smart Walker: replaced plotting with BLE server output

import serial
import time
import math
import asyncio
import threading
import numpy as np
from bless import BlessServer, BlessGATTCharacteristic, GATTCharacteristicProperties, GATTAttributePermissions

# Change the configuration file name
configFileName = 'AWR1843config.cfg'

CLIport = {}
Dataport = {}
byteBuffer = np.zeros(2**15,dtype = 'uint8')
byteBufferLength = 0;


# ------------------------------------------------------------------

# Function to configure the serial ports and send the data from
# the configuration file to the radar
def serialConfig(configFileName):

    global CLIport
    global Dataport

    # Raspberry pi
    CLIport  = serial.Serial('/dev/ttyACM0', 115200, timeout=0.1)
    Dataport = serial.Serial('/dev/ttyACM1', 921600, timeout=0.1)

    # Windows
    #CLIport = serial.Serial('COM8', 115200)
    #Dataport = serial.Serial('COM9', 921600)

    # Halt any previous session, drain stale CLI/data, then reconfigure.
    CLIport.write(b'sensorStop\n')
    _drain_until_quiet(CLIport, quiet_ms=300, max_wait_s=2.0)
    _drain_all(Dataport)

    with open(configFileName) as f:
        config = [line.rstrip('\r\n') for line in f]

    for line in config:
        stripped = line.strip()
        if not stripped or stripped.startswith('%'):
            print(line)
            continue

        CLIport.reset_input_buffer()
        CLIport.write((line + '\n').encode())
        print(line)

        if not _wait_for_ack(CLIport, timeout_s=1.2):
            print(f"[Radar] WARNING: no ack for '{line}'")

    return CLIport, Dataport

# Discard bytes until `port` is silent for quiet_ms (cap: max_wait_s).
def _drain_until_quiet(port, quiet_ms=300, max_wait_s=2.0):
    quiet_s = quiet_ms / 1000.0
    deadline = time.time() + max_wait_s
    last_data = time.time()
    while time.time() < deadline:
        if port.in_waiting:
            port.read(port.in_waiting)
            last_data = time.time()
        elif time.time() - last_data >= quiet_s:
            return
        time.sleep(0.02)

# Discard anything currently buffered on `port`.
def _drain_all(port):
    try:
        while port.in_waiting:
            port.read(port.in_waiting)
            time.sleep(0.01)
    except Exception:
        pass

# Return True if 'Done' appears on `port` within timeout_s.
def _wait_for_ack(port, timeout_s=1.2):
    deadline = time.time() + timeout_s
    buf = b''
    while time.time() < deadline:
        if port.in_waiting:
            buf += port.read(port.in_waiting)
            low = buf.lower()
            if b'done' in low:
                return True
            if b'error' in low or b'ignored' in low:
                return False
        time.sleep(0.02)
    return False


# ------------------------------------------------------------------

# Function to parse the data inside the configuration file
def parseConfigFile(configFileName):
    configParameters = {} # Initialize an empty dictionary to store the configuration parameters
    
    # Read the configuration file and send it to the board
    config = [line.rstrip('\r\n') for line in open(configFileName)]
    for i in config:
        
        # Split the line
        splitWords = i.split(" ")
        
        # Hard code the number of antennas, change if other configuration is used
        numRxAnt = 4
        numTxAnt = 3
        
        # Get the information about the profile configuration
        if "profileCfg" in splitWords[0]:
            startFreq = int(float(splitWords[2]))
            idleTime = int(splitWords[3])
            rampEndTime = float(splitWords[5])
            freqSlopeConst = float(splitWords[8])
            numAdcSamples = int(splitWords[10])
            numAdcSamplesRoundTo2 = 1;
            
            while numAdcSamples > numAdcSamplesRoundTo2:
                numAdcSamplesRoundTo2 = numAdcSamplesRoundTo2 * 2;
                
            digOutSampleRate = int(splitWords[11]);
            
        # Get the information about the frame configuration    
        elif "frameCfg" in splitWords[0]:
            
            chirpStartIdx = int(splitWords[1]);
            chirpEndIdx = int(splitWords[2]);
            numLoops = int(splitWords[3]);
            numFrames = int(splitWords[4]);
            framePeriodicity = float(splitWords[5]);

            
    # Combine the read data to obtain the configuration parameters           
    numChirpsPerFrame = (chirpEndIdx - chirpStartIdx + 1) * numLoops
    configParameters["numDopplerBins"] = numChirpsPerFrame / numTxAnt
    configParameters["numRangeBins"] = numAdcSamplesRoundTo2
    configParameters["rangeResolutionMeters"] = (3e8 * digOutSampleRate * 1e3) / (2 * freqSlopeConst * 1e12 * numAdcSamples)
    configParameters["rangeIdxToMeters"] = (3e8 * digOutSampleRate * 1e3) / (2 * freqSlopeConst * 1e12 * configParameters["numRangeBins"])
    configParameters["dopplerResolutionMps"] = 3e8 / (2 * startFreq * 1e9 * (idleTime + rampEndTime) * 1e-6 * configParameters["numDopplerBins"] * numTxAnt)
    configParameters["maxRange"] = (300 * 0.9 * digOutSampleRate)/(2 * freqSlopeConst * 1e3)
    configParameters["maxVelocity"] = 3e8 / (4 * startFreq * 1e9 * (idleTime + rampEndTime) * 1e-6 * numTxAnt)
    
    return configParameters
   
# ------------------------------------------------------------------

# Funtion to read and parse the incoming data
def readAndParseData18xx(Dataport, configParameters):
    global byteBuffer, byteBufferLength
    
    # Constants
    OBJ_STRUCT_SIZE_BYTES = 12;
    BYTE_VEC_ACC_MAX_SIZE = 2**15;
    MMWDEMO_UART_MSG_DETECTED_POINTS = 1;
    MMWDEMO_UART_MSG_RANGE_PROFILE   = 2;
    maxBufferSize = 2**15;
    tlvHeaderLengthInBytes = 8;
    pointLengthInBytes = 16;
    magicWord = [2, 1, 4, 3, 6, 5, 8, 7]
    
    # Initialize variables
    magicOK = 0 # Checks if magic number has been read
    dataOK = 0 # Checks if the data has been read correctly
    frameNumber = 0
    detObj = {}
    
    readBuffer = Dataport.read(Dataport.in_waiting)
    byteVec = np.frombuffer(readBuffer, dtype = 'uint8')
    byteCount = len(byteVec)
    
    # Check that the buffer is not full, and then add the data to the buffer
    if (byteBufferLength + byteCount) < maxBufferSize:
        byteBuffer[byteBufferLength:byteBufferLength + byteCount] = byteVec[:byteCount]
        byteBufferLength = byteBufferLength + byteCount
        
    # Check that the buffer has some data
    if byteBufferLength > 16:
        
        # Check for all possible locations of the magic word
        possibleLocs = np.where(byteBuffer == magicWord[0])[0]

        # Confirm that is the beginning of the magic word and store the index in startIdx
        startIdx = []
        for loc in possibleLocs:
            check = byteBuffer[loc:loc+8]
            if np.all(check == magicWord):
                startIdx.append(loc)
               
        # Check that startIdx is not empty
        if startIdx:
            
            # Remove the data before the first start index
            if startIdx[0] > 0 and startIdx[0] < byteBufferLength:
                byteBuffer[:byteBufferLength-startIdx[0]] = byteBuffer[startIdx[0]:byteBufferLength]
                byteBuffer[byteBufferLength-startIdx[0]:] = np.zeros(len(byteBuffer[byteBufferLength-startIdx[0]:]),dtype = 'uint8')
                byteBufferLength = byteBufferLength - startIdx[0]
                
            # Check that there have no errors with the byte buffer length
            if byteBufferLength < 0:
                byteBufferLength = 0
                
            # word array to convert 4 bytes to a 32 bit number
            word = [1, 2**8, 2**16, 2**24]
            
            # Read the total packet length
            totalPacketLen = np.matmul(byteBuffer[12:12+4],word)
            
            # Check that all the packet has been read
            if (byteBufferLength >= totalPacketLen) and (byteBufferLength != 0):
                magicOK = 1
    
    # If magicOK is equal to 1 then process the message
    if magicOK:
        # word array to convert 4 bytes to a 32 bit number
        word = [1, 2**8, 2**16, 2**24]
        
        # Initialize the pointer index
        idX = 0
        
        # Read the header
        magicNumber = byteBuffer[idX:idX+8]
        idX += 8
        version = format(np.matmul(byteBuffer[idX:idX+4],word),'x')
        idX += 4
        totalPacketLen = np.matmul(byteBuffer[idX:idX+4],word)
        idX += 4
        platform = format(np.matmul(byteBuffer[idX:idX+4],word),'x')
        idX += 4
        frameNumber = np.matmul(byteBuffer[idX:idX+4],word)
        idX += 4
        timeCpuCycles = np.matmul(byteBuffer[idX:idX+4],word)
        idX += 4
        numDetectedObj = np.matmul(byteBuffer[idX:idX+4],word)
        idX += 4
        numTLVs = np.matmul(byteBuffer[idX:idX+4],word)
        idX += 4
        subFrameNumber = np.matmul(byteBuffer[idX:idX+4],word)
        idX += 4

        # Read the TLV messages
        for tlvIdx in range(numTLVs):
            
            # word array to convert 4 bytes to a 32 bit number
            word = [1, 2**8, 2**16, 2**24]

            # Check the header of the TLV message
            tlv_type = np.matmul(byteBuffer[idX:idX+4],word)
            idX += 4
            tlv_length = np.matmul(byteBuffer[idX:idX+4],word)
            idX += 4

            # Read the data depending on the TLV message
            if tlv_type == MMWDEMO_UART_MSG_DETECTED_POINTS:

                # Initialize the arrays
                x = np.zeros(numDetectedObj,dtype=np.float32)
                y = np.zeros(numDetectedObj,dtype=np.float32)
                z = np.zeros(numDetectedObj,dtype=np.float32)
                velocity = np.zeros(numDetectedObj,dtype=np.float32)
                
                for objectNum in range(numDetectedObj):
                    
                    # Read the data for each object
                    x[objectNum] = byteBuffer[idX:idX + 4].view(dtype=np.float32)
                    idX += 4
                    y[objectNum] = byteBuffer[idX:idX + 4].view(dtype=np.float32)
                    idX += 4
                    z[objectNum] = byteBuffer[idX:idX + 4].view(dtype=np.float32)
                    idX += 4
                    velocity[objectNum] = byteBuffer[idX:idX + 4].view(dtype=np.float32)
                    idX += 4
                
                # Store the data in the detObj dictionary
                detObj = {"numObj": numDetectedObj, "x": x, "y": y, "z": z, "velocity":velocity}
                dataOK = 1
                
 
        # Remove already processed data
        if idX > 0 and byteBufferLength>idX:
            shiftSize = totalPacketLen
            
                
            byteBuffer[:byteBufferLength - shiftSize] = byteBuffer[shiftSize:byteBufferLength]
            byteBuffer[byteBufferLength - shiftSize:] = np.zeros(len(byteBuffer[byteBufferLength - shiftSize:]),dtype = 'uint8')
            byteBufferLength = byteBufferLength - shiftSize
            
            # Check that there are no errors with the buffer length
            if byteBufferLength < 0:
                byteBufferLength = 0         

    return dataOK, frameNumber, detObj

# ------------------------------------------------------------------

# BLE settings (must match iOS app BluetoothManager.swift and swRadar.ino)
BLE_DEVICE_NAME     = "SW-Radar"
BLE_SERVICE_UUID    = "A7E8F0B1-3C54-4D92-9F3E-0A1B2C3D4E5F"
BLE_CHAR_UUID       = "B8F9E1C2-4D65-5EA3-A04F-1B2C3D4E5F60"
BLE_NOTIFY_INTERVAL = 0.2   # seconds (200 ms, same as swRadar.ino)
METERS_TO_FEET      = 3.28084

# Distance & speed tracking (same logic as swRadar.ino)
totalDistanceFt  = 0.0
currentSpeedFtS  = 0.0
lastFrameTime    = 0.0
frameCount       = 0

# ------------------------------------------------------------------

# Function to process a parsed frame — find closest object, compute distance/speed
# (replaces the original update() which plotted a scatter chart)
def processFrame(detObj):
    global totalDistanceFt, currentSpeedFtS, lastFrameTime, frameCount

    frameCount += 1
    now = time.time()

    if detObj and detObj["numObj"] > 0 and len(detObj["x"]) > 0:
        # Compute range for each detected point
        ranges = np.sqrt(detObj["x"]**2 + detObj["y"]**2)

        # Find closest object (ignore points closer than 1 cm)
        valid = ranges > 0.01
        if np.any(valid):
            validRanges = np.where(valid, ranges, 9999.0)
            closestIdx = np.argmin(validRanges)
            closestVelocity = detObj["velocity"][closestIdx]

            speedMs = abs(float(closestVelocity))
            currentSpeedFtS = speedMs * METERS_TO_FEET

            if lastFrameTime > 0:
                dt = now - lastFrameTime
                totalDistanceFt += currentSpeedFtS * dt
        else:
            currentSpeedFtS = 0.0
    else:
        currentSpeedFtS = 0.0

    lastFrameTime = now

# ------------------------------------------------------------------

# Background thread: continuously reads and parses radar data
def radarReaderThread(Dataport, configParameters, stopEvent):
    while not stopEvent.is_set():
        try:
            dataOK, frameNumber, detObj = readAndParseData18xx(Dataport, configParameters)
            if dataOK:
                processFrame(detObj)
        except Exception as e:
            print(f"[Radar] Parse error: {e}")
        time.sleep(0.03)  # ~30 Hz, same as original (0.05 was ~20 Hz)

# ------------------------------------------------------------------

# Async main — sets up BLE server and runs the radar reader
async def main():
    global totalDistanceFt, currentSpeedFtS

    # 1. Configure radar serial ports and send config
    print("[Radar] Configuring serial ports...")
    CLIport, Dataport = serialConfig(configFileName)
    configParameters = parseConfigFile(configFileName)
    print(f"[Radar] Max range: {configParameters['maxRange']:.2f} m, "
          f"Max velocity: {configParameters['maxVelocity']:.2f} m/s")

    # 2. Start BLE GATT server (same UUIDs as swRadar.ino)
    print(f"[BLE] Starting server as '{BLE_DEVICE_NAME}'...")
    server = BlessServer(name=BLE_DEVICE_NAME)
    await server.add_new_service(BLE_SERVICE_UUID)

    char_flags = (
        GATTCharacteristicProperties.read |
        GATTCharacteristicProperties.notify
    )
    permissions = GATTAttributePermissions.readable
    await server.add_new_characteristic(
        BLE_SERVICE_UUID, BLE_CHAR_UUID,
        char_flags, None, permissions,
    )
    await server.start()
    print(f"[BLE] Advertising — Service: {BLE_SERVICE_UUID}")

    # 3. Start radar reader in a background thread
    stopEvent = threading.Event()
    reader = threading.Thread(
        target=radarReaderThread,
        args=(Dataport, configParameters, stopEvent),
        daemon=True,
    )
    reader.start()
    print("[Radar] Reader thread started — listening for data...")

    # 4. Main loop: update BLE characteristic and notify
    lastPrint = time.time()
    try:
        while True:
            # Build payload in same format as swRadar.ino: "distance,speed"
            payload = f"{totalDistanceFt:.2f},{currentSpeedFtS:.2f}"
            server.get_characteristic(BLE_CHAR_UUID).value = payload.encode("utf-8")
            server.update_value(BLE_SERVICE_UUID, BLE_CHAR_UUID)

            # Debug print every 1 second
            now = time.time()
            if now - lastPrint >= 1.0:
                lastPrint = now
                print(f"[Radar] Frames: {frameCount} | "
                      f"Distance: {totalDistanceFt:.2f} ft | "
                      f"Speed: {currentSpeedFtS:.2f} ft/s | "
                      f"BLE: {payload}")

            await asyncio.sleep(BLE_NOTIFY_INTERVAL)

    except KeyboardInterrupt:
        print("\n[Main] Shutting down...")

    finally:
        stopEvent.set()
        reader.join(timeout=2)
        await server.stop()
        CLIport.write(('sensorStop\n').encode())
        CLIport.close()
        Dataport.close()
        print("[Main] Clean shutdown complete")


# -------------------------    MAIN   -----------------------------------------  

if __name__ == "__main__":
    asyncio.run(main())
        
    





