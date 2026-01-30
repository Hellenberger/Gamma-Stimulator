//
//  PhoneWatchConnector.swift
//  Gamma Stimulator
//

import Foundation
import WatchConnectivity
import os.log

protocol PhoneWatchConnectorDelegate: AnyObject {
    func connector(_ connector: PhoneWatchConnector, didReceiveAccelerometerData data: [[String: Double]])
    func connector(_ connector: PhoneWatchConnector, didReceiveHeartRate heartRate: Double)
    func connector(_ connector: PhoneWatchConnector, didReceiveTemperature temperature: Double)
    func connector(_ connector: PhoneWatchConnector, didReceiveSleepStage stage: SleepStage)
    func connectorDidChangeConnectionState(_ connector: PhoneWatchConnector)
}

class PhoneWatchConnector: NSObject, WCSessionDelegate {
    // Logger
    private let logger = OSLog(subsystem: "com.gammaStimulator.phone", category: "WatchConnectivity")
    
    // Sleep stage statistics
    private var sleepStageReceiveCount: [SleepStage: Int] = [.awake: 0, .light: 0, .deep: 0, .rem: 0, .unknown: 0]
    private var lastReceivedStage: SleepStage = .unknown
    private var stageTransitions: [(from: SleepStage, to: SleepStage, timestamp: Date)] = []
    private var deepSleepDetectionTimes: [Date] = []
    
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
        os_log("PhoneWatchConnector initialized", log: logger, type: .info)
    }
    
    // MARK: - Setup Methods
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            os_log("Watch connectivity session activated", log: logger, type: .info)
        } else {
            os_log("Watch connectivity not supported on this device", log: logger, type: .error)
        }
    }
    
    // MARK: - Public Methods
    
    // Start monitoring on the watch
    func startWatchMonitoring() {
        guard let session = session else { return }

        if session.isReachable {
            session.sendMessage(["command": "startCollection"], replyHandler: nil, errorHandler: { error in
                print("Error sending startCollection: \(error.localizedDescription)")
            })
        } else {
            print("Watch not reachable. Using transferUserInfo.")
            session.transferUserInfo(["command": "startCollection"])
        }

        // Reset any old stats
        resetStatistics()

        // ✅ Send the message only if reachable
        session.sendMessage(["command": "startCollection"], replyHandler: { replyMessage in
            
            session.transferUserInfo(["command": "startCollection"])

            
            os_log("✅ Watch confirmed monitoring start: %{public}@", log: self.logger, type: .info, replyMessage.description)
        }) { error in
            os_log("❌ Failed to send start command to Watch: %{public}@", log: self.logger, type: .error, error.localizedDescription)
            
            // 🔁 Optional retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if session.isReachable {
                    os_log("🔁 Retrying startCollection...", log: self.logger, type: .info)
                    session.sendMessage(["command": "startCollection"], replyHandler: nil, errorHandler: nil)
                }
            }
        }

        os_log("📡 Sent startCollection command to Watch", log: logger, type: .info)
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        os_log("📶 Watch state changed: Installed: %{public}@, Reachable: %{public}@",
               log: logger,
               type: .info,
               String(session.isWatchAppInstalled),
               String(session.isReachable))
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        os_log("🔄 Watch reachability changed: %{public}@", log: logger, type: .info, String(session.isReachable))

        if session.isReachable {
            // Retry wake/start
            sendStartMessage()
        }
    }

    private func sendStartMessage() {
        let message = ["command": "startCollection"]
        session?.sendMessage(message, replyHandler: { reply in
            os_log("✅ Watch replied: %@", log: self.logger, type: .info, reply.description)
        }, errorHandler: { error in
            os_log("❌ Failed to send start command: %@", log: self.logger, type: .error, error.localizedDescription)
        })
    }
    
    func sendStartCommandToWatch() {
        let session = WCSession.default
        guard session.isReachable else {
            print("⌛️ Watch not reachable")
            return
        }

        session.sendMessage(["command": "startCollection"], replyHandler: nil) { error in
            print("❌ Send failed: \(error.localizedDescription)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Retry once
                if session.isReachable {
                    print("🔁 Retrying startCollection")
                    session.sendMessage(["command": "startCollection"], replyHandler: nil, errorHandler: nil)
                }
            }
        }
    }

    func wakeWatchApp() {
        guard let session = session, session.activationState == .activated else {
            os_log("WCSession not activated", log: logger, type: .error)
            return
        }

        if session.isReachable {
            session.sendMessage(["command": "wake"], replyHandler: nil) { error in
                os_log("Failed to send wake command: %@", log: self.logger, type: .error, error.localizedDescription)
            }
            os_log("Sent wake command to Watch", log: logger, type: .info)
        } else {
            os_log("Watch not reachable. Cannot send wake command.", log: logger, type: .error)
        }
    }

    // Stop monitoring on the watch
    func stopWatchMonitoring() {
        guard let session = session, session.isReachable else {
            os_log("Watch is not reachable, cannot stop monitoring", log: logger, type: .error)
            return
        }
        
        // Log statistics
        logSleepStageStatistics()
        
        let message = ["command": "stopCollection"]
        session.sendMessage(message, replyHandler: { replyMessage in
            os_log("Watch confirmed monitoring stop: %{public}@", log: self.logger, type: .info, replyMessage.description)
        }) { error in
            os_log("Error stopping watch monitoring: %{public}@", log: self.logger, type: .error, error.localizedDescription)
        }
        
        os_log("Sent stopCollection command to Watch", log: logger, type: .info)
    }
    
    // Reset statistics
    private func resetStatistics() {
        sleepStageReceiveCount = [.awake: 0, .light: 0, .deep: 0, .rem: 0, .unknown: 0]
        lastReceivedStage = .unknown
        stageTransitions.removeAll()
        deepSleepDetectionTimes.removeAll()
        os_log("Sleep statistics reset", log: logger, type: .info)
    }
    
    // Log sleep stage statistics
    private func logSleepStageStatistics() {
        os_log("===== SLEEP MONITORING STATISTICS =====", log: logger, type: .info)
        os_log("Received sleep stages - Awake: %{public}d, Light: %{public}d, Deep: %{public}d, REM: %{public}d, Unknown: %{public}d",
               log: logger, type: .info,
               sleepStageReceiveCount[.awake] ?? 0,
               sleepStageReceiveCount[.light] ?? 0,
               sleepStageReceiveCount[.deep] ?? 0,
               sleepStageReceiveCount[.rem] ?? 0,
               sleepStageReceiveCount[.unknown] ?? 0)
        
        os_log("Total sleep stage transitions: %{public}d", log: logger, type: .info, stageTransitions.count)
        os_log("Deep sleep detections: %{public}d", log: logger, type: .info, deepSleepDetectionTimes.count)
        
        // Log deep sleep detection times
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        
        for (index, date) in deepSleepDetectionTimes.enumerated() {
            let timeString = formatter.string(from: date)
            os_log("Deep sleep detection %{public}d: %{public}@", log: logger, type: .info, index + 1, timeString)
        }
        
        // Log transitions
        for (index, transition) in stageTransitions.enumerated() {
            let timeString = formatter.string(from: transition.timestamp)
            os_log("Transition %{public}d: %{public}@ -> %{public}@ at %{public}@",
                   log: logger, type: .info,
                   index + 1,
                   transition.from.description,
                   transition.to.description,
                   timeString)
        }
        
        os_log("======================================", log: logger, type: .info)
    }
    
    // Check if watch app is available
    func isWatchAppAvailable() -> Bool {
        return isWatchAppInstalled && isWatchReachable
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            os_log("WCSession activation failed with error: %{public}@", log: logger, type: .error, error.localizedDescription)
            return
        }
        
        os_log("WCSession activated with state: %{public}d", log: logger, type: .info, activationState.rawValue)
        
        // Update watch state
        DispatchQueue.main.async {
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isWatchReachable = session.isReachable
            os_log("Watch state updated - Installed: %{public}@, Reachable: %{public}@",
                   log: self.logger,
                   type: .info,
                   String(self.isWatchAppInstalled),
                   String(self.isWatchReachable))
            
            self.delegate?.connectorDidChangeConnectionState(self)
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        os_log("WCSession became inactive", log: logger, type: .info)
        
        DispatchQueue.main.async {
            self.isWatchReachable = false
            os_log("Watch reachability updated - Reachable: false", log: self.logger, type: .info)
            self.delegate?.connectorDidChangeConnectionState(self)
        }
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        os_log("WCSession deactivated, attempting reactivation", log: logger, type: .info)
        
        // Reactivate the session
        session.activate()
        
        DispatchQueue.main.async {
            self.isWatchReachable = false
            os_log("Watch reachability updated - Reachable: false", log: self.logger, type: .info)
            self.delegate?.connectorDidChangeConnectionState(self)
        }
    }
    
    // MARK: - Message Handling
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        os_log("Received message from watch: %{public}@", log: logger, type: .debug, message.description)
        
        if message["ready"] as? Bool == true {
               os_log("✅ Watch reported ready, sending startCollection", log: logger, type: .info)
               
               session.sendMessage(["command": "startCollection"], replyHandler: nil, errorHandler: { error in
                   os_log("❌ Failed to send startCollection after ready: %{public}@", log: self.logger, type: .error, error.localizedDescription)
               })
           }
        
        if let accelData = message["accelerometer"] as? [[String:Double]] {
            os_log("Received accelerometer data with %{public}d samples", log: logger, type: .debug, accelData.count)
            DispatchQueue.main.async {
                self.delegate?.connector(self, didReceiveAccelerometerData: accelData)
            }
        }
        
        if let heartRate = message["heartRate"] as? Double {
            os_log("Received heart rate: %{public}.2f BPM", log: logger, type: .debug, heartRate)
            DispatchQueue.main.async {
                self.delegate?.connector(self, didReceiveHeartRate: heartRate)
            }
        }
        
        if let temperature = message["temperature"] as? Double {
            os_log("Received temperature: %{public}.2f °C", log: logger, type: .debug, temperature)
            DispatchQueue.main.async {
                self.delegate?.connector(self, didReceiveTemperature: temperature)
            }
        }
        
        if let stageRawValue = message["sleepStage"] as? Int, let stage = SleepStage(rawValue: stageRawValue) {
            os_log("Received sleep stage: %{public}@", log: logger, type: .debug, stage.description)
            
            // Update sleep stage statistics
            sleepStageReceiveCount[stage] = (sleepStageReceiveCount[stage] ?? 0) + 1
            
            // Record transition if stage changed
            if lastReceivedStage != stage {
                let transition = (from: lastReceivedStage, to: stage, timestamp: Date())
                stageTransitions.append(transition)
                os_log("Sleep stage transition: %{public}@ -> %{public}@",
                       log: logger,
                       type: .info,
                       lastReceivedStage.description,
                       stage.description)
                
                // Post notification with the current stage and previous stage
                let userInfo: [String: Any] = [
                    "stage": stage.rawValue,
                    "previousStage": lastReceivedStage.rawValue,
                    "timestamp": Date()
                ]
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("SleepStageUpdate"),
                    object: self,
                    userInfo: userInfo
                )
                
                // Update last received stage
                lastReceivedStage = stage
            }
            
            // Log deep sleep detection
            if stage == .deep {
                let now = Date()
                deepSleepDetectionTimes.append(now)
                
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                os_log("Deep sleep detected at %{public}@", log: logger, type: .info, formatter.string(from: now))
                
                // Post notification for deep sleep detection (stimulation trigger)
                NotificationCenter.default.post(
                    name: NSNotification.Name("StimulationTrigger"),
                    object: self,
                    userInfo: ["timestamp": now]
                )
            }
            
            DispatchQueue.main.async {
                self.delegate?.connector(self, didReceiveSleepStage: stage)
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        os_log("Received message data from watch - Size: %{public}d bytes", log: logger, type: .debug, messageData.count)
        
        // Process binary data if needed
        do {
            if let message = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSDictionary.self, from: messageData) as? [String: Any] {
                os_log("Successfully unarchived message data: %{public}@", log: logger, type: .debug, message.description)
                self.session(session, didReceiveMessage: message)
            }
        } catch {
            os_log("Error unarchiving message data: %{public}@", log: logger, type: .error, error.localizedDescription)
        }
    }
    
    // MARK: - Error Handling
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        os_log("Received user info from watch: %{public}@", log: logger, type: .debug, userInfo.description)
    }
    
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error = error {
            os_log("User info transfer failed: %{public}@", log: logger, type: .error, error.localizedDescription)
        } else {
            os_log("User info transfer completed successfully", log: logger, type: .debug)
        }
    }
    
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            os_log("File transfer failed: %{public}@", log: logger, type: .error, error.localizedDescription)
        } else {
            os_log("File transfer completed successfully", log: logger, type: .debug)
            os_log("File transfer URL: %{public}@", log: logger, type: .debug, fileTransfer.file.fileURL.path)
        }
    }
    
    func session(_ session: WCSession,
                 didReceiveMessage message: [String : Any],
                 replyHandler: @escaping ([String : Any]) -> Void) {
        
        // Re‑use the existing parser
        self.session(session, didReceiveMessage: message)
        
        // Acknowledge so the watch's replyHandler doesn’t time‑out
        replyHandler(["status":"received"])
    }
}
