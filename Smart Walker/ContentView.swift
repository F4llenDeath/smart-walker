//
//  ContentView.swift
//  Smart Walker
//
//  Created by Xicheng Yang on 2026/3/12.
//

import SwiftUI

struct ContentView: View {
    @State private var trialRunning = false
    @State private var weightLbs: Double = 0.0
    @State private var distanceFt: Double = 0.0
    @State private var speedFtS: Double = 0.0

    var body: some View {
        VStack(spacing: 18) {
            Text("Smart Walker Live Telemetry")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Text("Status: \(trialRunning ? "RUNNING" : "STOPPED")")
                .font(.title2)
                .foregroundColor(trialRunning ? .green : .red)

            telemetryRow(label: "Weight (lbs)", value: weightLbs, decimals: 2)
            telemetryRow(label: "Distance (ft)", value: distanceFt, decimals: 2)
            telemetryRow(label: "Speed (ft/s)", value: speedFtS, decimals: 2)

            HStack(spacing: 16) {
                Button(action: startTrial) {
                    Text("Start Trial")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }

                Button(action: stopTrial) {
                    Text("Stop Trial")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(10)
                }
            }
            .padding(.top, 8)

            Text("Values refresh automatically.")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onAppear {
            startMockRefresh()
        }
    }

    @ViewBuilder
    private func telemetryRow(label: String, value: Double, decimals: Int) -> some View {
        HStack {
            Text(label + ":")
                .font(.title3)
            Spacer()
            Text(String(format: "%.\(decimals)f", value))
                .font(.title3)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 4)
    }

    private func startTrial() {
        trialRunning = true
    }

    private func stopTrial() {
        trialRunning = false
    }

    private func startMockRefresh() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if trialRunning {
                weightLbs = Double.random(in: 120...180)
                distanceFt += Double.random(in: 0.2...1.2)
                speedFtS = Double.random(in: 1.0...4.0)
            } else {
                speedFtS = 0.0
            }
        }
    }
}

#Preview {
    ContentView()
}
