//
//  SleepStimulationController.swift
//  Gamma Stimulator
//
//  Created by Howard Ellenberger on 4/14/25.
//


import Foundation
import UIKit

class SleepStimulationController {
    
    // MARK: - Properties
    
    weak var delegate: SleepStimulationControllerDelegate?
    
    // Configuration
    private let stimulationDuration: TimeInterval = 15 * 60 // 15 minutes
    private let minTimeBetweenStimulations: TimeInterval = 45 * 60 // 45 minutes
    
    // State tracking
    private(set) var isMonitoring = false
    private(set) var isStimulationActive = false
    private(set) var currentSleepStage: SleepStage = .unknown
    private(set) var currentSleepCycle = 0
    private(set) var stimulationHistory: [Date] = []
    private let sleepDetector = SleepStageDetector()

    
    // Stimulation timer
    private var stimulationTimer: Timer?
    
    // MARK: - Public Methods
    
    func runTestCycle() {
        // Make sure monitoring is active
        if !isMonitoring {
            startMonitoring()
        }
        
        // Force a sleep stage sequence
        // This will call through to SleepStageDetector
        sleepDetector.forceTestCycle()
    }
    
    
    // Start sleep monitoring
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        // Simulate sleep stage detection for now
        // In a real implementation, this would connect to Apple Watch data
        simulateSleepStages()
        
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
    
    // MARK: - Private Methods
    
    // TEMPORARY: Simulate sleep stage detection for testing
    private func simulateSleepStages() {
        // Create a repeating timer to simulate sleep stage changes
        // This would be replaced by actual detection logic in the real implementation
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] timer in
            guard let self = self, self.isMonitoring else {
                timer.invalidate()
                return
            }
            
            // Simulate sleep stage changes
            let stages: [SleepStage] = [.light, .deep, .rem, .light]
            let randomStage = stages.randomElement() ?? .light
            
            // Update state
            self.currentSleepStage = randomStage
            
            // Notify delegate
            self.delegate?.didUpdateSleepState(stage: randomStage, description: self.getStateDescription())
            
            // If deep sleep is detected, handle it
            if randomStage == .deep {
                self.handleDeepSleepDetected()
            }
        }
    }
    
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
                return false
            }
        }
        
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
        
        print("Stimulation started for cycle \(currentSleepCycle)")
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
