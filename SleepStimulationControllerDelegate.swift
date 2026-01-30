import Foundation
import UIKit

protocol SleepStimulationControllerDelegate: AnyObject {
    // Called when stimulation should start
    func startStimulation(duration: TimeInterval)
    
    // Called when stimulation should stop
    func stopStimulation()
    
    // Called to update UI with current sleep state
    func didUpdateSleepState(stage: SleepStage, description: String)
}

class SleepStimulationController: NSObject, SleepStageDetectorDelegate {
    
    // MARK: - Properties
    
    weak var delegate: SleepStimulationControllerDelegate?
    
    // Sleep detector
    private let sleepDetector = SleepStageDetector()
    
    // Stimulation configuration
    private let stimulationDuration: TimeInterval = 15 * 60 // 15 minutes
    private let minTimeBetweenStimulations: TimeInterval = 45 * 60 // 45 minutes
    
    // State tracking
    private(set) var isMonitoring = false
    private(set) var isStimulationActive = false
    private(set) var currentSleepStage: SleepStage = .unknown
    private(set) var currentSleepCycle = 0
    private(set) var stimulationHistory: [Date] = []
    
    // Stimulation timer
    private var stimulationTimer: Timer?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        sleepDetector.delegate = self
    }
    
    // MARK: - Public Methods
    
    // Start sleep monitoring
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        // Reset state
        currentSleepCycle = 0
        stimulationHistory = []
        currentSleepStage = .unknown
        
        // Start sleep detection
        sleepDetector.startDetection()
        
        isMonitoring = true
        print("Sleep stimulation monitoring started")
    }
    
    // Stop sleep monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // Stop sleep detection
        sleepDetector.stopDetection()
        
        // Stop any active stimulation
        stopStimulationIfActive()
        
        isMonitoring = false
        print("Sleep stimulation monitoring stopped")
    }
    
    // MARK: - SleepStageDetectorDelegate
    
    func sleepStageDetector(_ detector: SleepStageDetector, didDetectStage stage: SleepStage) {
        // Update internal state
        currentSleepStage = stage
        
        // Notify delegate for UI updates
        delegate?.didUpdateSleepState(stage: stage, description: getStateDescription())
        
        // Handle deep sleep detection
        if stage == .deep {
            handleDeepSleepDetected()
        } else if isStimulationActive && stage != .deep {
            // If we've moved out of deep sleep during stimulation, consider stopping
            // This is optional - you might want to complete the full stimulation period regardless
            // stopStimulationIfActive()
        }
    }
    
    func sleepStageDetector(_ detector: SleepStageDetector, didUpdateStageConfidence confidence: Double) {
        // Could use confidence for UI updates if desired
    }
    
    func sleepStageDetector(_ detector: SleepStageDetector, didDetectAwakening isAwake: Bool) {
        if isAwake {
            // Morning wake up detected
            print("Morning awakening detected, stopping monitoring")
            
            // Stop any active stimulation
            stopStimulationIfActive()
            
            // Stop monitoring after a delay to confirm it's really morning
            DispatchQueue.main.asyncAfter(deadline: .now() + 5 * 60) { [weak self] in
                self?.stopMonitoring()
            }
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