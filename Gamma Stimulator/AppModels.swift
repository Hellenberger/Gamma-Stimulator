//
//  AppModels.swift
//  Gamma Stimulator
//
//  Created by Howard Ellenberger on 11/21/25.
//

import Foundation
import AVFoundation

// MARK: - Notification Names
extension Notification.Name {
    static let sequenceStarted = Notification.Name("SequenceStarted")
    static let sequencePaused = Notification.Name("SequencePaused")
    static let sequenceResumed = Notification.Name("SequenceResumed")
    static let sequenceStopped = Notification.Name("SequenceStopped")
    static let sequenceCompleted = Notification.Name("SequenceCompleted")
    static let frequencyChanged = Notification.Name("FrequencyChanged")
    static let startFrequencySequence = Notification.Name("StartFrequencySequence")
    static let audioInterrupted = Notification.Name("AudioInterrupted")
    static let audioInterruptionEnded = Notification.Name("AudioInterruptionEnded")
}

// MARK: - UserDefaults Keys
enum UserDefaultsKey {
    static let safetyConsentGiven = "SafetyConsentGiven"
    static let safetyConsentDate = "SafetyConsentDate"
    static let savedSequence = "savedSequence"
    static let selectedFrequency = "selectedFrequency"
    static let lastBackgroundDate = "LastBackgroundDate"
    static let sessionState = "SessionState"
}

// MARK: - Safety Manager
class SafetyManager {
    static let shared = SafetyManager()

    private init() {}

    var hasUserConsented: Bool {
        return UserDefaults.standard.bool(forKey: UserDefaultsKey.safetyConsentGiven)
    }

    func recordConsent() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.safetyConsentGiven)
        UserDefaults.standard.set(Date(), forKey: UserDefaultsKey.safetyConsentDate)
    }

    func revokeConsent() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKey.safetyConsentGiven)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.safetyConsentDate)
    }

    static let warningTitle = "Important Safety Information"

    static let warningMessage = """
    This app produces flashing lights and visual stimulation that may trigger seizures in people with photosensitive epilepsy.

    ⚠️ DO NOT USE if you or anyone in your family has a history of epilepsy or seizures.

    ⚠️ STOP IMMEDIATELY if you experience dizziness, altered vision, eye or muscle twitches, loss of awareness, disorientation, or any involuntary movement.

    ⚠️ Frequencies between 15-25 Hz pose the highest risk.

    By continuing, you acknowledge these risks and confirm you do not have photosensitive epilepsy.
    """
}

// MARK: - Audio Route Detection
class AudioRouteManager {
    static let shared = AudioRouteManager()

    private init() {}

    /// Returns true if headphones (wired or Bluetooth) are connected
    var isHeadphonesConnected: Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        for output in route.outputs {
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay:
                return true
            default:
                continue
            }
        }
        return false
    }

    /// Returns true if using built-in speaker
    var isUsingSpeaker: Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        for output in route.outputs {
            if output.portType == .builtInSpeaker {
                return true
            }
        }
        return false
    }

    static let headphoneWarningTitle = "Headphones Recommended"

    static let headphoneWarningMessage = """
    Binaural beats require stereo headphones to work properly.

    Each ear must receive a different frequency to create the "beat" perception in your brain. Speaker playback mixes both channels, eliminating the binaural effect.

    For best results, please use wired or wireless headphones.
    """
}

// MARK: - Stimulation Frequency Enum
enum StimulationFrequency: Int, Codable {
    case delta = 2
    case theta = 6
    case alpha = 10
    case flowState = 8  // 8 Hz target with built-in ramp program (binaural-only)
    case beta = 17
    case gamma = 40
    case binaural = -1  // Represents 0.5 Hz Epsilon/Slow Delta
    
    var name: String {
        switch self {
        case .delta: return "Delta"
        case .theta: return "Theta"
        case .alpha: return "Alpha"
        case .flowState: return "Flow State"
        case .beta: return "Beta"
        case .gamma: return "Gamma"
        case .binaural: return "Resonate Binaural"
        }
    }
    
    var isBinauralOnly: Bool { self == .binaural || self == .flowState }

    var period: TimeInterval {
        if self == .binaural { return 2.0 } // 0.5 Hz
        // For Flow State the *target* beat is 8 Hz (the ramp varies over time).
        if self == .flowState { return 1.0 / 8.0 }
        return 1.0 / Double(self.rawValue)
    }
    
    var onDuration: TimeInterval { return period / 2.0 }
    var offDuration: TimeInterval { return period / 2.0 }
    
    var timingDescription: String {
        if self == .binaural { return "Resonate Binaural: Variable Beat" }
        if self == .flowState {
            return "Flow State: 14→12→10→8 Hz ramp (3.5m/3m/2m), then hold at 8 Hz"
        }
        let onMs = onDuration * 1000
        let offMs = offDuration * 1000
        return "\(name) (\(rawValue)Hz): \(String(format: "%.1f", onMs))ms on, \(String(format: "%.1f", offMs))ms off"
    }
}

// MARK: - Stimulation Mode Enum
enum StimulationMode: Int, Codable {
    case both = 0
    case lightOnly = 1
    case audioOnly = 2
    
    var label: String {
        switch self {
        case .both: return "Light & Audio"
        case .lightOnly: return "Light Only"
        case .audioOnly: return "Audio Only"
        }
    }
    
    var icon: String {
        switch self {
        case .both: return "bolt.horizontal.circle.fill"
        case .lightOnly: return "sun.max.fill"
        case .audioOnly: return "speaker.wave.2.fill"
        }
    }
}

// MARK: - Frequency Step Struct
struct FrequencyStep: Codable {
    let frequency: StimulationFrequency
    let durationMinutes: Int
    let isBinaural: Bool
    var mode: StimulationMode = .both
    
    var id: UUID = UUID()
    
    var description: String {
        let type = isBinaural ? "Binaural" : "Standard"
        return "\(frequency.name) (\(type)) - \(durationMinutes) min - \(mode.label)"
    }

    // Flow State ramp: 14→12 (3.5m), 12→10 (3m), 10→8 (2m) = 8.5 minutes total.
    static let flowStateRampSeconds: TimeInterval = (3.5 * 60.0) + (3.0 * 60.0) + (2.0 * 60.0)

    /// Total runtime for this step (including any built-in ramps).
    var effectiveDurationSeconds: TimeInterval {
        var seconds = TimeInterval(durationMinutes) * 60.0
        if isBinaural && frequency == .flowState {
            seconds += Self.flowStateRampSeconds
        }
        return seconds
    }

    /// Duration rounded up to whole minutes for UI summaries.
    var effectiveDurationMinutesRoundedUp: Int {
        return Int(ceil(effectiveDurationSeconds / 60.0))
    }
}
