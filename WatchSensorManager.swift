import Foundation
import WatchKit
import CoreMotion
import HealthKit
import WatchConnectivity

class WatchSensorManager: NSObject, WCSessionDelegate {
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
    private let dataTransferInterval: TimeInterval = 1.0 // Send data every second
    
    // Data buffers
    private var accelerometerData: [[String: Double]] = []
    private var heartRateData: Double?
    private var temperatureData: Double?
    
    // Data collection state
    private var isCollecting = false
    private var dataTransferTimer: Timer?
    
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
    
    // Request authorization for health data
    func requestHealthAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        // Define the types of data we want to read
        let types: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: types) { success, error in
            completion(success, error)
        }
    }
    
    // MARK: - Data Collection
    
    // Start collecting sensor data
    func startDataCollection() {
        guard !isCollecting else { return }
        
        // Start accelerometer updates
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = accelerometerUpdateInterval
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
                guard let self = self, let data = data else { return }
                self.processAccelerometerData(data)
            }
        }
        
        // Start heart rate monitoring
        startHeartRateMonitoring()
        
        // Start temperature monitoring if available
        startTemperatureMonitoring()
        
        // Start periodic data transfer
        dataTransferTimer = Timer.scheduledTimer(withTimeInterval: dataTransferInterval, 
                                                repeats: true) { [weak self] _ in
            self?.sendSensorDataToPhone()
        }
        
        isCollecting = true
        print("Watch sensor data collection started")
    }
    
    // Stop collecting sensor data
    func stopDataCollection() {
        guard isCollecting else { return }
        
        // Stop accelerometer updates
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
        
        // Stop data transfer timer
        dataTransferTimer?.invalidate()
        dataTransferTimer = nil
        
        // Clear buffers
        accelerometerData.removeAll()
        heartRateData = nil
        temperatureData = nil
        
        isCollecting = false
        print("Watch sensor data collection stopped")
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
            guard let samples = samples as? [HKQuantitySample] else {
                return
            }
            
            // Process the most recent sample
            if let mostRecentSample = samples.last {
                let heartRate = mostRecentSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                self?.heartRateData = heartRate
            }
        }
        
        // Update handler called whenever new data is available
        query.updateHandler = { [weak self] (query, samples, deletedObjects, anchor, error) in
            guard let samples = samples as? [HKQuantitySample] else {
                return
            }
            
            // Process the most recent sample
            if let mostRecentSample = samples.last {
                let heartRate = mostRecentSample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                self?.heartRateData = heartRate
            }
        }
        
        // Execute the query
        healthStore.execute(query)
    }
    
    // Start temperature monitoring
    private func startTemperatureMonitoring() {
        guard let temperatureType = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else {
            return
        }
        
        // Create a predicate for temperature data from the Apple Watch
        let devicePredicate = HKQuery.predicateForObjects(from: [HKDevice.local()])
        
        // Create a temperature query
        let query = HKAnchoredObjectQuery(
            type: temperatureType,
            predicate: devicePredicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] (query, samples, deletedObjects, anchor, error) in
            guard let samples = samples as? [HKQuantitySample] else {
                return
            }
            
            // Process the most recent sample
            if let mostRecentSample = samples.last {
                let temperature = mostRecentSample.quantity.doubleValue(for: HKUnit.degreeCelsius())
                self?.temperatureData = temperature
            }
        }
        
        // Update handler
        query.updateHandler = { [weak self] (query, samples, deletedObjects, anchor, error) in
            guard let samples = samples as? [HKQuantitySample] else {
                return
            }
            
            // Process the most recent sample
            if let mostRecentSample = samples.last {
                let temperature = mostRecentSample.quantity.doubleValue(for: HKUnit.degreeCelsius())
                self?.temperatureData = temperature
            }
        }
        
        // Execute the query
        healthStore.execute(query)
    }
    
    // MARK: - Data Transfer
    
    // Send collected sensor data to iPhone
    private func sendSensorDataToPhone() {
        guard let session = session, session.isReachable, isCollecting else {
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
        
        // Add temperature if available
        if let temperature = temperatureData {
            dataPackage["temperature"] = temperature
        }
        
        // Send data to phone
        session.sendMessage(dataPackage, replyHandler: nil) { error in
            print("Error sending sensor data to phone: \(error.localizedDescription)")
        }
        
        // Clear accelerometer buffer after sending
        accelerometerData.removeAll()
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
            return
        }
        
        print("WCSession activated with state: \(activationState.rawValue)")
    }
    
    // Required for WCSessionDelegate conformance
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Handle messages from iPhone
        if let command = message["command"] as? String {
            switch command {
            case "startCollection":
                DispatchQueue.main.async {
                    self.startDataCollection()
                }
            case "stopCollection":
                DispatchQueue.main.async {
                    self.stopDataCollection()
                }
            default:
                break
            }
        }
    }
}