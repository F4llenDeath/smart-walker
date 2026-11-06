# AGENTS.md — Smart Walker

## Project overview and scope

This guide applies to the entire Smart Walker repository. File paths are relative
to the repository root unless stated otherwise. Flutter and Dart application
commands must run from `app/`, not from the repository root. Application command
blocks below assume you start at the repository root and explicitly enter `app/`.
Host setup commands and runtime data paths are identified separately.

Smart Walker combines a Flutter application in `app/` with sensor controllers in
`controller/`. The application targets iOS, Android, macOS, and Windows x64 using
Forui, `fl_chart`, and `universal_ble`. It connects to two Seeed Studio XIAO ESP32-C5
load-cell modules and a Raspberry Pi + TI AWR1843 radar to record patient walking
trials. The retired SwiftUI application is retained in Git history; the Flutter
application does not depend on its old source or Xcode project. Linux and web
targets are not included.

Preserve these workflows:

- Live left/right/total weight in lbs, distance in ft, and speed in ft/s.
- Automatic three-sensor discovery, notification subscriptions, and reconnection.
- Patient selection, creation, confirmed deletion, and an Unassigned patient.
- Nominal 200 ms trial samples, a monotonic elapsed display, and live charts.
- Newest-first patient history, trial summaries, and full-trial charts.
- CSV file sharing on iOS/Android/macOS and native Save As on Windows.
- Exclusive, clearly labeled simulation mode; never mix simulated and BLE data.
- Local JSON storage, previous-save backups, and interrupted-trial recovery.

## Setup commands

Use **Flutter 3.47.7**, recorded in `app/.flutter-version`. The application requires
Dart **3.13** and Flutter **3.47+**; its Forui API is not compatible with older
Flutter SDKs. Keep dependency versions in `app/pubspec.lock`.

```sh
cd app
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <device-id>
```

Use a device ID reported by `flutter devices`. `flutter doctor -v` reports missing
host prerequisites. If intentionally changing dependencies, use `flutter pub get`
and include the resulting lockfile change; do not upgrade unrelated packages.

`universal_ble: 2.3.0` is the published pub.dev dependency. There is no vendored
copy, local fork, or Windows compatibility patch. Do not edit downloaded packages
in the Pub cache or introduce a fork without an explicit requirement.

The commands below document the development workflow; equivalent IDE actions are
also acceptable. No particular editor or terminal-only workflow is required.
No VS Code launch shortcuts or Windows packaging helper script are currently
maintained in this repository.

### iOS and Android prerequisites

- iOS requires full Xcode, the correct active developer directory, and the
  appropriate signing team/provisioning configuration. Deployment target: **18.2**.
- Native Apple plugins use Flutter-generated **Swift Package Manager** integration;
  no manually maintained Podfile is required.
- Android requires the Android SDK and a Java **17+** toolchain compatible with
  the generated Gradle/Android Gradle Plugin versions.

