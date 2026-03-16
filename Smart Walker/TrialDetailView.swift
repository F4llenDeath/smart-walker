//
//  TrialDetailView.swift
//  Smart Walker
//
//  Read-only detail view for a past trial.
//

import SwiftUI

struct TrialDetailView: View {
    let trial: Trial
    
    /// Date formatter
    private var dateFormatted: String {
        trial.startDate.formatted(date: .long, time: .omitted)
    }
    
    /// Time formatter
    private var startTimeFormatted: String {
        trial.startDate.formatted(date: .omitted, time: .standard)
    }
    
    private var endTimeFormatted: String {
        guard let end = trial.endDate else { return "—" }
        return end.formatted(date: .omitted, time: .standard)
    }
    
    var body: some View {
        List {
            
            Section("Time") {
                detailRow("Date", value: dateFormatted)
                detailRow("Start", value: startTimeFormatted)
                detailRow("End", value: endTimeFormatted)
                detailRow("Duration", value: trial.durationFormatted)
            }
            
            Section("Distance & Speed") {
                detailRow("Total Distance", value: String(format: "%.2f ft", trial.totalDistance))
                detailRow("Avg Speed", value: String(format: "%.2f ft/s", trial.averageSpeed))
            }
            
            Section("Weight") {
                detailRow("Avg Weight L", value: String(format: "%.2f lbs", trial.averageWeightLeft))
                detailRow("Avg Weight R", value: String(format: "%.2f lbs", trial.averageWeightRight))
                detailRow("Avg Total", value: String(format: "%.2f lbs", trial.averageWeightTotal))
            }
            
            // Export
            Section {
                ShareLink(
                    item: trial.toCSV(),
                    subject: Text("Smart Walker Trial Data"),
                    message: Text("Trial recorded on \(dateFormatted)"),
                    preview: SharePreview(
                        "Trial \(dateFormatted)",
                        image: Image(systemName: "tablecells")
                    )
                ) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export CSV")
                    }
                }
            }
        }
        .navigationTitle("Trial Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // Helper
    
    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    NavigationStack {
        TrialDetailView(trial: Trial(
            startDate: Date().addingTimeInterval(-150),
            endDate: Date(),
            dataPoints: [
                DataPoint(timestamp: Date(), weightLeft: 78.2, weightRight: 74.1, distanceFt: 12.5, speedFtS: 2.8),
                DataPoint(timestamp: Date(), weightLeft: 79.0, weightRight: 73.5, distanceFt: 15.3, speedFtS: 3.1),
            ]
        ))
    }
}
