//
//  TrialDetailView.swift
//  Smart Walker
//
//  Read-only detail view for a past trial.
//

import SwiftUI
import Charts

struct TrialDetailView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    
    let trial: Trial
    
    @State private var showDeleteConfirm = false
    
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
    
    /// Data points with elapsed seconds for chart X-axis
    private var chartData: [(elapsed: Double, speed: Double, weightL: Double, weightR: Double)] {
        let start = trial.startDate
        return trial.dataPoints.map { point in
            let elapsed = point.timestamp.timeIntervalSince(start)
            return (elapsed: elapsed, speed: point.speedFtS, weightL: point.weightLeft, weightR: point.weightRight)
        }
    }
    
    var body: some View {
        List {
            
            // Speed Chart
            if trial.dataPoints.count >= 2 {
                Section("Speed") {
                    Chart {
                        ForEach(Array(chartData.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Time (s)", point.elapsed),
                                y: .value("Speed (ft/s)", point.speed)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxisLabel("Time (s)")
                    .chartYAxisLabel("ft/s")
                    .frame(height: 200)
                }
                
                // Weight Chart
                Section("Weight Distribution") {
                    Chart {
                        ForEach(Array(chartData.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Time (s)", point.elapsed),
                                y: .value("Weight", point.weightL),
                                series: .value("Foot", "Left")
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)
                            
                            LineMark(
                                x: .value("Time (s)", point.elapsed),
                                y: .value("Weight", point.weightR),
                                series: .value("Foot", "Right")
                            )
                            .foregroundStyle(.orange)
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxisLabel("Time (s)")
                    .chartYAxisLabel("lbs")
                    .chartForegroundStyleScale([
                        "Left": Color.blue,
                        "Right": Color.orange
                    ])
                    .frame(height: 200)
                }
            }
            
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .alert("Delete Trial?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                dataStore.deleteTrial(
                    patientID: dataStore.selectedPatientID,
                    trialID: trial.id
                )
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This trial and all its data will be permanently deleted.")
        }
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
        .environmentObject(DataStore())
    }
}
