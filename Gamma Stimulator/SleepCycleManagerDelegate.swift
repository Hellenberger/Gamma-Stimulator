//
//  SleepCycleManager.swift
//  Gamma Stimulator
//

import Foundation
import CoreMotion
import HealthKit

protocol SleepCycleManagerDelegate: AnyObject {
    func sleepCycleManager(_ manager: SleepCycleManager, didStartStimulation: Bool)
    func sleepCycleManager(_ manager: SleepCycleManager, didStopStimulation: Bool)
    func sleepCycleManager(_ manager: SleepCycleManager, didDetectSleepStage stage: SleepStage)
    func sleepCycleManager(_ manager: SleepCycleManager, didDetectMorningWakeUp: Bool)
}

class SleepCycleManager: NSObject, PhoneWatchConnectorDelegate {
    
    override init() {
        super.init()
        setupSleepAnalyzer()
        phoneWatchConnector.delegate = self
        observeTimerNotifications()
        setupSleepAnalyzer()
        phoneWatchConnector.delegate = self
        
        print("SleepCycleManager initialized with real-time detection")
    }

    private func observeTimerNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(startStimFromTimer),
            name: NSNotification.Name("StartGammaStimulation"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stopStimFromTimer),
            name: NSNotification.Name("StopGammaStimulation"),
            object: nil
        )
    }

    @objc private func startStimFromTimer() {
        guard !stimulationActive else { return }
        stimulationActive = true
        delegate?.sleepCycleManager(self, didStartStimulation: true)
        print("Stimulation started from timer override")
    }

    @objc private func stopStimFromTimer() {
        guard stimulationActive else { return }
        stimulationActive = false
        delegate?.sleepCycleManager(self, didStopStimulation: true)
        print("Stimulation stopped from timer override")
    }

    // MARK: - Properties
    
    weak var delegate: SleepCycleManagerDelegate?
    
    // Components
    private let sleepAnalyzer = SleepAnalyzer()
    private let phoneWatchConnector = PhoneWatchConnector.shared
    
    // State tracking
    private(set) var monitoring = false
    private(set) var stimulationActive = false
    private(set) var currentSleepStage: SleepStage = .unknown
    private(set) var currentSleepCycle = 0
    private(set) var stimulationHistory: [Date] = []
    
    // Flag to track if the sleep analyzer is actively monitoring
    private var localAnalyzerActive = false
    
    // Configuration - UPDATED FOR REAL USAGE
    private let stimulationDuration: TimeInterval = 50 * 60 // 50 minutes (was 1 min for testing)
    private let minTimeBetweenStimulations: TimeInterval = 45 * 60 // 45 minutes (was 1 min for testing)
    private let maxCyclesToMonitor = 8 // Maximum number of sleep cycles to monitor
    
    // Timers
    private var stimulationTimer: Timer?
    private var watchConnectionCheckTimer: Timer?
    
    private func setupSleepAnalyzer() {
        // Set up the sleep analyzer delegate
        sleepAnalyzer.delegate = self
    }
    
    // MARK: - Public Methods
    
    // Method to check if monitoring is active (for external access)
    public func isMonitoring() -> Bool {
        return monitoring
    }
    
    // Method to access stimulation duration for testing
    public func getStimulationDuration() -> TimeInterval {
        return stimulationDuration
    }
    
    // Start monitoring sleep
    func startMonitoring() {
        guard !monitoring else { return }

        // Try to wake the Watch app
          PhoneWatchConnector.shared.wakeWatchApp()

        // Check Watch reachability every 10 s
        watchConnectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0,
                                                         repeats: true) { [weak self] _ in
            self?.checkWatchConnection()
        }

        if phoneWatchConnector.isWatchAppAvailable() {
            // Primary path – live data from the Watch
            phoneWatchConnector.startWatchMonitoring()
            print("Watch monitoring started")
        } else {
            // Fallback – on‑device motion analysis only
            sleepAnalyzer.startMonitoring()
            localAnalyzerActive = true
        }

        monitoring = true
        print("Sleep‑cycle monitoring started")
    }

    // Stop monitoring sleep
    func stopMonitoring() {
        guard monitoring else { return }
        
        // Stop Watch data collection
        if phoneWatchConnector.isWatchAppAvailable() {
            phoneWatchConnector.stopWatchMonitoring()
        }
        
        // Stop local sleep analyzer
        if localAnalyzerActive {
            sleepAnalyzer.stopMonitoring()
            localAnalyzerActive = false
        }
        
        // Stop Watch connection check
        watchConnectionCheckTimer?.invalidate()
        watchConnectionCheckTimer = nil
        
        // Stop any active stimulation
        stopStimulationIfActive()
        
        monitoring = false
        currentSleepCycle = 0
        stimulationHistory = []
        print("Sleep cycle monitoring stopped")
    }
    
    // MARK: - PhoneWatchConnectorDelegate
    
    func connector(_ connector: PhoneWatchConnector, didReceiveAccelerometerData data: [[String: Double]]) {
        // Process accelerometer data - can be used to enhance sleep detection
        // For now, we'll just use sleep stage data from the Watch
    }
    
    func connector(_ connector: PhoneWatchConnector, didReceiveHeartRate heartRate: Double) {
        // Update heart rate - can help with sleep stage determination
        sleepAnalyzer.updateHeartRate(heartRate)
        print("Received heart rate from Watch: \(heartRate) BPM")
    }
    
    func connector(_ connector: PhoneWatchConnector, didReceiveTemperature temperature: Double) {
        // Temperature data can be useful but is not critical for sleep stage detection
        print("Received temperature from Watch: \(temperature)°C")
    }
    
    func connector(_ connector: PhoneWatchConnector, didReceiveSleepStage stage: SleepStage) {
        // This is the key method for receiving sleep stage data from the Watch
        processSleepStageUpdate(stage)
        print("Received sleep stage from Watch: \(stage.description)")
    }
    
    func connectorDidChangeConnectionState(_ connector: PhoneWatchConnector) {
        // If the connection state changes, we need to adapt
        if connector.isWatchAppAvailable() {
            if monitoring {
                // Resume data collection on the Watch
                connector.startWatchMonitoring()
            }
        } else {
            // If Watch becomes unavailable, switch to local sleep detection
            if monitoring && !localAnalyzerActive {
                sleepAnalyzer.startMonitoring()
                localAnalyzerActive = true
            }
        }
    }

    private func checkWatchConnection() {
        let isWatchAvailable = phoneWatchConnector.isWatchAppAvailable()
        
        if isWatchAvailable {
            // If Watch just became available and local monitoring is active
            if localAnalyzerActive {
                sleepAnalyzer.stopMonitoring()
                localAnalyzerActive = false
                phoneWatchConnector.startWatchMonitoring()
            }
        } else {
            // If Watch just became unavailable and we're monitoring
            if monitoring && !localAnalyzerActive {
                sleepAnalyzer.startMonitoring()
                localAnalyzerActive = true
            }
        }
    }
    
    // Process sleep stage update from any source
    private func processSleepStageUpdate(_ stage: SleepStage) {
        // Update current stage
        if stage != currentSleepStage {
            currentSleepStage = stage
            
            // Notify delegate
            delegate?.sleepCycleManager(self, didDetectSleepStage: stage)
            
            // Handle deep sleep detection
            if stage == .deep {
                print("Deep sleep detected, checking if stimulation should start")
                handleDeepSleepDetected()
            }
        }
    }
    
    // Handle deep sleep detection
    private func handleDeepSleepDetected() {
        // Check if we should start stimulation
        if !stimulationActive && shouldStartStimulation() {
            startStimulation()
        }
    }
    
    // Determine if stimulation should start
    private func shouldStartStimulation() -> Bool {
        // Don't exceed maximum number of cycles
        if currentSleepCycle >= maxCyclesToMonitor {
            print("Maximum sleep cycles reached, not starting stimulation")
            return false
        }
        
        // Check if enough time has passed since last stimulation
        if let lastStimulation = stimulationHistory.last {
            let timeInterval = Date().timeIntervalSince(lastStimulation)
            if timeInterval < minTimeBetweenStimulations {
                print("Not enough time since last stimulation: \(timeInterval) seconds")
                return false
            }
        }
        
        print("Conditions met to start stimulation")
        return true
    }
    
    // Start stimulation
    private func startStimulation() {
        stimulationActive = true
        currentSleepCycle += 1
        stimulationHistory.append(Date())
        
        // Notify delegate
        delegate?.sleepCycleManager(self, didStartStimulation: true)
        
        print("Starting stimulation for cycle \(currentSleepCycle) with duration \(stimulationDuration) seconds")
        
        // Set timer to stop stimulation after the specified duration
        stimulationTimer = Timer.scheduledTimer(withTimeInterval: stimulationDuration,
                                               repeats: false) { [weak self] _ in
            self?.stopStimulationIfActive()
        }
    }
    
    // Stop stimulation if it's active
    private func stopStimulationIfActive() {
        guard stimulationActive else { return }
        
        stimulationActive = false
        stimulationTimer?.invalidate()
        stimulationTimer = nil
        
        // Notify delegate
        delegate?.sleepCycleManager(self, didStopStimulation: true)
        
        print("Stimulation stopped for cycle \(currentSleepCycle)")
    }
}

// MARK: - SleepAnalyzerDelegate Extension
extension SleepCycleManager: SleepAnalyzerDelegate {
    func sleepAnalyzer(_ analyzer: SleepAnalyzer, didDetectSleepStage stage: SleepStage) {
        // Update from local sleep analyzer - used when Watch is not available
        processSleepStageUpdate(stage)
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
}