If `xcode-select -p` points to Command Line Tools, the following commands select
full Xcode and complete its setup. They change the host configuration and are
setup instructions, not commands to run automatically for unrelated tasks:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcrun --sdk iphonesimulator --show-sdk-path
```

Supplying `DEVELOPER_DIR` to a Flutter command alone is insufficient for the
current native-assets build hook, which runs with a filtered environment. If
`objective_c` reports `Bad state: No element` while resolving `sdkPath`, confirm
that the last command above finds an SDK.

For a development build that launches independently from an iPhone's Home Screen:

```sh
cd app
flutter run --profile -d <iphone-device-id>
```

Profile mode does not provide hot reload; Apple signing/provisioning limits still
apply. Use Debug mode for active development with hot reload.

### macOS commands and prerequisites

Use a Mac with full Xcode selected. Native deployment target: **macOS 12.0**.

```sh
cd app
flutter pub get --enforce-lockfile
flutter run -d macos
flutter build macos --release
```

Release output, relative to the repository root:
`app/build/macos/Build/Products/Release/Smart Walker.app`.

### Windows commands and prerequisites

Build on a **Windows development computer** using Flutter **3.47.7**, Visual
Studio's **Desktop development with C++** workload, Windows SDK **10.0.19041+**,
and CMake **3.21+**. The BLE plugin uses C++20 and the pinned
`Microsoft.Windows.CppWinRT` **2.0.220418.1** NuGet package.

The development machine needs access to the pinned Dart/NuGet packages or a
populated cache. This is separate from offline use on clinic computers. The
Windows host disables incidental JNI/JDK discovery in an Android-related
transitive plugin: the Windows application does not use or bundle Java.

```powershell
cd app
flutter pub get --enforce-lockfile
flutter run -d windows
flutter build windows --release --target-platform windows-x64
```

Release output, relative to the repository root:
`app\build\windows\x64\runner\Release`. The macOS Flutter SDK cannot cross-compile
this target. Windows runtime requirements are listed below.

## Project structure and architecture

```text
AGENTS.md                 Repository-wide development and deployment guidance
README.md                 Project overview
LICENSE.txt               Repository license
app/
  lib/
    app/                  App dependencies, Forui bootstrap, lifecycle
    application/          Devices, telemetry, simulation, recorder, patients
    core/                 BLE constants/parsing and display formatters
    data/                 BLE, native services, JSON/draft storage, CSV export
    domain/models/        Immutable models and compatibility codecs
    features/             Dashboard, desktop workspace, patients, devices, trials
    shared/widgets/       Forui cards, notices, dialogs, adaptive sheets
  android/                Android host, permissions, and build settings
  ios/                    Flutter iOS host and signing configuration
  macos/                  Desktop host, Bluetooth entitlements, Swift packages
  windows/                x64 host, native services, CMake build configuration
  pubspec.yaml            Application version and dependencies
  pubspec.lock            Pinned dependency resolution
controller/
  swLeftFoot.ino          ESP32 left load-cell BLE peripheral
  swRightFoot.ino         ESP32 right load-cell BLE peripheral
  swRadar.py              Raspberry Pi radar serial processing and BLE peripheral
  AWR1843config.cfg       TI AWR1843 radar configuration
