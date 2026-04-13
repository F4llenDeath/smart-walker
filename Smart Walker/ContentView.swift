//
//  ContentView.swift
//  Smart Walker
//
//  Main dashboard
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @EnvironmentObject var dataStore: DataStore
    
    // Popover state
    @State private var showPatientPicker = false
    @State private var showBLEPopover = false
    
    // Recording timer
    @State private var recordingTimer: Timer? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    patientSelectorRow
                    
                    telemetrySection
                    
                    trialToggleButton
                    
                    trialHistorySection
                }
                .padding()
            }
            .navigationTitle("Smart Walker")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    bleStatusButton
                }
            }
            .sheet(isPresented: $showPatientPicker) {
                PatientPickerSheet()
            }
        }
    }
    
    // patient selector row
    private var patientSelectorRow: some View {
        Button(action: { showPatientPicker = true }) {
            HStack {
                Image(systemName: dataStore.selectedPatient.isUnassigned ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                Text(dataStore.selectedPatient.isUnassigned ? "Unassigned Session" : dataStore.selectedPatient.name)
                    .font(.title3)
                    .fontWeight(.medium)
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // ble status
    private var bleStatusButton: some View {
        Button(action: { showBLEPopover = true }) {
            Image(systemName: bleIconName)
                .font(.title3)
                .foregroundColor(bleIconColor)
        }
        .popover(isPresented: $showBLEPopover) {
            blePopoverContent
        }
    }
    
    private var bleIconName: String {
        if !bluetooth.isBluetoothOn {
            return "xmark.circle.fill"
        }
        return "antenna.radiowaves.left.and.right"
    }
    
    private var bleIconColor: Color {
        if !bluetooth.isBluetoothOn { return .red }
        switch bluetooth.connectedCount {
        case 3: return .green
        case 1, 2: return .yellow
        default: return .red
        }
    }
    
    private var blePopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BLE Status (\(bluetooth.connectedCount)/3)")
                .font(.headline)
            
            Divider()
            
            bleDeviceRow(name: "Left Foot", connected: bluetooth.leftFootConnected)
            bleDeviceRow(name: "Right Foot", connected: bluetooth.rightFootConnected)
            bleDeviceRow(name: "Radar", connected: bluetooth.radarConnected)
            
            if bluetooth.isScanning {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            
            Divider()
            
            Toggle(isOn: Binding(
                get: { bluetooth.isSimulating },
                set: { _ in bluetooth.toggleSimulation() }
            )) {
                Label("Simulate Data", systemImage: "dice")
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(minWidth: 200)
        .presentationCompactAdaptation(.popover)
    }
    
    private func bleDeviceRow(name: String, connected: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connected ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
            Text(name)
                .font(.subheadline)
            Spacer()
            Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(connected ? .green : .secondary)
                .font(.subheadline)
        }
    }
    
    // live telementry
    private var telemetrySection: some View {
        VStack(spacing: 8) {
            telemetryRow(label: "Weight L (lbs)", value: bluetooth.weightLeft)
            telemetryRow(label: "Weight R (lbs)", value: bluetooth.weightRight)
            telemetryRow(label: "Total (lbs)", value: bluetooth.weightTotal)
            
            Divider()
            
            telemetryRow(label: "Distance (ft)", value: bluetooth.distanceFt)
            telemetryRow(label: "Speed (ft/s)", value: bluetooth.speedFtS)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func telemetryRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.2f", value))
                .font(.title3)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
    
    // trial toggle button
    
    private var trialToggleButton: some View {
        Button(action: toggleTrial) {
            HStack {
                Image(systemName: dataStore.isRecording ? "stop.fill" : "play.fill")
                Text(dataStore.isRecording ? "Stop Trial" : "Start Trial")
                    .fontWeight(.semibold)
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(dataStore.isRecording ? Color.red : Color.green)
            .cornerRadius(12)
        }
    }
    
    private func toggleTrial() {
        if dataStore.isRecording {
            // Stop recording
            recordingTimer?.invalidate()
            recordingTimer = nil
            dataStore.stopTrial()
        } else {
            // Start recording
            dataStore.startTrial()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                dataStore.addDataPoint(
                    weightLeft: bluetooth.weightLeft,
                    weightRight: bluetooth.weightRight,
                    distanceFt: bluetooth.distanceFt,
                    speedFtS: bluetooth.speedFtS
                )
            }
        }
    }
    
    // trials list
    
    private var trialHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Past Trials")
                .font(.headline)
                .padding(.top, 4)
            
            if dataStore.selectedPatientTrials.isEmpty {
                Text("No trials recorded yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(dataStore.selectedPatientTrials) { trial in
                    NavigationLink(destination: TrialDetailView(trial: trial)) {
                        trialRow(trial)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func trialRow(_ trial: Trial) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(trial.startDate, style: .date)
                    .font(.subheadline)
                    .fontWeight(.medium)
                + Text("  ")
                + Text(trial.startDate, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("\(trial.durationFormatted) • \(String(format: "%.1f", trial.totalDistance)) ft")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

#Preview {
    ContentView()
        .environmentObject(BluetoothManager())
        .environmentObject(DataStore())
}
