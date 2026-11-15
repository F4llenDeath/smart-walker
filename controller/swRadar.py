# Radar parsing based on AWR1843-Read-Data-Python by Ibai Gorordo (MIT License).
# Original: https://github.com/ibaiGorordo/AWR1843-Read-Data-Python-MMWAVE-SDK-3-
# Modified for Smart Walker: UART-to-BLE relay; measurement logic is in Flutter.

import serial
import time
import secrets
import asyncio
import threading
import math
import struct
from bless import BlessServer, GATTCharacteristicProperties, GATTAttributePermissions

# UART parsing and BLE framing only: target selection and movement calculations
# remain in the Flutter app. This script and AWR1843config.cfg are the Pi files.
MAGIC = b'\x02\x01\x04\x03\x06\x05\x08\x07'
MAX_PACKET_BYTES = 32768
MAX_BLE_POINTS = 128


class RadarUartParser:
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, incoming):
        self.buffer.extend(incoming)
        # Bounded resynchronization; preserve a possible partial magic word.
        if len(self.buffer) > 2 * MAX_PACKET_BYTES:
            del self.buffer[:-MAX_PACKET_BYTES]
        frames = []
        while True:
            start = self.buffer.find(MAGIC)
            if start < 0:
                if len(self.buffer) > 7:
                    del self.buffer[:-7]
                break
            if start:
                del self.buffer[:start]
            if len(self.buffer) < 40:
                break
            header = struct.unpack_from('<8I', self.buffer, 8)
            _, length, _, number, cycles, count, tlvs, subframe = header
            if length < 40 or length > MAX_PACKET_BYTES or tlvs > (length - 40) // 8:
                del self.buffer[0]
                continue
            if len(self.buffer) < length:
                break
            packet = bytes(self.buffer[:length])
            del self.buffer[:length]
            try:
                offset = 40
                points = None
                for _ in range(tlvs):
                    if offset + 8 > length:
                        raise ValueError('Truncated TLV header')
                    kind, size = struct.unpack_from('<II', packet, offset)
                    offset += 8
                    # mmWave SDK 3.x TLV length describes the payload only.
                    end = offset + size
                    if end > length:
                        raise ValueError('Truncated TLV payload')
                    if kind == 1:
                        if points is not None or size != count * 16:
                            raise ValueError('Invalid detected-point TLV length')
                        points = list(struct.iter_unpack('<ffff', packet[offset:end]))
                        if any(not math.isfinite(v) or abs(v) > 1000
                               for point in points for v in point):
                            raise ValueError('Invalid detected-point value')
                    offset = end  # Skip side-info/other TLVs and preserve alignment.
                if subframe != 0 or count > 0 and points is None:
                    raise ValueError('Unsupported subframe or missing detections')
                frames.append((number, cycles, points or []))
            except (ValueError, struct.error):
                # Consume the malformed packet, but never publish it as fresh data.
                continue
        return frames


def encode_ble_frame(session, number, cycles, acquired_ms, points):
    # Overflow is explicit: never silently choose/truncate points on the Pi.
    overflow = len(points) > MAX_BLE_POINTS
    forwarded = [] if overflow else points
    return struct.pack('<IIIQHH', session, number, cycles, acquired_ms,
                       len(forwarded), int(overflow)) + b''.join(
        struct.pack('<ffff', *point) for point in forwarded)


def ble_chunks(body, sequence):
    for offset in range(0, len(body), 12):
        yield struct.pack('<2sBBHH', b'SW', 2, offset // 12,
                          sequence & 0xffff, len(body)) + body[offset:offset + 12]


# Change the configuration file name
configFileName = 'AWR1843config.cfg'

CLIport = {}
Dataport = {}


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
# UART/BLE bridge. Target selection, speed geometry and trial range tracking
# belong to the Flutter app, not the Pi. Both ends require protocol v2.
BLE_DEVICE_NAME = "SW-Radar"
BLE_SERVICE_UUID = "A7E8F0B1-3C54-4D92-9F3E-0A1B2C3D4E5F"
BLE_CHAR_UUID = "B8F9E1C2-4D65-5EA3-A04F-1B2C3D4E5F60"
BLE_NOTIFY_INTERVAL = 0.2
latestFrame = None
frameLock = threading.Lock()
frameCount = 0