```

- Widgets must not call BLE APIs or write storage files directly. Keep device,
  persistence, and export operations in the corresponding service layers.
- Services own their timers/subscriptions and dispose them with the application.
- macOS and Windows share the desktop workspace and content-pane navigator;
  retain shared recording, JSON, telemetry, and CSV-generation services.
- Keep `app/ios/Runner.xcodeproj`, `app/ios/Runner/AppDelegate.swift`, and
  `app/ios/Runner/SceneDelegate.swift`: they are the Flutter host, not remnants of
  the retired SwiftUI application.
- `app/windows/runner/windows_app_services.*` owns the asynchronous STA Save As
  dialog, Local AppData lookup, instance lock, and background file replacement.
  Return results on Flutter's platform thread and stop workers before destroying
  the engine.
- `app/lib/data/platform/windows_native_services.dart` is the narrow Dart/native
  boundary; `app/lib/data/storage/app_storage_directory.dart` selects the data root.

### Sensor controller guidance

- Both foot modules now use **Seeed Studio XIAO ESP32-C5** boards, replacing the
  previous XIAO ESP32-S3 boards. Each board is powered by its own **3.7 V nominal,
  2200 mAh lithium-ion cylindrical battery**
  ([Adafruit product 1781](https://www.adafruit.com/product/1781)). Only the
  Raspberry Pi and TI AWR1843 radar are powered by a separate power bank.
- The XIAO ESP32-C5 supports onboard battery-voltage measurement; see the
  [official Seeed guide](https://wiki.seeedstudio.com/xiao_esp32c5_getting_started/).
  The foot firmware enables GPIO26 and averages 16 calibrated GPIO6 millivolt
  readings, multiplied by two for the divider. It samples every second, smooths
  valid readings, and exposes optional battery telemetry separately from weight.
  The shared Flutter connection panel shows High/Medium/Low battery icons, not
  voltage or percentage; these are approximate voltage bands, not a fuel gauge
  or confirmation of charging/full charge. The radar/Pi power bank is not monitored.
- `controller/swLeftFoot.ino` and `controller/swRightFoot.ino` use the existing
  ESP32 Arduino BLE libraries and HX711 load-cell interface. Preserve the device
  names, UUIDs, notification format, and nominal 200 ms send interval shared with
  the Flutter application.
- Keep hardware pin assignments, calibration factors, and taring behavior intact
  unless a task explicitly requires a hardware change. Preserve reconnection and
  advertising behavior when changing peripheral code.
- `controller/swRadar.py` uses `pyserial`, NumPy, and `bless`; it processes radar
  serial data on the Raspberry Pi and exposes the existing BLE telemetry contract.
  Do not move radar processing or USB serial access into a desktop app port.
- The radar script reads `AWR1843config.cfg` relative to its working directory;
  run it from `controller/` on the configured hardware. Serial paths and baud
  rates are hardware-specific. Starting it sends configuration commands to the
  radar, so do not run it automatically as a documentation/static check.
- Arduino/Python changes follow their existing local conventions, not Dart
  formatting rules. No controller toolchain or dependency versions are pinned
  here; do not invent build commands or silently change hardware dependencies.
- Preserve upstream radar attribution and license notices. Changes to the shared
  protocol must be coordinated between the app and all affected controllers.

## Code style and change guidelines

- For `app/`, follow existing Dart naming, import grouping, formatting, and
  feature/service boundaries. `app/analysis_options.yaml` includes
  `package:flutter_lints/flutter.yaml`.
- Use the existing libraries and Forui components; do not introduce a parallel
  Windows UI or an unrelated state-management framework.
- Keep desktop-specific behavior gated to desktop platforms. Mobile retains
  touch styling, patient sheets, history navigation, and the dashboard layout.
- Preserve the BLE contract, units, CSV schema, app identities, and historical
  data compatibility unless the task explicitly requires a change.
- Keep native host source under version control, but do not manually edit
  generated plugin registration/build files or commit ephemeral build output.
- Never commit signing secrets, Android keystores, or private key properties.
- Keep scope focused: no cloud synchronization, automatic data import, or
  unrequested platform/dependency upgrades.

## Static checks and testing instructions

These commands check the Flutter application only, not the controller firmware or
Python program. From the repository root, enter `app/` before running them:

```sh
cd app
dart format --output=none --set-exit-if-changed lib
flutter analyze
```

The generated native RunnerTests scaffolds are not an application test suite.
There is no configured GitHub Actions release workflow. Do not add test suites,
CI, or a runtime-validation project unless explicitly requested. Documentation-only
changes do not require building or running the application.

Formatting, static analysis, and compilation are not evidence of hardware/runtime
compatibility. Report exactly what was run and what remains unverified. Windows
native code has not been compiled or run during the port's development on macOS;
do not describe the Windows/LTSC targets as demonstrated or certified. Three-device
BLE and platform export behavior likewise must not be claimed verified from
compilation alone. Protect existing patient data before replacing an installation.

## Desktop workspace and interface behavior

Both desktops use Forui desktop light/dark themes. macOS starts with **1180 x 820**
content and a **900 x 640** minimum. Windows uses the same preferred logical sizes,
clamped to the monitor's available work area, with ordinary Windows controls.

- **Sidebar:** patient dropdown, add/delete actions, and newest-first trial list.
  Select by patient ID so duplicate names remain distinct. Keep editing/selection
  locks consistent with mobile.
- **Live pane:** shared measurements, live charts, simulation notice, storage
  errors, and recovery controls. Do not duplicate patient selection/history here.
- **Connection button:** opens an anchored, opaque popover with sensor readiness,
  Retry, and simulation. Outside click or Escape dismisses it without navigation.
- **Trial details:** open in the right pane. Back returns to live content; another
  trial replaces the current detail instead of stacking pages. Changing patient
  or deleting the selected trial returns to live content.
- **Recording controls:** stay pinned in the right pane, including while viewing
  a past trial. Starting returns to live content. Browsing history does not stop
  an active trial; a save failure returns to live content with Retry visible.

On macOS, retain the sandbox, Bluetooth usage descriptions, and
`com.apple.security.device.bluetooth` in development and Release. If denied,
enable Smart Walker in **System Settings > Privacy & Security > Bluetooth**, then
retry. macOS sharing remains unchanged; Windows uses native Save As.

## Recording and lifecycle invariants

- Start only when storage/recovery is resolved and all three streams are ready.
  Each stream must have a valid packet within **two seconds**.
- Sample the latest device values every nominal **200 ms**. Device packets are
  not hardware-synchronized; late timers must not fabricate catch-up samples.
- Capture patient, source, and an application-side distance baseline at start.
  Do not send reset or other commands to controllers. Lock patient/source changes
  and destructive actions while a recording or save is pending.
- Keep dashboard controls visible while scrolling, reserving their own space
  rather than covering charts/history. Display the **MM:SS.cc** clock only during
  recording, with no recording-panel title/explanation.
- Live speed and left/right weight charts appear below measurements only during
  a trial. Start each trial with an empty live series. Keep a bounded **30-second**
  recent-sample buffer plus an edge sample for continuity; persistence, summaries,
  CSV, and historical charts retain the complete recording.
- Live Y-axis limits expand when needed without shrinking on every sample.
  Update charts at the sampling cadence, independently of the faster elapsed clock.
- Required sensor disconnect, stale telemetry, Bluetooth loss, decreasing radar
  distance, or backgrounding stops recording and saves a partial trial. Never
  continue with a missing required stream or fabricate replacement measurements.
- A transient `inactive` state or ordinary focus change alone does not stop a
  trial, including focus lost to Windows Save As. Screen lock/backgrounding does;
  desktop minimize/hide stops and preserves a partial trial.
- Returning to the foreground refreshes connections but never resumes an
  interrupted trial automatically.
- Normal macOS Quit/close and Windows X/Alt+F4 wait for recording/patient saves.
  Failed trial saves or a **20-second** save-wait timeout cancel exit, leaving
  Retry available. Repeated close requests must not overlap exit/save operations.
- Checkpoint `smart_walker_recording.json` every **two seconds** and at stop.
  Offer save/discard recovery on restart; recovery is idempotent by trial ID.
- Force quit, abrupt shutdown, sleep, power loss, and termination are not
  continuous-recording guarantees. Samples after the last completed checkpoint
  can be lost; do not claim to record while terminated.

## BLE contract and troubleshooting

Preserve the existing controller protocol:

| Advertised device name | UTF-8 notification example | Units |
| --- | --- | --- |
| `SW-LeftFoot` | `32.50` | lbs |
| `SW-RightFoot` | `30.25` | lbs |
| `SW-Radar` | `12.50,1.25` | ft, ft/s |

```text
Service:        A7E8F0B1-3C54-4D92-9F3E-0A1B2C3D4E5F
Characteristic: B8F9E1C2-4D65-5EA3-A04F-1B2C3D4E5F60
```

### Optional foot battery status

Both feet add Read + Notify characteristic
`C9A0F2D3-5E76-4FB4-B150-2C3D4E5F6071` under the existing service. Advertising,
device names, and weight/radar packets remain unchanged. Battery payload is four
bytes: protocol version `1`, validity `0`/`1`, then unsigned 16-bit little-endian
millivolts (zero when invalid). Values outside **2500–4500 mV** are rejected;
these are plausibility bounds, not recommended operating/cutoff voltages.

- Firmware updates the readable value every **one second**, notifies every
  **ten seconds** even when unchanged, and also notifies on validity transitions.
  No new blocking delays are added. Serial output retains voltage for diagnostics.
- The app establishes required telemetry first, then attaches battery listeners,
  subscribes and reads with bounded optional operations. Missing support on older
  firmware, invalid packets, or battery-operation failures do not fail the sensor
  connection or change recording readiness. Battery packets never refresh weight
  freshness. Battery readings expire after **45 seconds** without a valid update.
- Icons are High at **3900 mV or above**, Low at **3600 mV or below**, otherwise
  Medium on first receipt. Hysteresis retains High down to **3800 mV** and Low
  until **3700 mV**. These thresholds are **provisional and not hardware-validated**;
  compare both modules against a multimeter and characterize normal loaded
  discharge before relying on the Low warning. No remaining-runtime claim is made.
- Missing, invalid, stale, or disconnected readings show Unknown, never a
  fabricated charge level. Tooltips/accessibility describe the status. Simulation
  hides real battery indicators. Low is nonblocking and never stops a trial by
  itself. No battery values are added to patient JSON, trial samples, or CSV.
- Compile each `.ino` as a **separate Arduino sketch**, with a matching sketch
  directory name, using the XIAO ESP32-C5 board and the installed HX711 library.
  Do not compile both `.ino` files together from `controller/` or change load-cell
  pin assignments/calibration as part of battery validation.

### Required telemetry and troubleshooting

`UniversalBleTransport` is the only application layer importing `universal_ble`.
Roles use advertised names; route packets by device ID and characteristic. Require
finite numeric values: malformed packets must not refresh freshness. Serialize
connection setup, stop scanning before connecting, and enable notifications only
after verifying the service and characteristic. Retry after **1, 2, 4, 8, then 16
seconds**. Rebuild a subscription after **12 seconds** without valid telemetry.

Android uses legacy advertising scans for the ESP32 modules. It declares Nearby
Devices permissions on Android 12+ and legacy Bluetooth/fine-location permissions
through Android 11. Older Android may require system location services for scans.
Show permission denial/Bluetooth-off state and offer Retry. Do not add advertising,
background-location, or background-recording permissions.

Windows retains upstream advertisement/scan-response behavior. Published plugin
2.3.0 calls `IsConnectable`, introduced in build **19041**; no local older-Windows
API fallback or discovery-merging patch is present.

Troubleshooting guidance:

- **No adapter:** enable/install a BLE adapter and an appropriate Windows driver.
- **Bluetooth off:** enable it in system Settings and retry.
- **Access blocked:** ask clinic IT about Bluetooth/device restrictions; the app
  does not install drivers or bypass policy.
- **Missing sensors:** check power/range and whether another phone/computer is
  connected. Retry rebuilds connections.
- **Stale/disconnected mid-trial:** preserve the partial trial, never invent data.

## Storage, identities, migration, and security

### Shared persistence rules

- Keep `smart_walker_data.json` and previous-save `smart_walker_data.json.bak`.
  Serialize writes, flush staged temporary files, and replace the destination
  without deleting the original first. Mobile replacement is atomic; preserve
  the existing Windows native replace-file path.
- Protect unreadable primary data from silent overwrite. Allow explicit reload
  or backup restoration, preserving the unreadable file when restoring.
- Retain failed trial saves in memory/recovery and expose Retry.
- Patient JSON, recovery files, and exported CSV are **not encrypted by this
  application**. Follow organizational access-control, retention, backup, and
  export requirements. A previous-save backup is not a separate backup strategy.
- There is no cloud sync, clinic-wide shared database, or automatic import/schema
  migration workflow. Do not imply that deleting source files migrates device data.

### Mobile/macOS identities and historical iOS data

| Build | iOS bundle ID | Android application ID |
| --- | --- | --- |
| Debug / Profile | `com.xichengyang.Smart-Walker.dev` | `com.xichengyang.smart_walker.dev` |
| Release | `com.xichengyang.Smart-Walker` | `com.xichengyang.smart_walker` |

macOS uses `com.xichengyang.Smart-Walker.mac` in development and Release, with its
own sandbox dataset separate from iOS/Android. Mac development/Release builds
share the same Mac identity/data. Back up important trials before replacing builds.

Mobile Debug/Profile can coexist with Release/the retired SwiftUI app, but each
installation has independent storage. Release iOS preserves the historical bundle
ID for in-place updates. **Do not uninstall an existing app before an update if
its local data is needed.** Archives need the appropriate team/provisioning.

iOS/Android/macOS read JSON in their application Documents directory. For a
development iOS migration, copy a **backup** of the old JSON into that exact
Flutter installation's directory using Xcode's downloaded app container or the
simulator container, then relaunch. Preserve the original. There is no in-app
file import or cross-installation migration; Android starts independently.

Compatibility is **historical Swift JSON -> Flutter**, not round-trip:

- Preserve the top-level patient array and existing field names.
- Normalize UUIDs for case-insensitive comparisons; keep Unassigned's fixed
  all-zero ID.
- Accept whole-second and fractional ISO-8601 dates; retain fractional precision
  for new sample timestamps.
- Preserve trial fields `source`, `completion`, and optional `interruptionReason`.
  Legacy source is `unknown`, not assumed hardware.
- Preserve mean speed/weight and last-minus-first distance summary calculations.

### Windows per-user data and instance protection

Resolve the Windows Local AppData known folder and append `Smart Walker`, normally:

```text
%LOCALAPPDATA%\Smart Walker\
  smart_walker_data.json
  smart_walker_data.json.bak
  smart_walker_recording.json       (while recording/recovery is pending)
  .instance.lock
