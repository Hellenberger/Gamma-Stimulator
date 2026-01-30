import Foundation
import CoreMotion
import HealthKit

// Sleep stages enumeration
enum SleepStage {
    case awake
    case light
    case deep
    case rem
    case unknown
    
    var description: String {
        switch self {
        case .awake: return "Awake"
        case .light: return "Light Sleep"
        case .deep: return "Deep Sleep (Slow Wave)"
        case .rem: return "REM Sleep"
        case .unknown: return "Unknown"
        }
    }
}

protocol SleepAnalyzerDelegate: AnyObject {
    func sleepAnalyzer(_ analyzer: SleepAnalyzer, didDetectSleepStage stage: SleepStage)
    func sleepAnalyzer(_ analyzer: SleepAnalyzer, didDetectAwake isAwake: Bool)
}

class SleepAnalyzer {
    
    // MARK: - Properties
    
    weak var delegate: SleepAnalyzerDelegate?
    
    // Motion manager for accelerometer data
    private let motionManager = CMMotionManager()
    
    // Data processing queues
    private let processingQueue = DispatchQueue(label: "com.sleepanalyzer.processing", qos: .userInitiated)
    
    // Analysis parameters
    private let motionThreshold: Double = 0.02  // Threshold for detecting significant motion
    private let deepSleepHeartRateDecreasePercent: Double = 10.0  // Percentage decrease from baseline for deep sleep
    private let deepSleepDetectionWindow: TimeInterval = 300.0  // 5 minutes of low movement for deep sleep detection
    private let deepSleepConfirmationPeriod: TimeInterval = 60.0  // 1 minute to confirm deep sleep
    
    // Analysis state
    private var isMonitoring = false
    private var currentSleepStage: SleepStage = .unknown
    private var baselineHeartRate: Double = 60.0
    private var movementBuffer: [Double] = []
    private var sleepStartTime: Date?
    private var lastSleepStageChangeTime: Date?
    private var lastDeepSleepDetectionTime: Date?
    private var potentialDeepSleepStartTime: Date?
    private var isAwakeDetected = false
    private var timeAwakeStarted: Date?
    private var isMorningWakeUpDetected = false
    
    // Timer for periodic analysis
    private var analysisTimer: Timer?
    
    // MARK: - Public Methods
    
    // Start sleep monitoring
    func startMonitoring() {
        guard !isMonitoring, motionManager.isAccelerometerAvailable else {
            print("Cannot start monitoring: already monitoring or accelerometer unavailable")
            return
        }
        
        // Reset state
        resetAnalysisState()
        
        // Start accelerometer
        motionManager.accelerometerUpdateInterval = 1.0 / 10.0  // 10 Hz sampling rate
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            self.processAccelerometerData(data)
        }
        