def radarReaderThread(Dataport, stopEvent):
    global latestFrame, frameCount
    parser = RadarUartParser()
    previousNumber = None
    session = secrets.randbits(32)
    while not stopEvent.is_set():
        try:
            incoming = Dataport.read(min(Dataport.in_waiting, MAX_PACKET_BYTES))
            frames = parser.feed(incoming)
            if frames:
                number, cycles, points = frames[-1]
                advance = None if previousNumber is None else (number - previousNumber) & 0xffffffff
                if advance != 0:
                    if advance is not None and advance >= 0x80000000:
                        session = secrets.randbits(32)
                    previousNumber = number
                    acquired_ms = time.monotonic_ns() // 1000000
                    with frameLock:
                        latestFrame = (session, number, cycles, acquired_ms, points)
                        frameCount += len(frames)
        except Exception as e:
            print(f"[Radar] Parse error: {e}")
        time.sleep(0.03)  # Preserve the pre-v2 reader cadence.


# Async main — same server lifecycle as before detection-frame v2.
async def main():
    # 1. Configure radar serial ports and send config.
    print("[Radar] Configuring serial ports...")
    CLIport, Dataport = serialConfig(configFileName)

    # 2. Start BLE GATT server with the original name/UUIDs/properties.
    print(f"[BLE] Starting server as '{BLE_DEVICE_NAME}'...")
    server = BlessServer(name=BLE_DEVICE_NAME)
    await server.add_new_service(BLE_SERVICE_UUID)
    char_flags = (GATTCharacteristicProperties.read |
                  GATTCharacteristicProperties.notify)
    permissions = GATTAttributePermissions.readable
    await server.add_new_characteristic(
        BLE_SERVICE_UUID, BLE_CHAR_UUID, char_flags, None, permissions,
    )
    await server.start()
    print(f"[BLE] Advertising — Service: {BLE_SERVICE_UUID}")

    # 3. Original background-reader structure; processing now stays in the app.
    stopEvent = threading.Event()
    reader = threading.Thread(
        target=radarReaderThread, args=(Dataport, stopEvent), daemon=True,
    )
    reader.start()
    print("[Radar] Reader thread started — listening for data...")

    # 4. Publish periodically as before. Repeats preserve acquisition identity:
    # they keep the relay active, never turn old readings into fresh measurements.
    sequence = 0
    lastPrint = time.time()
    try:
        while True:
            with frameLock:
                frame = latestFrame
                count = frameCount
            if frame is not None:
                session, number, cycles, acquired_ms, points = frame
            # Do not introduce a long-dead UART value as a new client's baseline.
            if frame is not None and time.monotonic_ns() // 1000000 - acquired_ms <= 500:
                body = encode_ble_frame(session, number, cycles, acquired_ms, points)
                # Advance even after a failed transmission so partial frames cannot mix.
                sequence = (sequence + 1) & 0xffff
                try:
                    for chunk in ble_chunks(body, sequence):
                        server.get_characteristic(BLE_CHAR_UUID).value = bytearray(chunk)
                        updated = server.update_value(BLE_SERVICE_UUID, BLE_CHAR_UUID)
                        if updated is False:
                            raise RuntimeError("BLE backend rejected characteristic update")
                        # Framing is the necessary difference from the old single text
                        # notification. This yields to the backend, not a delivery ACK.
                        await asyncio.sleep(0.002)
                except Exception as e:
                    # A send failure must not stop the radar or unregister the server.
                    print(f"[BLE] Publish failed; retrying next cycle: {e}")

            now = time.time()
            if now - lastPrint >= 1.0:
                lastPrint = now
                if frame is None:
                    print(f"[Radar] Frames: {count} | Waiting for UART data | BLE v2")
                else:
                    age_ms = time.monotonic_ns() // 1000000 - acquired_ms
                    print(f"[Radar] Frames: {count} | Frame: {number} | "
                          f"Detections: {len(points)} | Age: {age_ms} ms | BLE v2")
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


if __name__ == "__main__":
    asyncio.run(main())
