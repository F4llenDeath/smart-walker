//
//  DataStore.swift
//  Smart Walker
//
//  Manages all patient and trial data. 
//

import Foundation

class DataStore: ObservableObject {
    
    // Published State 
    @Published var patients: [Patient] = []
    @Published var selectedPatientID: UUID = Patient.unassignedID
    @Published var currentTrial: Trial? = nil
    
    // Computed Properties 
    var isRecording: Bool { currentTrial != nil }
    
    var selectedPatient: Patient {
        patients.first(where: { $0.id == selectedPatientID }) ?? Patient.unassigned
    }
    
    var selectedPatientTrials: [Trial] {
        selectedPatient.trials.sorted { $0.startDate > $1.startDate }
    }
    
    // Initialization
    
    override init() {
        super.init()
        load()
        
        // Ensure "Unassigned" patient always exists
        if !patients.contains(where: { $0.id == Patient.unassignedID }) {
            patients.insert(Patient.unassigned, at: 0)
            save()
        }
    }
    
    //  PATIENT MANAGEMENT
    
    func addPatient(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let patient = Patient(name: trimmed)
        patients.append(patient)
        selectedPatientID = patient.id
        save()
        
        print("[DataStore] Added patient: \(trimmed)")
    }
    
    func deletePatient(id: UUID) {
        guard id != Patient.unassignedID else {
            print("[DataStore] Cannot delete Unassigned")
            return
        }
        
        patients.removeAll { $0.id == id }
        
        // If the deleted patient was selected, switch back to Unassigned
        if selectedPatientID == id {
            selectedPatientID = Patient.unassignedID
        }
        
        save()
        print("[DataStore] Deleted patient: \(id)")
    }
    
    func selectPatient(id: UUID) {
        guard patients.contains(where: { $0.id == id }) else { return }
        selectedPatientID = id
        print("[DataStore] Selected patient: \(selectedPatient.name)")
    }
    
    var realPatients: [Patient] {
        patients
            .filter { !$0.isUnassigned }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    //  TRIAL RECORDING
    
    func startTrial() {
        guard currentTrial == nil else {
            print("[DataStore] Already recording a trial")
            return
        }
        
        currentTrial = Trial()
        print("[DataStore] Trial started for \(selectedPatient.name)")
    }
    
    func addDataPoint(weightLeft: Double, weightRight: Double, distanceFt: Double, speedFtS: Double) {
        guard currentTrial != nil else { return }
        
        let point = DataPoint(
            timestamp: Date(),
            weightLeft: weightLeft,
            weightRight: weightRight,
            distanceFt: distanceFt,
            speedFtS: speedFtS
        )
        
        currentTrial?.dataPoints.append(point)
    }
    
    func stopTrial() {
        guard var trial = currentTrial else {
            print("[DataStore] No trial is recording")
            return
        }
        
        trial.endDate = Date()
        
        // Find the selected patient and append the trial
        if let index = patients.firstIndex(where: { $0.id == selectedPatientID }) {
            patients[index].trials.append(trial)
        }
        
        currentTrial = nil
        
        save()
        print("[DataStore] Trial stopped and saved (\(trial.sampleCount) data points, \(trial.durationFormatted))")
    }
    
    func cancelTrial() {
        currentTrial = nil
        print("[DataStore] Trial cancelled")
    }
    
    func deleteTrial(patientID: UUID, trialID: UUID) {
        guard let patientIndex = patients.firstIndex(where: { $0.id == patientID }) else { return }
        patients[patientIndex].trials.removeAll { $0.id == trialID }
        save()
        print("[DataStore] Deleted trial \(trialID)")
    }
    
    //  PERSISTENCE (JSON file)
    
    /// The URL of the JSON data file in the app's Documents directory
    private var dataFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("smart_walker_data.json")
    }
    
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted  // readable for debugging
            
            let data = try encoder.encode(patients)
            try data.write(to: dataFileURL, options: .atomic)
            
            print("[DataStore] Saved to \(dataFileURL.lastPathComponent)")
        } catch {
            print("[DataStore] Save failed: \(error.localizedDescription)")
        }
    }
    
    /// Load all patients (and their trials) from disk
    private func load() {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else {
            print("[DataStore] No data file found — starting fresh")
            patients = [Patient.unassigned]
            return
        }
        
        do {
            let data = try Data(contentsOf: dataFileURL)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            patients = try decoder.decode([Patient].self, from: data)
            
            print("[DataStore] Loaded \(patients.count) patients from disk")
        } catch {
            print("[DataStore] Load failed: \(error.localizedDescription) — starting fresh")
            patients = [Patient.unassigned]
        }
    }
}
