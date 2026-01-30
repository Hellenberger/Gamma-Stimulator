import Foundation
import CoreMotion
import HealthKit
import WatchConnectivity
import os.log

class WatchSensorManager: NSObject, WCSessionDelegate {
    // Logger
    private let logger = OSLog(subsystem: "com.gammaStimulator.watch", category: "SleepTracking")
    
    // Singleton instance
    static let shared = WatchSensorManager()
    
    // Motion manager for accelerometer data
    private let motionManager = CMMotionManager()
    
    // Health store for heart rate monitoring
    private let healthStore = HKHealthStore()
    
    // Watch connectivity session
    private var session: WCSession?
    
    // Data collection settings
    private let accelerometerUpdateInterval: TimeInterval = 0.1 // 10 Hz
    private let dataTransferInterval: TimeInterval = 0.5 // Send data every half second
    private let sleepStageCheckInterval: TimeInterval = 30.0 // Check sleep stage every 30 seconds
    
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
    
    // Request authorization for health data
    func requestHealthAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        // Define the types of data we want to read
        let types: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        ]
        
        os_log("Requesting HealthKit authorization", log: logger, type: .info)
        healthStore.requestAuthorization(toShare: nil, read: types) { success, error in
            if let error = error {
                os_log("HealthKit authorization failed: %{public}@", log: self.logger, type: .error, error.localizedDescription)
            } else if success {
                os_log("HealthKit authorization granted", log: self.logger, type: .info)
            }
            completion(success, error)
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
        
        // Request health data authorization
        requestHealthAuthorization { [weak self] success, error in
            guard let self = self, success else {
                if let error = error {
                    if let strongSelf = self {
                        os_log("Heart rate update error: %{public}@", log: strongSelf.logger, type: .error, error.localizedDescription)
                    }
                    return
                }
                return
            }
        
            
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
            
            // Start heart rate monitoring
            self.startHeartRateMonitoring()
            
            // Start sleep stage monitoring
            self.startSleepStageMonitoring()
            
            // Start periodic data transfer
            self.dataTransferTimer = Timer.scheduledTimer(withTimeInterval: self.dataTransferInterval,
                                                        repeats: true) { [weak self] _ in
                self?.sendSensorDataToPhone()
            }
            
            self.isCollecting = true
            os_log("Watch sensor data collection started successfully", log: self.logger, type: .info)
        }
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
    
    // Start heart rate monitoring
    private func startHeartRateMonitoring() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            os_log("Heart rate quantityType not available", log: logger, type: .error)
            return
        }
        
        // Create a predicate for heart rate data from the Apple Watch
        let devicePredicate = HKQuery.predicateForObjects(from: [HKDevice.local()])
        
        // Create a heart rate query with a results handler
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: devicePredicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] (query, samples, deletedObjects, anchor, error) in
            guard let self = self, let samples = samples as? [HKQuantitySample] else {
                if let error = error {
                    os_log("Heart rate query error: %{public}@", log: self?.logger ?? OSLog.default, type: .error, error.localizedDescription)
                }
                return
            }
            
            // Process the most recent sample
            if let mostRecentSample = samples.last {
                let heartRate = mostRecentSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                self.heartRateData = heartRate
                os_log("Heart rate updated: %{public}.1f BPM", log: self.logger, type: .debug, heartRate)
            }
        }
        
        // Update handler called whenever new data is available
        query.updateHandler = { [weak self] (query, samples, deletedObjects, anchor, error) in
            guard let self = self, let samples = samples as? [HKQuantitySample] else {
                if let error = error {
                    os_log("Heart rate update error: %{public}@", log: self?.logger ?? OSLog.default, type: .error, error.localizedDescription)
                }
                return
            }
            
            // Process the most recent sample
            if let mostRecentSample = samples.last {
                let heartRate = mostRecentSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                self.heartRateData = heartRate
                os_log("Heart rate updated: %{public}.1f BPM", log: self.logger, type: .debug, heartRate)
            }
        }
        
        // Execute the query
        healthStore.execute(query)
        os_log("Heart rate monitoring started", log: logger, type: .info)
    }
    
    // Start sleep stage monitoring
    private func startSleepStageMonitoring() {
        // Sleep stage updates typically don't come as frequently as heart rate data
        // So we'll periodically query for the current sleep stage
        sleepMonitoringTimer = Timer.scheduledTimer(withTimeInterval: sleepStageCheckInterval, // Check every 30 seconds
                                                  repeats: true) { [weak self] _ in
            self?.checkCurrentSleepStage()
        }
        
        // Initial check
        checkCurrentSleepStage()
        os_log("Sleep stage monitoring started with interval: %{public}.1f seconds", log: logger, type: .info, sleepStageCheckInterval)
    }
    
    // Check current sleep stage
    private func checkCurrentSleepStage() {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            os_log("Sleep analysis category type not available", log: logger, type: .error)
            return
        }
        
        // Get data from the last 10 minutes
        let now = Date()
        let tenMinutesAgo = now.addingTimeInterval(-10 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: tenMinutesAgo, end: now, options: .strictStartDate)
        
        // Sort by end date descending to get most recent first
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        // Create the query
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: 10, // Limit to 10 samples
            sortDescriptors: [sortDescriptor]
        ) { [weak self] (query, samples, error) in
            guard let self = self, let samples = samples as? [HKCategorySample] else {
                if let error = error {
                    os_log("Sleep stage query error: %{public}@", log: self?.logger ?? OSLog.default, type: .error, error.localizedDescription)
                }
                return
            }
            
            // Process the samples to determine sleep stage
            self.processSleepStageSamples(samples)
        }
        
        // Execute the query
        healthStore.execute(query)
        os_log("Checking current sleep stage", log: logger, type: .debug)
    }
    
    // Process sleep stage samples
    private func processSleepStageSamples(_ samples: [HKCategorySample]) {
        guard !samples.isEmpty else {
            os_log("No sleep samples found", log: logger, type: .debug)
            return
        }
        
        // Default to unknown
        var detectedStage: SleepStage = .unknown
        
        // Look at the most recent sample
        for sample in samples {
            if #available(watchOS 9.0, *) {
                // In watchOS 9.0+, we can get more detailed sleep stages
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                    detectedStage = .deep
                    os_log("Deep sleep detected in HealthKit sample", log: logger, type: .info)
                    break
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    detectedStage = .rem
                    os_log("REM sleep detected in HealthKit sample", log: logger, type: .info)
                    break
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                    detectedStage = .light
                    os_log("Light sleep detected in HealthKit sample", log: logger, type: .info)
                    break
                case HKCategoryValueSleepAnalysis.awake.rawValue:
                    detectedStage = .awake
                    os_log("Awake state detected in HealthKit sample", log: logger, type: .info)
                    break
                default:
                    os_log("Unknown sleep value in HealthKit sample: %{public}d", log: logger, type: .debug, sample.value)
                    continue
                }
            } else {
                // In earlier watchOS versions, we only get asleep/awake
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleep.rawValue:
                    detectedStage = .light // Default to light sleep without more specifics
                    os_log("Asleep state detected in HealthKit sample (pre-watchOS 9)", log: logger, type: .info)
                    break
                case HKCategoryValueSleepAnalysis.awake.rawValue:
                    detectedStage = .awake
                    os_log("Awake state detected in HealthKit sample (pre-watchOS 9)", log: logger, type: .info)
                    break
                default:
                    os_log("Unknown sleep value in HealthKit sample: %{public}d", log: logger, type: .debug, sample.value)
                    continue
                }
            }
            
            if detectedStage != .unknown {
                break // Use the first valid sleep stage we find
            }
        }
        
        // Check if there's a change in sleep stage
        if detectedStage != lastSleepStage && detectedStage != .unknown {
            // Record the transition
            sleepStageTransitions.append((stage: detectedStage, timestamp: Date()))
            
            // Count deep sleep detections
            if detectedStage == .deep {
                deepSleepDetectionCount += 1
                os_log("Deep sleep detected! Count: %{public}d", log: logger, type: .info, deepSleepDetectionCount)
            }
            
            // Format timestamp for logging
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeString = formatter.string(from: Date())
            
            os_log("Sleep stage changed: %{public}@ -> %{public}@ at %{public}@",
                  log: logger, type: .info,
                  lastSleepStage.description,
                  detectedStage.description,
                  timeString)
            
            lastSleepStage = detectedStage
        }
        
        // Update our current sleep stage
        self.sleepStageData = detectedStage
    }
    
    // MARK: - Data Transfer
    
    // Send collected sensor data to iPhone
    private func sendSensorDataToPhone() {
        guard let session = session, session.isReachable, isCollecting else {
            if let unwrappedSession = session, !unwrappedSession.isReachable {
                os_log("Watch is not reachable to iPhone", log: logger, type: .fault)
            }
            return
        }
        
        // Prepare data package
        var dataPackage: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "accelerometer": accelerometerData
        ]
        
        // Add heart rate if available
        if let heartRate = heartRateData {
            dataPackage["heartRate"] = heartRate
        }
        
        // Add sleep stage data - use the integer rawValue for sending over WCSession
        dataPackage["sleepStage"] = sleepStageData.rawValue
        
        // Send data to phone
        session.sendMessage(dataPackage, replyHandler: { replyMessage in
            os_log("Received reply from iPhone: %{public}@", log: self.logger, type: .debug, replyMessage.description)
        }) { error in
            os_log("Error sending sensor data to phone: %{public}@", log: self.logger, type: .error, error.localizedDescription)
        }
        
        // Log sleep stage data transfer
        if sleepStageData != .unknown {
            os_log("Sent sleep stage data to iPhone: %{public}@", log: logger, type: .debug, sleepStageData.description)
            
            // Log additional detail if sending deep sleep
            if sleepStageData == .deep {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                let timeString = formatter.string(from: Date())
                os_log("Sent DEEP SLEEP data to iPhone at %{public}@", log: logger, type: .info, timeString)
            }
        }
        
        // Clear accelerometer buffer after sending
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
    
    // Required for WCSessionDelegate on iOS
    func sessionDidBecomeInactive(_ session: WCSession) {
        os_log("WCSession did become inactive", log: logger, type: .info)
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        os_log("WCSession did deactivate", log: logger, type: .info)
        session.activate()
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
    
    // Record messages received from iPhone
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // Log the message
        os_log("Received message from iPhone with reply handler: %{public}@", log: logger, type: .debug, message.description)
        
        // Process the message (same as above)
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
        
        // Send a reply
        replyHandler(["status": "received", "timestamp": Date().timeIntervalSince1970])
    }
}
