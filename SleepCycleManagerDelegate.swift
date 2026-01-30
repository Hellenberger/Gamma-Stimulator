import Foundation
import HealthKit
import CoreMotion

protocol SleepCycleManagerDelegate: AnyObject {
    func sleepCycleManager(_ manager: SleepCycleManager, didStartStimulation: Bool)
    func sleepCycleManager(_ manager: SleepCycleManager, didStopStimulation: Bool)
    func sleepCycleManager(_ manager: SleepCycleManager, didDetectSleepStage stage: SleepStage)
    func sleepCycleManager(_ manager: SleepCycleManager, didDetectMorningWakeUp: Bool)
}

class SleepCycleManager: SleepAnalyzerDelegate {
    
    // MARK: - Properties
    
    weak var delegate: SleepCycleManagerDelegate?
    
    // Components
    private let healthKitManager = HealthKitManager.shared
    private let sleepAnalyzer = SleepAnalyzer()
    
    // State tracking
    private(set) var isMonitoring = false
    private(set) var isStimulationActive = false
    private(set) var currentSleepStage: SleepStage = .unknown
    private(set) var currentSleepCycle = 0
    private(set) var stimulationHistory: [Date] = []
    
    // Configuration
    private let stimulationDuration: TimeInterval = 15 * 60 // 15 minutes
    private let minTimeBetweenStimulations: TimeInterval = 45 * 60 // 45 minutes
    private let maxCyclesToMonitor = 8 // Maximum number of sleep cycles to monitor
    
    // Timers
    private var stimulationTimer: Timer?
    private var heartRateUpdateTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        sleepAnalyzer.delegate = self
    }
    
    // MARK: - Public Methods
    
    // Start monitoring sleep
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        // Request HealthKit authorization if needed
        if healthKitManager.isHealthKitAvailable() {
            healthKitManager.requestAuthorization { [weak self] (success, error) in
                guard let self = self, success else {
                    if let error = error {
                        print("HealthKit authorization failed: \(error.localizedDescription)")
                    }
                    return
                }
                
                self.setupHeartRateUpdates()
                self.sleepAnalyzer.startMonitoring()
                self.isMonitoring = true
                print("Sleep cycle monitoring started")
            }
        } else {
            // If HealthKit is not available, just use motion data
            self.sleepAnalyzer.startMonitoring()
            self.isMonitoring = true
            print("Sleep cycle monitoring started without HealthKit")
        }
    }
    
    // Stop monitoring sleep
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        sleepAnalyzer.stopMonitoring()
        stopHeartRateUpdates()
        stopStimulationIfActive()
        
        isMonitoring = false
        currentSleepCycle = 0
        stimulationHistory = []
        print("Sleep cycle monitoring stopped")
    }
    
    // MARK: - SleepAnalyzerDelegate
    
    func sleepAnalyzer(_ analyzer: SleepAnalyzer, didDetectSleepStage stage: SleepStage) {
        // Update current stage
        currentSleepStage = stage
        
        // Notify delegate
        delegate?.sleepCycleManager(self, didDetectSleepStage: stage)
        
        // Handle deep sleep detection
        if stage == .deep {
            handleDeepSleepDetected()
        }
    }
    
    func sleepAnalyzer(_ analyzer: SleepAnalyzer, didDetectAwake isAwake: Bool) {
        if isAwake {
            // Morning wake up detected
            delegate?.sleepCycleManager(self, didDetectMorningWakeUp: true)
            
            // Stop monitoring after confirming it's morning
            DispatchQueue.main.asyncAfter(deadline: .now() + 5 * 60) { [weak self] in // 5 minute delay
                self?.stopMonitoring()
            }
        }
    }
    
    // MARK: - Private Methods
    
    // Setup periodic heart rate updates from HealthKit
    private func setupHeartRateUpdates() {
        heartRateUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateLatestHeartRate()
        }
    }
    
    // Stop heart rate updates
    private func stopHeartRateUpdates() {
        heartRateUpdateTimer?.invalidate()
        heartRateUpdateTimer = nil
    }
    
    // Fetch the latest heart rate from HealthKit
    private func updateLatestHeartRate() {
        // This is a simplified example - in a real app, you would implement
        // proper HealthKit queries to get the latest heart rate
        let mockHeartRate = 60.0 + Double.random(in: -5...5)
        sleepAnalyzer.updateHeartRate(mockHeartRate)
    }
    
    // Handle deep sleep detection
    private func handleDeepSleepDetected() {
        // Check if we should start stimulation
        if !isStimulationActive && shouldStartStimulation() {
            startStimulation()
        }
    }
    
    // Determine if stimulation should start
    private func shouldStartStimulation() -> Bool {
        // Don't exceed maximum number of cycles
        if currentSleepCycle >= maxCyclesToMonitor {
            return false
        }
        
        // Check if enough time has passed since last stimulation
        if let lastStimulation = stimulationHistory.last {
            let timeInterval = Date().timeIntervalSince(lastStimulation)
            if timeInterval < minTimeBetweenStimulations {
                return false
            }
        }
        
        return true
    }
    
    // Start stimulation
    private func startStimulation() {
        isStimulationActive = true
        currentSleepCycle += 1
        stimulationHistory.append(Date())
        
        // Notify delegate
        delegate?.sleepCycleManager(self, didStartStimulation: true)
        
        // Set timer to stop stimulation after the specified duration
        stimulationTimer = Timer.scheduledTimer(withTimeInterval: stimulationDuration, 
                                               repeats: false) { [weak self] _ in
            self?.stopStimulationIfActive()
        }
    }
    
    // Stop stimulation if it's active
    private func stopStimulationIfActive() {
        guard isStimulationActive else { return }
        
        isStimulationActive = false
        stimulationTimer?.invalidate()
        stimulationTimer = nil
        
        // Notify delegate
        delegate?.sleepCycleManager(self, didStopStimulation: true)
    }
}