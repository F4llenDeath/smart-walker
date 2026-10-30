# Smart Walker

A mobile/desktop app + embedded hardware project for the Spring 2026 UW Madison BME Design [Smart Walker](https://bmedesign.engr.wisc.edu/projects/s26/smart_walker) project. The Flutter app runs on iOS, Android, and macOS and connects via BLE to three sensor modules mounted on a walker — two ESP32 load cells (feet) and a Raspberry Pi + TI AWR1843 mmWave radar — to display live weight, distance, and walking speed data. Trials can be recorded per patient and exported as CSV.

## Features

### Live BLE Telemetry
- Live left, right, and total weight (lbs), distance (ft), and speed (ft/s).
- Automatic discovery and reconnection for the three BLE sensor modules.
- Compact sensor-readiness indicators and retry controls.

### Trial Recording
- Persistent bottom start/stop control and an elapsed timer (MM:SS.cc) while recording.
- Samples captured at a nominal 200 ms interval.
- Live walking-speed and left/right weight charts showing the latest 30 seconds;
  the saved trial retains the complete recording.
- Trials stop and preserve partial data when required telemetry is lost or the
  app enters the background. Recording is foreground-only.

### Patient Management
- Add and select patients, or record under the default Unassigned patient.
- Trials are attached to the patient selected when recording starts.
- Patient and trial deletion require confirmation.

### Trial History
- Patient-specific history with duration, distance, average speed, and average weight.
- Full-trial speed and weight-distribution charts.
- CSV file export through the platform share interface on iOS, Android, and macOS.
- Local JSON persistence, previous-save backups, and interrupted-recording recovery.

## Project Structure

```
Smart Walker/
├── app/                        # Flutter + Forui app (iOS / Android / macOS)
│   ├── lib/                    # UI, models, app services, BLE and persistence
│   ├── android/                # Android permissions and native host
│   ├── ios/                    # iOS permissions, signing, and native host
│   ├── macos/                  # Desktop window, Bluetooth entitlements, native host
│   ├── pubspec.yaml            # App version and dependencies
│   └── README.md               # Setup, architecture, and migration notes
└── controller/
    ├── swLeftFoot.ino          # ESP32 left foot load cell → BLE
    ├── swRightFoot.ino         # ESP32 right foot load cell → BLE
    ├── swRadar.py              # Raspberry Pi AWR1843 radar via USB → BLE
    └── AWR1843config.cfg       # TI mmWave radar configuration
```

## Acknowledgments
- Radar data parsing based on [AWR1843-Read-Data-Python](https://github.com/ibaiGorordo/AWR1843-Read-Data-Python-MMWAVE-SDK-3-) by Ibai Gorordo (MIT License)
