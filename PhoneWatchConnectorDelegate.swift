import Foundation
import WatchConnectivity

protocol PhoneWatchConnectorDelegate: AnyObject {
    func connector(_ connector: PhoneWatchConnector, didReceiveAccelerometerData data: [[String: Double]])
    func connector(_ connector: PhoneWatchConnector, didReceiveHeartRate heartRate: Double)
    func connector(_ connector: PhoneWatchConnector, didReceiveTemperature temperature: Double)
    func connectorDidChangeConnectionState(_ connector: PhoneWatchConnector)
}

class PhoneWatchConnector: NSObject, WCSessionDelegate {
    // Singleton instance
    static let shared = PhoneWatchConnector()
    
    // Delegate for data handling
    weak var delegate: PhoneWatchConnectorDelegate?
    
    // Watch connectivity session
    private var session: WCSession?
    
    // Connection state
    private(set) var isWatchAppInstalled = false
    private(set) var isWatchReachable = false
    
    // Initialization
    private override init() {
        super.init()
        setupWatchConnectivity()
    }
    
    // MARK: - Setup Methods
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    // MARK: - Public Methods
    
    // Start monitoring on the watch
    func startWatchMonitoring() {
        guard let session = session, session.isReachable else {
            print("Watch is not reachable")
            return
        }
        
        let message = ["command": "startCollection"]
        session.sendMessage(message, replyHandler: nil) { error in
            print("Error starting watch monitoring: \(error.localizedDescription)")
        }
    }
    
    // Stop monitoring on the watch
    func stopWatchMonitoring() {
        guard let session = session, session.isReachable else {
            print("Watch is not reachable")
            return
        }
        
        let message = ["command": "stopCollection"]
        session.sendMessage(message, replyHandler: nil) { error in
            print("Error stopping watch monitoring: \(error.localizedDescription)")
        }
    }
    
    // Check if watch app is available
    func isWatchAppAvailable() -> Bool {
        return isWatchAppInstalled && isWatchReachable
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
            return
        }
        
        print("WCSession activated with state: \(activationState.rawValue)")
        
        // Update watch state
        DispatchQueue.main.async {
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isWatchReachable = session.isReachable
            self.delegate?.connectorDidChangeConnectionState(self)
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession did become inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession did deactivate")
        
        // Reactivate session if needed
        session.activate()
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isWatchReachable = session.isReachable
            self.delegate?.connectorDidChangeConnectionState(self)
        }
    }
    
    // Process incoming messages from the watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            // Process timestamp
            let timestamp = message["timestamp"] as? Double ?? Date().timeIntervalSince1970
            
            // Process accelerometer data
            if let accelerometerData = message["accelerometer"] as? [[String: Double]] {
                self.delegate?.connector(self, didReceiveAccelerometerData: accelerometerData)
            }
            
            // Process heart rate data
            if let heartRate = message["heartRate"] as? Double {
                self.delegate?.connector(self, didReceiveHeartRate: heartRate)
            }
            
            // Process temperature data
            if let temperature = message["temperature"] as? Double {
                self.delegate?.connector(self, didReceiveTemperature: temperature)
            }
        }
    }
}