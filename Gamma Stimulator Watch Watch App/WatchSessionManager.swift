//
//  WatchSessionManager.swift
//  Gamma Stimulator
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
            print("WCSession activated on Watch")
        }
    }
    
    func activate() {
        session?.activate()
    }
    
    // Required WCSessionDelegate methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("Watch session activated with state: \(activationState.rawValue)")

        if activationState == .activated {
            WCSession.default.sendMessage(["ready": true], replyHandler: nil, errorHandler: { error in
                print("❌ Failed to notify iPhone that Watch is ready: \(error.localizedDescription)")
            })
        }

        // ✅ Send this under a different notification name
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("WCConnectionUpdate"), object: nil, userInfo: [
                "connection": activationState == .activated ? "Connected" : "Waiting..."
            ])
        }

        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("🔁 Reachability changed: \(session.isReachable)")
    }

    // Handle messages from the iPhone app
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            if let command = message["command"] as? String {
                switch command {
                case "startCollection":
                    WatchSensorManager.shared.startDataCollection()

                    // Reply to iPhone
                    session.sendMessage(["status": "started", "timestamp": Date().timeIntervalSince1970],
                                        replyHandler: nil, errorHandler: nil)
                    
                    print("📡 Posting WCStatusUpdate: Collecting Sleep Data")

                    // ✅ Post notification to update UI
                    NotificationCenter.default.post(
                        name: Notification.Name("WCStatusUpdate"),
                        object: nil,
                        userInfo: ["status": "Collecting Sleep Data"]
                    )

                case "stopCollection":
                    WatchSensorManager.shared.stopDataCollection()
                    NotificationCenter.default.post(
                        name: Notification.Name("WCStatusUpdate"),
                        object: nil,
                        userInfo: ["status": "Stopped"]
                    )

                default:
                    print("Received unknown command: \(command)")
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
