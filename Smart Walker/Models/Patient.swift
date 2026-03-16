//
//  Patient.swift
//  Smart Walker
//
//  Data model for a patient. 
//

import Foundation

struct Patient: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var dateCreated: Date
    var trials: [Trial]
    
    init(id: UUID = UUID(), name: String, dateCreated: Date = Date(), trials: [Trial] = []) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
        self.trials = trials
    }
    
    // "Unassigned"
    // the default patient for trials without a specific patient
    
    /// Fixed UUID so the Unassigned patient is always the same across app launches
    static let unassignedID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    static let unassigned = Patient(
        id: unassignedID,
        name: "Unassigned",
        dateCreated: Date.distantPast
    )
    
    /// Check if this patient is the "Unassigned" placeholder
    var isUnassigned: Bool {
        id == Patient.unassignedID
    }
}