        // Start periodic analysis
        analysisTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.analyzeCurrentSleepState()
        }
        
        isMonitoring = true
        print("Sleep monitoring started")
    }
    
    // Stop sleep monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // Stop data collection
        motionManager.stopAccelerometerUpdates()
        
        // Stop analysis timer
        analysisTimer?.invalidate()
        analysisTimer = nil
        
        isMonitoring = false
        isMorningWakeUpDetected = false
        print("Sleep monitoring stopped")
    }
    
    // Update baseline heart rate (should be called regularly with heart rate data)
    func updateHeartRate(_ heartRate: Double) {
        // Only update baseline if we're not in deep sleep
        if currentSleepStage != .deep {
            baselineHeartRate = heartRate
        }
    }
    
    // MARK: - Private Methods
    
    // Reset analysis state
    private func resetAnalysisState() {
        currentSleepStage = .unknown
        movementBuffer = []
        sleepStartTime = nil
        lastSleepStageChangeTime = nil
        lastDeepSleepDetectionTime = nil
        potentialDeepSleepStartTime = nil
        isAwakeDetected = false
        timeAwakeStarted = nil
        isMorningWakeUpDetected = false
    }
    
    // Process accelerometer data
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Calculate magnitude of acceleration
            let magnitude = sqrt(pow(data.acceleration.x, 2) + 
                                pow(data.acceleration.y, 2) + 
                                pow(data.acceleration.z, 2))
            
            // Remove gravity component (approximately 1G)
            let movementMagnitude = abs(magnitude - 1.0)
            
            // Add to buffer (keep last 100 samples - 10 seconds at 10Hz)
            self.movementBuffer.append(movementMagnitude)
            if self.movementBuffer.count > 100 {
                self.movementBuffer.removeFirst()
            }
        }
    }
    
    // Analyze current sleep state based on collected data
    private func analyzeCurrentSleepState() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Calculate average movement
            let avgMovement = self.calculateAverageMovement()
            
            // Determine sleep stage based on movement and heart rate patterns
            let detectedStage = self.determineSleepStage(avgMovement: avgMovement)
            
            // Handle stage transitions
            if detectedStage != self.currentSleepStage {
                self.handleSleepStageTransition(from: self.currentSleepStage, to: detectedStage)
            }
            
            // Check for morning wake up
            self.checkForMorningWakeUp(currentStage: detectedStage, avgMovement: avgMovement)
        }
    }
    
    // Calculate average movement from the buffer
    private func calculateAverageMovement() -> Double {
        guard !movementBuffer.isEmpty else { return 0.0 }
        return movementBuffer.reduce(0.0, +) / Double(movementBuffer.count)
    }
    
    // Determine sleep stage based on movement and heart rate
    private func determineSleepStage(avgMovement: Double) -> SleepStage {
        let now = Date()
        
        // High movement indicates being awake
        if avgMovement > motionThreshold * 3.0 {
            if !isAwakeDetected {
                isAwakeDetected = true
                timeAwakeStarted = now
            }
            return .awake
        }
        
        // If previously detected as awake, require 5 minutes of low movement to transition out
        if isAwakeDetected {
            guard let awakeStartTime = timeAwakeStarted,
                  now.timeIntervalSince(awakeStartTime) >= 300 else {
                return .awake
            }
            isAwakeDetected = false
        }
        
        // Very low movement could indicate deep sleep
        if avgMovement < motionThreshold / 2.0 {
            if potentialDeepSleepStartTime == nil {
                potentialDeepSleepStartTime = now
            } 
            else if let startTime = potentialDeepSleepStartTime,
                    now.timeIntervalSince(startTime) >= deepSleepConfirmationPeriod {
                // We've been in low movement state long enough to consider this deep sleep
                return .deep
            }
        } else {
            // Reset potential deep sleep timer if movement exceeds threshold
            potentialDeepSleepStartTime = nil
        }
        
        // Default to light sleep if we can't determine a specific stage
        return .light
    }
    
    // Handle transitions between sleep stages
    private func handleSleepStageTransition(from oldStage: SleepStage, to newStage: SleepStage) {
        let now = Date()
        
        // Only change stage if we've been in the current stage for at least 2 minutes
        // This prevents rapid fluctuations
        if let lastChange = lastSleepStageChangeTime, 
           now.timeIntervalSince(lastChange) < 120, 
           oldStage != .unknown {
            return
        }
        
        // Record the transition
        lastSleepStageChangeTime = now
        
        if oldStage == .unknown && newStage != .awake {
            // First non-awake stage - record sleep start time
            sleepStartTime = now
        }
        
        if newStage == .deep {
            lastDeepSleepDetectionTime = now
        }
        
        // Update state and notify delegate on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentSleepStage = newStage
            self.delegate?.sleepAnalyzer(self, didDetectSleepStage: newStage)
        }
    }
    
    // Check if the user appears to be awake for morning
    private func checkForMorningWakeUp(currentStage: SleepStage, avgMovement: Double) {
        guard !isMorningWakeUpDetected, let sleepStart = sleepStartTime else { return }
        
        let now = Date()
        let timeSlept = now.timeIntervalSince(sleepStart)
        
        // Check if enough time has passed (at least 3 hours of sleep)
        guard timeSlept >= 3 * 3600 else { return }
        
        // Look for sustained wake period after sleep
        if currentStage == .awake && avgMovement > motionThreshold * 2.0 {
            if let awakeStartTime = timeAwakeStarted,
               now.timeIntervalSince(awakeStartTime) >= 600 { // 10 minutes of wakefulness
                
                isMorningWakeUpDetected = true
                
                // Notify delegate of morning wake-up on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.sleepAnalyzer(self, didDetectAwake: true)
                }
            }
        }
    }
}