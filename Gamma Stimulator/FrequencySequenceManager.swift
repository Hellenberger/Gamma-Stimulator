import Foundation

// MARK: - Session State (for persistence)
struct SessionState: Codable {
    let currentStepIndex: Int
    let remainingSeconds: TimeInterval
    let stepStartDate: Date
    let isRunning: Bool
    let isPaused: Bool
}

// MARK: - Manager Class

class FrequencySequenceManager {
    static let shared = FrequencySequenceManager()

    private(set) var steps: [FrequencyStep] = []
    private(set) var isRunning = false
    private(set) var isPaused = false

    weak var delegate: FrequencySequenceDelegate?

    private(set) var currentStepIndex = 0
    private var stepTimer: Timer?
    private var stepStartDate: Date?
    private var currentStepDuration: TimeInterval = 0

    private init() {}

    // MARK: - Step Management

    func addStep(_ step: FrequencyStep) {
        steps.append(step)
        saveSequence()
    }

    func removeStep(at index: Int) {
        guard index < steps.count else { return }
        steps.remove(at: index)
        saveSequence()
    }

    func updateStep(at index: Int, with step: FrequencyStep) {
        guard index < steps.count else { return }
        steps[index] = step
        saveSequence()
    }

    func clearSteps() {
        steps.removeAll()
        saveSequence()
    }

    func moveStep(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex < steps.count, destinationIndex <= steps.count else { return }
        let step = steps.remove(at: sourceIndex)
        steps.insert(step, at: destinationIndex)
        saveSequence()
    }

    func getTotalDuration() -> Int {
        let totalSeconds = steps.reduce(0.0) { $0 + $1.effectiveDurationSeconds }
        return Int(ceil(totalSeconds / 60.0))
    }

    // MARK: - Sequence Control

    func startSequence() {
        guard !steps.isEmpty else { return }

        isRunning = true
        isPaused = false
        currentStepIndex = 0

        NotificationCenter.default.post(name: .sequenceStarted, object: nil)
        playCurrentStep()
    }

    func pauseSequence() {
        guard isRunning else { return }
        isPaused = true
        stepTimer?.invalidate()
        saveSessionState()
        NotificationCenter.default.post(name: .sequencePaused, object: nil)
    }

    func resumeSequence() {
        guard isRunning && isPaused else { return }
        isPaused = false

        // Calculate remaining time for current step
        if let startDate = stepStartDate {
            let elapsed = Date().timeIntervalSince(startDate)
            let remaining = max(0, currentStepDuration - elapsed)
            if remaining > 0 {
                resumeCurrentStep(remainingTime: remaining)
            } else {
                currentStepIndex += 1
                playCurrentStep()
            }
        } else {
            playCurrentStep()
        }

        clearSessionState()
        NotificationCenter.default.post(name: .sequenceResumed, object: nil)
    }

    func stopSequence() {
        isRunning = false
        isPaused = false
        stepTimer?.invalidate()
        stepTimer = nil
        currentStepIndex = 0
        stepStartDate = nil
        clearSessionState()
        NotificationCenter.default.post(name: .sequenceStopped, object: nil)
    }

    private func playCurrentStep() {
        guard currentStepIndex < steps.count else {
            completeSequence()
            return
        }

        let step = steps[currentStepIndex]
        currentStepDuration = step.effectiveDurationSeconds
        stepStartDate = Date()

        // Notify delegate
        delegate?.frequencyChanged(to: step.frequency, stepIndex: currentStepIndex, totalSteps: steps.count)

        // Notify observers (useful for UI updates)
        NotificationCenter.default.post(
            name: .frequencyChanged,
            object: nil,
            userInfo: ["frequency": step.frequency]
        )

        // Schedule next step using effectiveDurationSeconds to account for Flow State ramp time
        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: currentStepDuration, repeats: false) { [weak self] _ in
            self?.currentStepIndex += 1
            self?.playCurrentStep()
        }

        saveSessionState()
    }

    private func resumeCurrentStep(remainingTime: TimeInterval) {
        guard currentStepIndex < steps.count else {
            completeSequence()
            return
        }

        let step = steps[currentStepIndex]

        // Notify delegate
        delegate?.frequencyChanged(to: step.frequency, stepIndex: currentStepIndex, totalSteps: steps.count)

        // Schedule with remaining time
        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
            self?.currentStepIndex += 1
            self?.playCurrentStep()
        }
    }

    private func completeSequence() {
        isRunning = false
        isPaused = false
        stepTimer?.invalidate()
        stepStartDate = nil
        clearSessionState()
        delegate?.sequenceCompleted()
        NotificationCenter.default.post(name: .sequenceCompleted, object: nil)
    }

    // MARK: - Sequence Persistence

    func saveSequence() {
        do {
            let data = try JSONEncoder().encode(steps)
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.savedSequence)
        } catch {
            print("Failed to save sequence: \(error)")
        }
    }

    func loadSequence() {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.savedSequence) else { return }
        do {
            self.steps = try JSONDecoder().decode([FrequencyStep].self, from: data)
        } catch {
            print("Failed to load sequence: \(error)")
        }
    }

    // MARK: - Session State Persistence

    private func saveSessionState() {
        guard isRunning, let startDate = stepStartDate else { return }

        let elapsed = Date().timeIntervalSince(startDate)
        let remaining = max(0, currentStepDuration - elapsed)

        let state = SessionState(
            currentStepIndex: currentStepIndex,
            remainingSeconds: remaining,
            stepStartDate: startDate,
            isRunning: isRunning,
            isPaused: isPaused
        )

        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.sessionState)
        } catch {
            print("Failed to save session state: \(error)")
        }
    }

    private func clearSessionState() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.sessionState)
    }

    /// Attempts to restore a previously saved session state
    /// Returns true if a session was restored
    @discardableResult
    func restoreSessionIfAvailable() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.sessionState) else {
            return false
        }

        do {
            let state = try JSONDecoder().decode(SessionState.self, from: data)

            // Only restore if we have steps and the saved state is valid
            guard !steps.isEmpty, state.currentStepIndex < steps.count else {
                clearSessionState()
                return false
            }

            // Check if too much time has passed (e.g., more than 1 hour)
            let timeSinceSave = Date().timeIntervalSince(state.stepStartDate)
            let maxRestoreTime: TimeInterval = 60 * 60 // 1 hour
            guard timeSinceSave < maxRestoreTime else {
                clearSessionState()
                return false
            }

            currentStepIndex = state.currentStepIndex
            isRunning = state.isRunning
            isPaused = true // Always restore as paused so user can choose to resume
            stepStartDate = state.stepStartDate
            currentStepDuration = steps[currentStepIndex].effectiveDurationSeconds

            return true
        } catch {
            print("Failed to restore session state: \(error)")
            clearSessionState()
            return false
        }
    }

    /// Returns remaining time in current step, or nil if not running
    var remainingTimeInCurrentStep: TimeInterval? {
        guard isRunning, let startDate = stepStartDate else { return nil }
        let elapsed = Date().timeIntervalSince(startDate)
        return max(0, currentStepDuration - elapsed)
    }
}

protocol FrequencySequenceDelegate: AnyObject {
    func frequencyChanged(to frequency: StimulationFrequency, stepIndex: Int, totalSteps: Int)
    func sequenceCompleted()
}
