// StimulationTimerManager.swift (Fixed - Start delay only once)

import Foundation

enum TimerPhase {
    case startDelay
    case stimulation
    case rest
    case completed
}

protocol StimulationTimerManagerDelegate: AnyObject {
    func timerUpdate(secondsRemaining: Int, phase: TimerPhase, currentCycle: Int, totalCycles: Int)
    func timerCompletedAllCycles()
}

class StimulationTimerManager {
    static let shared = StimulationTimerManager()

    private var currentPhase: TimerPhase = .completed
    private var phaseRemaining: TimeInterval = 0
    private var phaseTimer: Timer?
    weak var delegate: StimulationTimerManagerDelegate?

    // User settings (in minutes)
    private(set) var startDelayMinutes: Int = 0
    private(set) var stimulationDurationMinutes: Int = 0
    private(set) var restDurationMinutes: Int = 0
    private(set) var totalCycles: Int = 0

    // Internal state
    private var currentCycle = 0
    private var isStimulating = false
    private var hasCompletedInitialDelay = false

    private let userDefaults = UserDefaults.standard

    
    // MARK: - Configuration
    func configureTimer(startDelay: Int, stimulationDuration: Int, restDuration: Int, cycles: Int) {
        self.startDelayMinutes = startDelay
        self.stimulationDurationMinutes = stimulationDuration
        self.restDurationMinutes = restDuration
        self.totalCycles = cycles
        saveSettings()
    }

    // MARK: - Start / Stop
    func start() {
        cancel()
        currentCycle = 0
        hasCompletedInitialDelay = false
        currentPhase = .startDelay
        phaseRemaining = TimeInterval(startDelayMinutes * 60)
        
        print("[TimerManager] Starting timer sequence")
        print("[TimerManager] Initial delay: \(startDelayMinutes) minutes")
        
        startPhaseCountdown()
    }

    func cancel() {
        phaseTimer?.invalidate()
        phaseTimer = nil
        currentPhase = .completed
        currentCycle = 0
        isStimulating = false
        hasCompletedInitialDelay = false
        
        // Ensure stimulation is stopped
        NotificationCenter.default.post(name: NSNotification.Name("StopGammaStimulation"), object: nil)
    }

    var isRunning: Bool {
        return phaseTimer != nil
    }

    // MARK: - Phase Management
    private func startPhaseCountdown() {
        phaseTimer?.invalidate()
        
        print("[TimerManager] Starting phase: \(currentPhase), duration: \(Int(phaseRemaining)) seconds")
        
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.phaseRemaining -= 1
            
            // Update delegate with current cycle (show cycle 0 during initial delay)
            let displayCycle = self.currentPhase == .startDelay ? 0 : self.currentCycle
            
            self.delegate?.timerUpdate(
                secondsRemaining: Int(self.phaseRemaining),
                phase: self.currentPhase,
                currentCycle: displayCycle,
                totalCycles: self.totalCycles
            )

            if self.phaseRemaining <= 0 {
                self.transitionToNextPhase()
            }
        }
    }

    private func transitionToNextPhase() {
        print("[TimerManager] Transitioning from phase: \(currentPhase)")
        
        switch currentPhase {
        case .startDelay:
            // After initial delay, start the first stimulation
            hasCompletedInitialDelay = true
            currentCycle = 1
            currentPhase = .stimulation
            phaseRemaining = TimeInterval(stimulationDurationMinutes * 60)
            startStimulation()

        case .stimulation:
            // After stimulation, go to rest
            stopStimulation()
            
            // Check if we've completed all cycles
            if currentCycle >= totalCycles {
                endTimer()
                return
            } else {
                currentPhase = .rest
                phaseRemaining = TimeInterval(restDurationMinutes * 60)
            }

        case .rest:
            // After rest, go to next stimulation
            currentCycle += 1
            currentPhase = .stimulation
            phaseRemaining = TimeInterval(stimulationDurationMinutes * 60)
            startStimulation()

        case .completed:
            break
        }

        if currentPhase != .completed {
            startPhaseCountdown()
        }
    }

    private func endTimer() {
        print("[TimerManager] All cycles completed")
        phaseTimer?.invalidate()
        phaseTimer = nil
        currentPhase = .completed
        stopStimulation() // Ensure stimulation is stopped
        delegate?.timerCompletedAllCycles()
    }

    // MARK: - Actions
    private func startStimulation() {
        isStimulating = true
        print("[TimerManager] Starting stimulation for cycle \(currentCycle)/\(totalCycles)")
        NotificationCenter.default.post(name: NSNotification.Name("StartGammaStimulation"), object: nil)
    }

    private func stopStimulation() {
        if isStimulating {
            isStimulating = false
            print("[TimerManager] Stopping stimulation")
            NotificationCenter.default.post(name: NSNotification.Name("StopGammaStimulation"), object: nil)
        }
    }

    // MARK: - Persistence
    func saveSettings() {
        userDefaults.set(startDelayMinutes, forKey: "startDelayMinutes")
        userDefaults.set(stimulationDurationMinutes, forKey: "stimulationDurationMinutes")
        userDefaults.set(restDurationMinutes, forKey: "restDurationMinutes")
        userDefaults.set(totalCycles, forKey: "totalCycles")
    }

    func loadSettings() {
        startDelayMinutes = userDefaults.integer(forKey: "startDelayMinutes")
        stimulationDurationMinutes = userDefaults.integer(forKey: "stimulationDurationMinutes")
        restDurationMinutes = userDefaults.integer(forKey: "restDurationMinutes")
        totalCycles = userDefaults.integer(forKey: "totalCycles")
        
        // Set defaults if nothing saved
        if startDelayMinutes == 0 && stimulationDurationMinutes == 0 {
            startDelayMinutes = 90
            stimulationDurationMinutes = 15
            restDurationMinutes = 75
            totalCycles = 5
        }
    }

    func updateDisplay() {
        let displayCycle = currentPhase == .startDelay ? 0 : currentCycle
        delegate?.timerUpdate(
            secondsRemaining: Int(phaseRemaining),
            phase: currentPhase,
            currentCycle: displayCycle,
            totalCycles: totalCycles
        )
    }

    func adjustForBackgroundTime(_ elapsed: TimeInterval) {
        guard elapsed >= 0 else { return }
        phaseRemaining -= elapsed
        if phaseRemaining <= 0 {
            transitionToNextPhase()
        } else {
            startPhaseCountdown()
        }
    }
    
    // Helper method to get total session duration
    func getTotalSessionDuration() -> TimeInterval {
        let initialDelay = TimeInterval(startDelayMinutes * 60)
        let cycleTime = TimeInterval((stimulationDurationMinutes + restDurationMinutes) * 60)
        // Subtract one rest period since the last cycle doesn't need rest after it
        let totalCycleTime = cycleTime * TimeInterval(totalCycles) - TimeInterval(restDurationMinutes * 60)
        return initialDelay + totalCycleTime
    }
    
    // Debug info
    func getSessionInfo() -> String {
        let totalMinutes = Int(getTotalSessionDuration() / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        return """
        Session Configuration:
        - Initial delay: \(startDelayMinutes) min
        - Stimulation: \(stimulationDurationMinutes) min × \(totalCycles) cycles
        - Rest between: \(restDurationMinutes) min
        - Total duration: \(hours)h \(minutes)min
        """
    }
}
