//
//  WatchSessionManager.swift
//  Gamma Stimulator
//
//  Created by Howard Ellenberger on 4/14/25.
//


import WatchKit
import WatchConnectivity

class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    
    private var session: WCSession?
    
    private override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    // Required WCSessionDelegate methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
        } else {
            print("WCSession activated with state: \(activationState.rawValue)")
        }
    }
    
    // Handle messages from the iPhone app
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Process commands
        DispatchQueue.main.async {
            if let command = message["command"] as? String {
                switch command {
                case "startHaptic":
                    HapticFeedbackManager.shared.startHapticFeedback()
                    self.updateInterface(status: "Haptic Active")
                case "stopHaptic":
                    HapticFeedbackManager.shared.stopHapticFeedback()
                    self.updateInterface(status: "Haptic Stopped")
                default:
                    break
                }
            }
        }
    }
    
    // Helper method to update the interface
    private func updateInterface(status: String) {
        // For SwiftUI, you'll need to use NotificationCenter or a similar method
        // to communicate with your view
        NotificationCenter.default.post(
            name: NSNotification.Name("StatusUpdate"),
            object: nil,
            userInfo: ["status": status]
        )
    }
}