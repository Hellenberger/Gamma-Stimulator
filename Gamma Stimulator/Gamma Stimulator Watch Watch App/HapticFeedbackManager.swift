//
//  HapticFeedbackManager.swift
//  Gamma Stimulator
//
//  Created by Howard Ellenberger on 4/14/25.
//


import WatchKit
import Foundation

class HapticFeedbackManager {
    static let shared = HapticFeedbackManager()
    
    private var isRunning = false
    private var hapticTimer: Timer?
    
    // 40 Hz = vibration every 25ms (1000ms / 40)
    private let hapticInterval: TimeInterval = 0.025
    
    // Start haptic feedback at 40Hz
    func startHapticFeedback() {
        guard !isRunning else { return }
        
        isRunning = true
        
        // Create a timer that fires at 40Hz (every 25ms)
        hapticTimer = Timer.scheduledTimer(withTimeInterval: hapticInterval, 
                                          repeats: true) { [weak self] _ in
            self?.playHaptic()
        }
        
        // Add the timer to the common run loop mode
        if let timer = hapticTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    // Stop the haptic feedback
    func stopHapticFeedback() {
        hapticTimer?.invalidate()
        hapticTimer = nil
        isRunning = false
    }
    
    // Play a single haptic pulse
    private func playHaptic() {
        // Use the lightest haptic to avoid battery drain
        WKInterfaceDevice.current().play(.click)
    }
    
    // Check if haptic is running
    func isHapticRunning() -> Bool {
        return isRunning
    }
}