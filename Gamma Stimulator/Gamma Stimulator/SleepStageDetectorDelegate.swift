//
//  SleepStageDetectorDelegate.swift
//  Gamma Stimulator
//
//  Created by Howard Ellenberger on 4/14/25.
//


//
//  SleepStageDetector.swift
//  Gamma Stimulator
//
//  Created by Howard Ellenberger on 4/14/25.
//

import Foundation
import CoreMotion

// Protocol for SleepStageDetector delegate
protocol SleepStageDetectorDelegate: AnyObject {
    func sleepStageDetector(_ detector: SleepStageDetector, didDetectStage stage: SleepStage)
    func sleepStageDetector(_ detector: SleepStageDetector, didUpdateStageConfidence confidence: Double)
    func sleepStageDetector(_ detector: SleepStageDetector, didDetectAwakening isAwake: Bool)
}

class SleepStageDetector {
    // Delegate
    weak var delegate: SleepStageDetectorDelegate?
    
    // Whether detection is running
    private var isRunning = false
    
    // Simulated detection timer
    private var detectionTimer: Timer?
    
    func forceTestCycle() {
        // Force a sequence of stages
        let testSequence: [SleepStage] = [.light, .deep, .light, .rem, .light]
        
        // Create a test cycle that goes through stages rapidly
        var index = 0
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if index < testSequence.count {
                let stage = testSequence[index]
                self.delegate?.sleepStageDetector(self, didDetectStage: stage)
                index += 1
            } else {
                // End of test cycle
                timer.invalidate()
            }
        }
    }
    // Start detection
    func startDetection() {
        guard !isRunning else { return }
        
        // Simulate sleep stage detection with a timer
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Simulate different sleep stages
            let stages: [SleepStage] = [.light, .deep, .rem, .light]
            let randomStage = stages.randomElement() ?? .light
            
            // Notify delegate
            DispatchQueue.main.async {
                self.delegate?.sleepStageDetector(self, didDetectStage: randomStage)
                
                // Simulate confidence level
                let confidence = Double.random(in: 0.5...0.95)
                self.delegate?.sleepStageDetector(self, didUpdateStageConfidence: confidence)
                
                // Occasionally simulate awakening (5% chance)
                if Double.random(in: 0...1) < 0.05 {
                    self.delegate?.sleepStageDetector(self, didDetectAwakening: true)
                }
            }
        }
        
        isRunning = true
    }
    
    // Stop detection
    func stopDetection() {
        detectionTimer?.invalidate()
        detectionTimer = nil
        isRunning = false
    }
}
