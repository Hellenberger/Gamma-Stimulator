//
//  SleepStimulationController.swift
//  Gamma Stimulator
//

import Foundation
import UIKit

class SleepStimulationController {
    
    // MARK: - Properties
    
    weak var delegate: SleepStimulationControllerDelegate?
    
    // Configuration - MODIFIED FOR REAL USAGE
    private let stimulationDuration: TimeInterval = 15 * 60 // 15 minutes for real usage
    private let minTimeBetweenStimulations: TimeInterval = 45 * 60 // 45 minutes for real usage
    
    // State tracking
    private(set) var isMonitoring = false
    private(set) var isStimulationActive = false
    private(set) var currentSleepStage: SleepStage = .unknown
    private(set) var currentSleepCycle = 0
    private(set) var stimulationHistory: [Date] = []
    private let sleepDetector = SleepStageDetector()
    
    // Stimulation timer
    private var stimulationTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        print("SleepStimulationController initialized with real-time detection")
        // Register for sleep stage notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSleepStageUpdate),
            name: NSNotification.Name("SleepStageUpdate"),
            object: nil
        )
        
        // Register for direct stimulation trigger notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStimulationTrigger),
            name: NSNotification.Name("StimulationTrigger"),
            object: nil
        )
    }
    
    deinit {
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods

    // Start sleep monitoring
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        // Reset state
        currentSleepCycle = 0
        stimulationHistory = []
        currentSleepStage = .unknown
        
        isMonitoring = true
        print("Sleep stimulation monitoring started")
    }
    
    // Stop sleep monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // Stop any active stimulation
        stopStimulationIfActive()
        
        isMonitoring = false
        currentSleepCycle = 0
        stimulationHistory = []
        print("Sleep stimulation monitoring stopped")
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleSleepStageUpdate(_ notification: Notification) {
        guard isMonitoring, let userInfo = notification.userInfo,
              let stageRawValue = userInfo["stage"] as? Int,
              let stage = SleepStage(rawValue: stageRawValue) else {
            return
        }
        
        // Update current sleep stage
        currentSleepStage = stage
        
        // Notify delegate
        delegate?.didUpdateSleepState(stage: stage, description: getStateDescription())
        
        // If deep sleep is detected, handle it
        if stage == .deep {
            handleDeepSleepDetected()
        }
        
        print("Sleep stage updated to: \(stage.description)")
    }
    
    @objc private func handleStimulationTrigger(_ notification: Notification) {
        guard isMonitoring, !isStimulationActive else {
            return
        }
        
        print("Received direct stimulation trigger notification")
        
        // Check if we should start stimulation
        if shouldStartStimulation() {
            startStimulation()
        }
    }
    
    // MARK: - Private Methods
    
    // Get description of current sleep state
    private func getStateDescription() -> String {
        let stage = currentSleepStage.description
        
        if isStimulationActive {
            return "\(stage) - Stimulation Active (Cycle \(currentSleepCycle))"
        } else {
            return stage
        }
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
    
    // Start stimulation cycle
    private func startStimulation() {
        guard !isStimulationActive else { return }
        
        isStimulationActive = true
        currentSleepCycle += 1
        stimulationHistory.append(Date())
        
        // Notify delegate to start stimulation
        delegate?.startStimulation(duration: stimulationDuration)
        
        // Set timer to stop stimulation after the specified duration
        stimulationTimer = Timer.scheduledTimer(withTimeInterval: stimulationDuration,
                                               repeats: false) { [weak self] _ in
            self?.stopStimulationIfActive()
        }
        
        // Update UI
        delegate?.didUpdateSleepState(stage: currentSleepStage, description: getStateDescription())
        
        print("Stimulation started for cycle \(currentSleepCycle) with duration \(stimulationDuration) seconds")
    }
    
    // Stop stimulation if active
    private func stopStimulationIfActive() {
        guard isStimulationActive else { return }
        
        isStimulationActive = false
        stimulationTimer?.invalidate()
        stimulationTimer = nil
        
        // Notify delegate to stop stimulation
        delegate?.stopStimulation()
        
        // Update UI
        delegate?.didUpdateSleepState(stage: currentSleepStage, description: getStateDescription())
        
        print("Stimulation stopped for cycle \(currentSleepCycle)")
    }
}
