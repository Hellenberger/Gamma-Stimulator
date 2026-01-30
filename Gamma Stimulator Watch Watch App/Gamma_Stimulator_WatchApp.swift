//
//  Gamma_Stimulator_WatchApp.swift
//  Gamma Stimulator Watch Watch App
//
//  Created by Howard Ellenberger on 4/14/25.
//

import SwiftUI

@main
struct GammaStimulatorApp: App {
    init() {
        _ = WatchSessionManager.shared  // Ensures setupSession() runs early
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
