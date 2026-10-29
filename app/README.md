# Smart Walker — Flutter

The primary Smart Walker application for iOS and Android, built with Flutter,
Forui, and universal_ble. Sensor controllers are in `../controller/`. The retired
SwiftUI implementation is retained in Git history; this app does not depend on
its source files or Xcode project.

## Development setup

Use **Flutter 3.47.7**, recorded in `.flutter-version`. The application requires
Dart 3.13 and Flutter 3.47 or later; its current Forui API is not compatible with
older Flutter SDKs. Application dependency versions are committed in `pubspec.lock`.

From this application directory:

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

Replace `<device-id>` with an ID printed by `flutter devices`. For iOS, install a
compatible full Xcode, select its developer directory, and configure signing for
your team in the Runner project. For Android, install the Android SDK and a Java
17+ toolchain compatible with the generated Gradle/Android Gradle Plugin versions.
`flutter doctor -v` reports missing host prerequisites. The iOS deployment target
is **18.2**. Native plugins use Flutter's generated **Swift Package Manager**
integration; no manually maintained Podfile is required.

If `xcode-select -p` points to Command Line Tools, select the full Xcode
installation before compiling iOS. These commands change the host's active
developer directory and complete Xcode setup:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcrun --sdk iphonesimulator --show-sdk-path
```

Supplying `DEVELOPER_DIR` to a Flutter command alone is insufficient for the
current native-assets build hook, which runs with a filtered environment. If
`objective_c` reports `Bad state: No element` while resolving `sdkPath`, confirm
that the last command above finds an SDK.

Open this directory in VS Code for Flutter tooling. Launch configuration is in
`.vscode/launch.json`. Static checks, without running tests:

```sh
dart format --output=none --set-exit-if-changed lib
flutter analyze
```

For a development build that can launch independently from an iPhone's Home
Screen, install in Profile mode:

```sh
flutter run --profile -d <iphone-device-id>
```

Profile mode does not provide hot reload, and Apple signing/provisioning limits
still apply. Use the normal Debug mode for active development with hot reload.

## Implemented workflows

- Forui dashboard, phone/tablet layouts, and system light/dark theme.
- Live left/right/total weight (lbs), distance (ft), and speed (ft/s).
- Automatic three-sensor BLE discovery, subscriptions, and reconnection.
- Patient selection, creation, and confirmed patient/trial deletion.
- Nominal 200 ms trial samples and a monotonic elapsed display.
- Dashboard recording controls pinned above the bottom safe area; the clock is
  shown only while recording, with no recording-panel title or explanation.
- Live speed and left/right weight charts during recording, showing a rolling
  30-second window from the same samples that are saved in the trial.
- Newest-first patient history, summary statistics, speed and weight charts.
- CSV **file** sharing, including iPad popover positioning.
- Exclusive simulation mode, with simulated trials clearly labeled.
- Local JSON persistence, previous-save backup, and interrupted-trial recovery.

## App identities and existing iOS data

| Build | iOS bundle ID | Android application ID |
| --- | --- | --- |
| Debug / Profile | `com.xichengyang.Smart-Walker.dev` | `com.xichengyang.smart_walker.dev` |
| Release | `com.xichengyang.Smart-Walker` | `com.xichengyang.smart_walker` |

Debug/Profile installs can coexist with a Release installation or the retired
SwiftUI app. Their storage is separate: **they do not automatically read another
installation's data**. The Release iOS identity preserves the historical bundle
ID for an in-place update.
Do not uninstall the existing app before an update if its local data is needed.
An archive must use the appropriate signing team and provisioning configuration.

The app reads `smart_walker_data.json` in its application Documents directory.
For a development migration, copy a **backup** of the old JSON into that exact
directory for the Flutter installation using Xcode's downloaded app container
or a simulator container, then relaunch the app. Preserve the original copy.
There is no in-app file-import workflow or cross-installation migration. Android
starts with an independent local dataset. Removing the old source code from the
repository neither migrates nor backs up any data held on a device.

Compatibility is **historical Swift JSON → Flutter**, not round-trip compatibility:

- Top-level patient array and existing field names are preserved.
- UUID comparisons are case-insensitive through normalization.
- Whole-second and fractional ISO-8601 dates are accepted.
- The special Unassigned patient retains its fixed all-zero ID.
- Flutter trial fields include `source`, `completion`, and optional `interruptionReason`.
- Legacy trials have source `unknown`, not an assumed hardware source.
- New sample timestamps retain fractional precision.
- Mean speed/weight and last-minus-first distance summaries preserve the historical calculations.

## Recording and lifecycle policy

Start is enabled only when storage/recovery is resolved and all three streams are
ready. A valid packet must have arrived within **two seconds**. Samples capture
the latest values from each device; they are not synchronized hardware packets.
Late timer ticks do not produce fabricated catch-up samples.

The dashboard's recording control stays visible while scrolling and reserves its
own space rather than covering charts or history. Live charts appear below the
measurement rows only during a trial, then disappear when it stops. Each trial
starts with an empty live series. The chart display keeps a bounded recent-sample
buffer (plus an edge sample for line continuity), while persistence, summaries,
and CSV export retain the complete recording. Historical trial charts continue
to show the full trial. Live Y-axis limits expand when needed without shrinking
on every sample. Chart updates occur at the sampling cadence, independently of
the more frequent elapsed-time display updates.

Starting a trial captures the patient, source, and app-side distance baseline.
No reset or other command is sent to a controller. Patient/source changes and
destructive data actions are locked while a recording or save is pending.

A required sensor disconnect, stale stream, Bluetooth loss, decreasing radar
distance, or background transition stops recording and saves a partial trial.
Recording does **not** continue with the screen locked or app backgrounded. A
transient `inactive` state alone does not stop a trial. Returning to the foreground
refreshes hardware connections but never resumes an interrupted trial automatically.

`smart_walker_recording.json` is checkpointed every two seconds and at stop. On
restart, save or discard a recovered trial from the dashboard. Recovery is
idempotent by trial ID. Abrupt termination can lose samples since the last completed
checkpoint; the application does not claim to record while terminated.

Writes are serialized, flushed to a temporary file, and replaced atomically on
the target mobile platforms. `smart_walker_data.json.bak` retains the previous
save. Unreadable primary data is protected from silent replacement. The dashboard
can retry loading or explicitly restore a backup; restoration preserves the
previous unreadable file. Failed trial saves retain the trial and expose Retry.
Data is local JSON and is **not encrypted by this application**. Handle real
patient data and exported files according to your organization's requirements.

## BLE contract and implementation

The app preserves the existing controller protocol:

| Device name | UTF-8 notification | Units |
| --- | --- | --- |
| `SW-LeftFoot` | `32.50` | lbs |
| `SW-RightFoot` | `30.25` | lbs |
| `SW-Radar` | `12.50,1.25` | ft, ft/s |

```text
Service:        A7E8F0B1-3C54-4D92-9F3E-0A1B2C3D4E5F
Characteristic: B8F9E1C2-4D65-5EA3-A04F-1B2C3D4E5F60
```

`UniversalBleTransport` is the only layer that imports `universal_ble`. Device
roles use advertised names; packets are routed by device ID and characteristic.
Finite numeric parsing is required; malformed packets do not refresh freshness.
Android uses legacy advertising scans for the ESP32 modules. Connection setup is
serialized, stops scanning before connecting, and enables notifications only after
verifying the expected service and characteristic. Retry delays are 1, 2, 4, 8,
then 16 seconds. A subscription with no valid telemetry for 12 seconds is rebuilt.

Android declares Nearby Devices permissions on Android 12+ and legacy Bluetooth/
fine-location permissions through Android 11. Enable system location services on
older Android versions if required by that OS for scanning. Permission denial and
Bluetooth-off status are shown in the device panel; grant permission/enable
Bluetooth in Settings and retry. No advertising, background location, or
background-recording permissions are requested.

## Architecture

```text
lib/
  app/            App-scoped dependencies, Forui bootstrap, lifecycle
  application/    Device coordination, telemetry, simulation, recorder, patients
  core/           BLE constants/parsing and display formatters
  data/           BLE transport, JSON/draft repositories, CSV sharing
  domain/models/  Immutable patient/trial/sample models and compatibility codecs
  features/       Dashboard, patients, devices, trial detail/charts
  shared/widgets/ Forui cards, notices, dialogs, adaptive sheets
```

Widgets do not call BLE APIs or write storage files. Services own their timers and
subscriptions and are disposed with the app. Desktop/web targets and their native
setup are **not** included.

The `ios/` directory, including `Runner.xcodeproj`, `AppDelegate.swift`, and
`SceneDelegate.swift`, is the Flutter application's native iOS host and must be
retained. It is separate from the retired SwiftUI application. The `android/`
directory contains the equivalent Android host, permissions, and build settings.

## Distribution

Android Release builds are unsigned unless private `android/key.properties` is
provided. That file and keystores are ignored by Git. Its required entries are
`storeFile`, `storePassword`, `keyAlias`, and `keyPassword`; `storeFile` is resolved
relative to the Android project directory, or may be an absolute path. Do not use
the development debug signing key for distribution.

Builds and GitHub releases are managed manually; no GitHub Actions release
workflow is configured. Keep the Android signing key and its passwords backed up
outside the repository. An iOS IPA still needs appropriate Apple signing and
provisioning before it can be installed.

The generated native RunnerTests scaffold is not an application test suite.
Formatting and static analysis do not validate runtime behavior. Verify changes
on the target iOS/Android devices before replacing an installation containing
important data or distributing a build.
