//
//  Smart_WalkerApp.swift
//  Smart Walker
//
//  Created by Xicheng Yang on 2026/3/12.
//

import SwiftUI

@main
struct Smart_WalkerApp: App {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var dataStore = DataStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
                .environmentObject(dataStore)
        }
    }
}
