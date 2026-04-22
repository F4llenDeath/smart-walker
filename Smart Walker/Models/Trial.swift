//
//  Trial.swift
//  Smart Walker
//
//  Data models for a recorded trial and its individual data points.
//

import Foundation

// DataPoint
struct DataPoint: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var timestamp: Date
    var weightLeft: Double      
    var weightRight: Double     
    var distanceFt: Double      
    var speedFtS: Double        
    
    var weightTotal: Double { weightLeft + weightRight }
}

// Trial
struct Trial: Identifiable, Codable, Equatable {
    var id: UUID
    var startDate: Date
    var endDate: Date?          // nil while still recording
    var dataPoints: [DataPoint]
    
    init(id: UUID = UUID(), startDate: Date = Date(), endDate: Date? = nil, dataPoints: [DataPoint] = []) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.dataPoints = dataPoints
    }
    
    // Status
    var isRecording: Bool { endDate == nil }
    
    // Computed Summary Stats 

    var duration: TimeInterval {
        let end = endDate ?? Date()
        return end.timeIntervalSince(startDate)
    }
    
    var durationFormatted: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    /// Distance walked during the trial only (last - first data point).
    var totalDistance: Double {
        guard let first = dataPoints.first?.distanceFt,
              let last  = dataPoints.last?.distanceFt else { return 0.0 }
        return max(0.0, last - first)
    }

    
    var averageSpeed: Double {
        guard !dataPoints.isEmpty else { return 0.0 }
        let sum = dataPoints.reduce(0.0) { $0 + $1.speedFtS }
        return sum / Double(dataPoints.count)
    }
    
    var averageWeightLeft: Double {
        guard !dataPoints.isEmpty else { return 0.0 }
        let sum = dataPoints.reduce(0.0) { $0 + $1.weightLeft }
        return sum / Double(dataPoints.count)
    }
    
    var averageWeightRight: Double {
        guard !dataPoints.isEmpty else { return 0.0 }
        let sum = dataPoints.reduce(0.0) { $0 + $1.weightRight }
        return sum / Double(dataPoints.count)
    }
    
    var averageWeightTotal: Double {
        averageWeightLeft + averageWeightRight
    }
    
    var sampleCount: Int {
        dataPoints.count
    }
    
    // CSV Export
    
    /// ISO 8601 date formatter for CSV timestamps
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    /// Format:
    /// timestamp,weightLeft,weightRight,weightTotal,distanceFt,speedFtS
    /// 2026-03-16T01:35:00.000Z,78.20,74.10,152.30,0.00,0.00
    func toCSV() -> String {
        var lines: [String] = []
        
        // Header
        lines.append("timestamp,weightLeft,weightRight,weightTotal,distanceFt,speedFtS")
        
        // Data rows
        for point in dataPoints {
            let ts = Trial.isoFormatter.string(from: point.timestamp)
            let line = String(
                format: "%@,%.2f,%.2f,%.2f,%.2f,%.2f",
                ts,
                point.weightLeft,
                point.weightRight,
                point.weightTotal,
                point.distanceFt,
                point.speedFtS
            )
            lines.append(line)
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Generate a filename
    var csvFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateStr = formatter.string(from: startDate)
        return "trial_\(dateStr).csv"
    }
}
