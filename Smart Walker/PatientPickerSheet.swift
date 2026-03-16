//
//  PatientPickerSheet.swift
//  Smart Walker
//
//  A bottom sheet for selecting or adding patients.
//

import SwiftUI

struct PatientPickerSheet: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    
    @State private var newPatientName = ""
    
    var body: some View {
        NavigationStack {
            List {
                
                // Unassigned (always first)
                Section {
                    Button(action: { selectAndDismiss(id: Patient.unassignedID) }) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .foregroundColor(.secondary)
                            Text("Unassigned")
                            Spacer()
                            if dataStore.selectedPatientID == Patient.unassignedID {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                // Patient List 
                Section("Patients") {
                    if dataStore.realPatients.isEmpty {
                        Text("No patients added yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(dataStore.realPatients) { patient in
                            Button(action: { selectAndDismiss(id: patient.id) }) {
                                HStack {
                                    Image(systemName: "person.crop.circle.fill")
                                        .foregroundColor(.accentColor)
                                    Text(patient.name)
                                    Spacer()
                                    if dataStore.selectedPatientID == patient.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                        .onDelete(perform: deletePatients)
                    }
                }
                
                // Add New Patient
                Section("Add Patient") {
                    HStack {
                        TextField("Patient name", text: $newPatientName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(addPatient)
                        
                        Button(action: addPatient) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                        }
                        .disabled(newPatientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Select Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    // Actions
    
    private func selectAndDismiss(id: UUID) {
        dataStore.selectPatient(id: id)
        dismiss()
    }
    
    private func addPatient() {
        let name = newPatientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        dataStore.addPatient(name: name)
        newPatientName = ""
        dismiss()
    }
    
    private func deletePatients(at offsets: IndexSet) {
        let patients = dataStore.realPatients
        for index in offsets {
            dataStore.deletePatient(id: patients[index].id)
        }
    }
}

#Preview {
    PatientPickerSheet()
        .environmentObject(DataStore())
}
