import Foundation
import CoreMotion
import WatchConnectivity
import os.log

class WatchSensorManager: NSObject, WCSessionDelegate {
    // Logger
    private let logger = OSLog(subsystem: "com.gammaStimulator.watch", category: "SleepTracking")
    
    // Singleton instance
    static let shared = WatchSensorManager()
    
    // Motion manager for accelerometer data
    private let motionManager = CMMotionManager()
    
    // Watch connectivity session
    private var session: WCSession?
    
    // MARK: - Data collection settings
    private let accelerometerUpdateInterval: TimeInterval = 1.0   // 1 Hz is plenty
    private let dataTransferInterval:    TimeInterval = 60.0      // once a minute
    
    // Data buffers
    private var accelerometerData: [[String: Double]] = []
    private var heartRateData: Double?
    private var temperatureData: Double?
    private var sleepStageData: SleepStage = .unknown
    private var lastSleepStage: SleepStage = .unknown
    
    // Sleep stage statistics
    private var sleepStageTransitions: [(stage: SleepStage, timestamp: Date)] = []
    private var deepSleepDetectionCount: Int = 0
    
    // Data collection state
    private(set) var isCollecting = false
    private var dataTransferTimer: Timer?
    private var sleepMonitoringTimer: Timer?
    
    private override init() {
        super.init()
        setupWatchConnectivity()
        os_log("WatchSensorManager initialized", log: logger, type: .info)
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
    
    // MARK: - Data Collection
    
    // Start collecting sensor data
    func startDataCollection() {
        guard !isCollecting else { return }
        
        os_log("Starting data collection", log: logger, type: .info)
        
        // Reset statistics
        sleepStageTransitions.removeAll()
        deepSleepDetectionCount = 0
        
        // Start accelerometer updates
        if self.motionManager.isAccelerometerAvailable {
            self.motionManager.accelerometerUpdateInterval = self.accelerometerUpdateInterval
            self.motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
                guard let self = self, let data = data else { return }
                self.processAccelerometerData(data)
            }
            os_log("Accelerometer monitoring started", log: self.logger, type: .info)
        } else {
            os_log("Accelerometer not available", log: self.logger, type: .fault)
        }
        
        // Start periodic data transfer
        self.dataTransferTimer = Timer.scheduledTimer(withTimeInterval: self.dataTransferInterval,
                                                      repeats: true) { [weak self] _ in
            self?.sendSensorDataToPhone()
        }
        
        self.isCollecting = true
        os_log("Watch sensor data collection started successfully", log: self.logger, type: .info)
    }
    
    // Stop collecting sensor data
    func stopDataCollection() {
        guard isCollecting else { return }
        
        os_log("Stopping data collection", log: logger, type: .info)
        
        // Log sleep stage statistics
        logSleepStageStatistics()
        
        // Stop accelerometer updates
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
            os_log("Accelerometer monitoring stopped", log: logger, type: .info)
        }
        
        // Stop data transfer timer
        dataTransferTimer?.invalidate()
        dataTransferTimer = nil
        
        // Stop sleep monitoring timer
        sleepMonitoringTimer?.invalidate()
        sleepMonitoringTimer = nil
        
        // Clear buffers
        accelerometerData.removeAll()
        heartRateData = nil
        temperatureData = nil
        sleepStageData = .unknown
        
        isCollecting = false
        os_log("Watch sensor data collection stopped", log: logger, type: .info)
    }
    
    // Log sleep stage statistics
    private func logSleepStageStatistics() {
        os_log("===== SLEEP MONITORING STATISTICS =====", log: logger, type: .info)
        os_log("Total sleep stage transitions: %{public}d", log: logger, type: .info, sleepStageTransitions.count)
        os_log("Deep sleep detections: %{public}d", log: logger, type: .info, deepSleepDetectionCount)
        
        // Log all transitions
        for (index, transition) in sleepStageTransitions.enumerated() {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeString = formatter.string(from: transition.timestamp)
            os_log("Transition %{public}d: %{public}@ at %{public}@",
                   log: logger, type: .info,
                   index + 1,
                   transition.stage.description,
                   timeString)
        }
        
        os_log("======================================", log: logger, type: .info)
    }
    
    // MARK: - Data Processing
    
    // Process accelerometer data
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        // Add data to buffer
        let dataPoint: [String: Double] = [
            "x": data.acceleration.x,
            "y": data.acceleration.y,
            "z": data.acceleration.z,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        accelerometerData.append(dataPoint)
        
        // Limit buffer size
        if accelerometerData.count > 100 {
            accelerometerData.removeFirst(accelerometerData.count - 100)
        }
    }
    
    // MARK: - Data Transfer
    
    // Send collected sensor data to iPhone
    private func sendSensorDataToPhone() {
        guard let session = session, isCollecting else { return }
        
        // 1‑minute summary – much smaller payload
        let payload: [String: Any] = [
            "timestamp"    : Date().timeIntervalSince1970,
            "sleepStage"   : sleepStageData.rawValue,
            "heartRate"    : heartRateData ?? NSNull()
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            
        } else {
            // Queue for delivery while the phone is asleep/locked.
            session.transferUserInfo(payload)
        }
        
        // we no longer need the accelerometer buffer
        accelerometerData.removeAll()
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            os_log("WCSession activation failed with error: %{public}@", log: logger, type: .error, error.localizedDescription)
            return
        }
        
        os_log("WCSession activated with state: %{public}d", log: logger, type: .info, activationState.rawValue)
    }
        
    // Handle messages from iPhone
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        
        // Handle messages from iPhone
        if let command = message["command"] as? String {
            os_log("Received command from iPhone: %{public}@", log: logger, type: .info, command)
            switch command {
            case "startCollection":
                DispatchQueue.main.async {
                    os_log("Starting data collection as requested by iPhone", log: self.logger, type: .info)
                    self.startDataCollection()
                }
            case "stopCollection":
                DispatchQueue.main.async {
                    os_log("Stopping data collection as requested by iPhone", log: self.logger, type: .info)
                    self.stopDataCollection()
                }
            default:
                os_log("Unknown command received from iPhone: %{public}@", log: self.logger, type: .fault, command)
                break
            }
            
        }
    }
    
    func session(_ session: WCSession,
                 didReceiveMessage message: [String : Any],
                 replyHandler: @escaping ([String : Any]) -> Void) {
        
        os_log("Received message from iPhone with reply handler: %{public}@", log: logger, type: .debug, message.description)
        
        if let command = message["command"] as? String {
            os_log("Received command from iPhone: %{public}@", log: logger, type: .info, command)
            switch command {
            case "startCollection":
                DispatchQueue.main.async {
                    os_log("Starting data collection as requested by iPhone", log: self.logger, type: .info)
                    self.startDataCollection()
                    
                    // ✅ Send back a confirmation message
                    replyHandler(["status": "started", "timestamp": Date().timeIntervalSince1970])
                }
            case "stopCollection":
                DispatchQueue.main.async {
                    os_log("Stopping data collection as requested by iPhone", log: self.logger, type: .info)
                    self.stopDataCollection()
                    
                    // ✅ Send back a confirmation message
                    replyHandler(["status": "stopped", "timestamp": Date().timeIntervalSince1970])
                }
            default:
                os_log("Unknown command received from iPhone: %{public}@", log: self.logger, type: .fault, command)
                replyHandler(["status": "unknown_command"])
            }
        } else {
            replyHandler(["status": "invalid_format"])
        }
    }
}