```

The host holds an exclusive OS file handle **before starting Dart**, preventing
two copies from writing the same dataset. A remaining hidden lock file alone does
not mean the app is running; the open handle enforces exclusivity. Do not delete
or modify data files while the app is open.

Debug/Profile/Release and extracted copies share the same data root for a Windows
user. Different Windows accounts have independent datasets. Moving/removing the
installation folder does not move/remove Local AppData. Stage writes beside their
destination so replacement stays on the same volume.

## CSV export behavior

Keep CSV columns, units, precision, timestamp representation, and the suggested
trial filename unchanged.

- iOS/Android/macOS share a CSV **file** through the platform interface; retain
  iPad popover positioning and existing export-file lifetime handling.
- Windows **Export CSV** opens native Save As with a CSV filter/default extension,
  suggested trial filename, and overwrite confirmation. Cancellation is normal,
  not a failure. Write/flush a staged file before replacing an existing CSV.
  Show access errors and the destination path after a successful save. No receiving
  share application is required.

## Windows compatibility and clinic deployment

| Intended x64 target | Version | Base build |
| --- | --- | --- |
| Windows 10 Enterprise / IoT Enterprise LTSC 2021 | 21H2 | 19044 |
| Windows 11 Enterprise / IoT Enterprise LTSC 2024 | 24H2 | 26100 |

These are implementation targets, not certified/demonstrated compatibility.
Minimum OS build: **19041**, checked by build number rather than edition name;
equivalent non-LTSC Windows is not intentionally rejected. LTSC 2019, Windows 7/8,
LTSB 2015/2016, 32-bit Windows, and ARM builds are out of scope. An x64 executable
cannot launch on 32-bit Windows.

Clinic computers need a working BLE adapter/driver and policy permission to run
the app and use Bluetooth. They do not need Flutter, Dart, Visual Studio, NuGet,
Java, Python, Microsoft Store, a browser, cloud access, or a Smart Walker service
account. The Windows OS user still owns its local dataset. The radar continues
running on its Raspberry Pi; Windows does not access its USB serial port directly.

### Offline packaging and installation

There is no maintained packaging script or installer. After building on Windows:

1. Copy the **complete** Release output, including `smart_walker.exe`, companion
   DLLs/native assets, and the `data` directory, into a distribution folder.
2. Include matching application-local **x64 Visual C++ runtime DLLs** from the
   build toolchain's redistributable CRT directory. Include `vcruntime140.dll`,
   `vcruntime140_1.dll`, `msvcp140.dll`, and any other required CRT DLLs; follow
   redistribution terms. Do not copy Debug runtime libraries or x86 DLLs.
3. Include the root `AGENTS.md` as deployment/build documentation and the root
   `LICENSE.txt`. Keep Flutter's generated dependency license-notice assets,
   including the published BLE plugin's license.
4. Manually create a versioned `Smart-Walker-<version>-windows-x64.zip` outside
   tracked source directories (for example under `app/build/distributions`). This
   packages an existing build; it does not compile, install tools, or run tests.

Runtime-directory example only; use the matching toolchain's actual directory:

```text
C:\BuildTools\VC\Redist\MSVC\14.44.35208\x64\Microsoft.VC143.CRT
```

For a clinic installation:

1. Extract the **entire ZIP** into a local directory allowed by IT. Do not run
   from inside the ZIP or copy only the executable.
2. Keep DLLs and `data` alongside `smart_walker.exe`.
3. Run as the normal Windows user; the app does not request administrator access.
   IT may need to allow unsigned executables.
4. Enable Bluetooth, power the sensors, and use the connection panel for readiness,
   Retry, or exclusive/labeled simulation.

The application-local runtime enables deployment without a runtime download;
drivers/OS prerequisites remain IT's responsibility. ZIP distribution is not an
installer and this repository does not configure code signing or automatic updates.

To upgrade, close the app, back up its data directory, and replace the **entire**
application bundle. Do not mix DLLs from different builds. Removing the extracted
application leaves the separate Local AppData dataset intact.

## Signing and release instructions

- Builds/GitHub releases are managed manually; no release CI is configured.
- Android Release is unsigned unless private `app/android/key.properties` is supplied.
  Required fields: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.
  `storeFile` resolves relative to the Android project directory or can be absolute.
  The properties file/keystores are Git-ignored; back up secrets outside the repo.
  Never use the development debug key for distribution.
- iOS IPA distribution requires appropriate Apple signing/provisioning. Preserve
  the Release identity when updating an installation with historical data.
- Local macOS Release output is not a notarized public distribution. Developer ID
  signing, notarization, and `.pkg`/`.dmg` packaging are separate, unconfigured steps.
- Windows distributions require the full bundle/runtime files described above;
  Store submission, installers, signing, and auto-updating are not configured.