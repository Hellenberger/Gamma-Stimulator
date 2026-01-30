//
//  BinauralBeatGenerator.swift
//  Gamma Stimulator
//

import Foundation
import UIKit           // for CADisplayLink
import AVFoundation

protocol BinauralBeatGeneratorDelegate: AnyObject {
    func binauralBeatGeneratorDidTriggerLightPulse()
    func binauralBeatGeneratorDidReleaseLightPulse()
}

class BinauralBeatGenerator {
    // MARK: - Properties
    weak var delegate: BinauralBeatGeneratorDelegate?

    // Audio engine components
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var audioFormat: AVAudioFormat?

    // Waveform generation
    private let sampleRate: Double = 48000.0  // Keep this constant

    // Primary carrier frequencies
    private var leftFrequency: Double = 200.0   // Hz - LEFT ear only
    private var rightFrequency: Double = 200.5  // Hz - RIGHT ear only

    // Secondary carrier frequencies (for dual-carrier mode)
    private var leftFrequency2: Double = 400.0   // Hz - LEFT ear only
    private var rightFrequency2: Double = 400.5  // Hz - RIGHT ear only
    private var useDualCarriers: Bool = false    // Flag for dual carrier mode

    private var beatFrequency: Double = 0.5     // Hz - perceived beat

    // Public read-only access for UI sync (e.g., Aurora fade duration)
    var currentBeatFrequency: Double { beatFrequency }
    var currentBeatPeriod: TimeInterval { beatFrequency > 0 ? (1.0 / beatFrequency) : 0.0 }

    // MARK: - Flow State program (time-varying beat)
    private struct BeatStage {
        let startHz: Double
        let endHz: Double
        let duration: TimeInterval
    }

    private var beatProgramActive: Bool = false
    private var beatProgramStartTime: TimeInterval?
    private var beatProgramStages: [BeatStage] = []

    // Light sync needs a phase accumulator to support time-varying beat frequencies cleanly.
    private var lastLightUpdateTime: TimeInterval = 0
    private var lightPhaseCycles: Double = 0

    // Phase tracking
    private var leftPhase: Double = 0
    private var rightPhase: Double = 0
    private var leftPhase2: Double = 0  // Phase for second carrier
    private var rightPhase2: Double = 0 // Phase for second carrier
    private var lightIsOn = false

    // Modulation phase tracking (moved here to persist between buffer calls)
    private var modulationPhase: Double = 0
    private var debugSampleCount: Int = 0  // Debug counter

    // State
    private(set) var isRunning = false

    // Light sync
    private var displayLink: CADisplayLink?
    private var beatStartTime: TimeInterval = 0

    // Volume
    private var currentVolume: Float = 0.0
    private let targetVolume: Float = 0.5
    private var fadeTimer: Timer?

    // Volume modulation for enhanced beat perception
    private var useVolumeModulation: Bool = false
    private let modulationDepth: Float = 0.3  // 30% modulation depth

    // MARK: - Initialization
    init() {
        setupAudioSession()
    }

    deinit {
        stop()
    }

    // MARK: - Setup
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(0.005) // 5ms latency
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func setupAudioEngine() throws {
        audioEngine = AVAudioEngine()

        guard let engine = audioEngine else {
            throw NSError(domain: "BinauralBeatGenerator", code: 1)
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw NSError(domain: "BinauralBeatGenerator", code: 2)
        }
        audioFormat = format

        let sourceNode = AVAudioSourceNode(format: format) { [weak self] (_, _, frameCount, audioBufferList) -> OSStatus in
            guard let self = self else { return noErr }

            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard bufferList.count == 2 else { return noErr }

            let leftChannel = bufferList[0]
            let rightChannel = bufferList[1]

            guard let leftData = leftChannel.mData?.assumingMemoryBound(to: Float.self),
                  let rightData = rightChannel.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            self.generateStereoSamples(
                leftBuffer: leftData,
                rightBuffer: rightData,
                frameCount: Int(frameCount)
            )

            return noErr
        }

        self.sourceNode = sourceNode

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        try engine.start()
    }

    // MARK: - Sample Generation
    private func generateStereoSamples(leftBuffer: UnsafeMutablePointer<Float>,
                                       rightBuffer: UnsafeMutablePointer<Float>,
                                       frameCount: Int) {
        // Keep Flow State ramps updated on the audio thread as well.
        updateBeatFromProgram(currentTime: CACurrentMediaTime())

        // Calculate modulation phase increment
        let modulationPhaseIncrement = 2.0 * Double.pi * beatFrequency / sampleRate

        if useDualCarriers {
            let leftPhaseIncrement1 = 2.0 * Double.pi * leftFrequency / sampleRate
            let rightPhaseIncrement1 = 2.0 * Double.pi * rightFrequency / sampleRate
            let leftPhaseIncrement2 = 2.0 * Double.pi * leftFrequency2 / sampleRate
            let rightPhaseIncrement2 = 2.0 * Double.pi * rightFrequency2 / sampleRate

            for frame in 0..<frameCount {
                var volumeMultiplier: Float = 1.0
                if useVolumeModulation {
                    let currentModPhase = modulationPhase + (Double(frame) * modulationPhaseIncrement)
                    let modValue = Float((1.0 + sin(currentModPhase)) * 0.5)
                    volumeMultiplier = 1.0 - (modulationDepth * (1.0 - modValue))
                }

                let effectiveVolume = currentVolume * volumeMultiplier

                let leftSample1 = Float(sin(leftPhase)) * effectiveVolume * 0.5
                let leftSample2 = Float(sin(leftPhase2)) * effectiveVolume * 0.5
                let rightSample1 = Float(sin(rightPhase)) * effectiveVolume * 0.5
                let rightSample2 = Float(sin(rightPhase2)) * effectiveVolume * 0.5

                leftBuffer[frame] = leftSample1 + leftSample2
                rightBuffer[frame] = rightSample1 + rightSample2

                leftPhase += leftPhaseIncrement1
                rightPhase += rightPhaseIncrement1
                leftPhase2 += leftPhaseIncrement2
                rightPhase2 += rightPhaseIncrement2

                if leftPhase > 2.0 * Double.pi { leftPhase -= 2.0 * Double.pi }
                if rightPhase > 2.0 * Double.pi { rightPhase -= 2.0 * Double.pi }
                if leftPhase2 > 2.0 * Double.pi { leftPhase2 -= 2.0 * Double.pi }
                if rightPhase2 > 2.0 * Double.pi { rightPhase2 -= 2.0 * Double.pi }
            }

            if useVolumeModulation {
                modulationPhase += Double(frameCount) * modulationPhaseIncrement
                while modulationPhase > 2.0 * Double.pi {
                    modulationPhase -= 2.0 * Double.pi
                }

                debugSampleCount += frameCount
                if debugSampleCount >= Int(sampleRate) {
                    debugSampleCount = 0
                    let modValue = Float((1.0 + sin(modulationPhase)) * 0.5)
                    let currentMultiplier = 1.0 - (modulationDepth * (1.0 - modValue))
                    print("Volume modulation active - phase: \(String(format: "%.2f", modulationPhase)), multiplier: \(String(format: "%.2f", currentMultiplier))")
                }
            }
        } else {
            let leftPhaseIncrement = 2.0 * Double.pi * leftFrequency / sampleRate
            let rightPhaseIncrement = 2.0 * Double.pi * rightFrequency / sampleRate

            for frame in 0..<frameCount {
                var volumeMultiplier: Float = 1.0
                if useVolumeModulation {
                    let currentModPhase = modulationPhase + (Double(frame) * modulationPhaseIncrement)
                    let modValue = Float((1.0 + sin(currentModPhase)) * 0.5)
                    volumeMultiplier = 1.0 - (modulationDepth * (1.0 - modValue))
                }

                let effectiveVolume = currentVolume * volumeMultiplier

                let leftSample = Float(sin(leftPhase)) * effectiveVolume
                let rightSample = Float(sin(rightPhase)) * effectiveVolume

                leftBuffer[frame] = leftSample
                rightBuffer[frame] = rightSample

                leftPhase += leftPhaseIncrement
                rightPhase += rightPhaseIncrement

                if leftPhase > 2.0 * Double.pi { leftPhase -= 2.0 * Double.pi }
                if rightPhase > 2.0 * Double.pi { rightPhase -= 2.0 * Double.pi }
            }

            if useVolumeModulation {
                modulationPhase += Double(frameCount) * modulationPhaseIncrement
                while modulationPhase > 2.0 * Double.pi {
                    modulationPhase -= 2.0 * Double.pi
                }
            }
        }
    }

    // MARK: - Light Synchronization
    private func startLightSync() {
        let now = CACurrentMediaTime()
        beatStartTime = now
        lastLightUpdateTime = now
        lightPhaseCycles = 0

        // Reset Flow State ramp timing to align with audio + light start.
        if beatProgramActive {
            beatProgramStartTime = now
            if let first = beatProgramStages.first {
                setBeatFrequency(first.startHz, updateCarriersForFlow: true)
            }
        }

        displayLink = CADisplayLink(target: self, selector: #selector(updateLightState))
        displayLink?.add(to: .current, forMode: .common)
    }

    @objc private func updateLightState() {
        guard isRunning else { return }

        let now = CACurrentMediaTime()
        let dt = now - lastLightUpdateTime
        lastLightUpdateTime = now

        updateBeatFromProgram(currentTime: now)

        if dt > 0 {
            lightPhaseCycles = (lightPhaseCycles + (dt * beatFrequency)).truncatingRemainder(dividingBy: 1.0)
        }

        let shouldBeOn = lightPhaseCycles < 0.5

        if shouldBeOn && !lightIsOn {
            lightIsOn = true
            delegate?.binauralBeatGeneratorDidTriggerLightPulse()
        } else if !shouldBeOn && lightIsOn {
            lightIsOn = false
            delegate?.binauralBeatGeneratorDidReleaseLightPulse()
        }
    }

    // MARK: - Time-varying beat support
    private func setBeatFrequency(_ hz: Double, updateCarriersForFlow: Bool) {
        let clamped = max(0.01, hz)
        beatFrequency = clamped

        if updateCarriersForFlow {
            rightFrequency = leftFrequency + clamped
            rightFrequency2 = leftFrequency2 + clamped
        }
    }

    private func updateBeatFromProgram(currentTime: TimeInterval) {
        guard beatProgramActive,
              let t0 = beatProgramStartTime,
              !beatProgramStages.isEmpty else { return }

        let elapsed = max(0, currentTime - t0)
        var cursor: TimeInterval = 0

        for stage in beatProgramStages {
            let end = cursor + stage.duration
            if elapsed <= end || stage.duration == 0 {
                let local = max(0, elapsed - cursor)
                let frac = stage.duration > 0 ? min(1.0, local / stage.duration) : 1.0
                let hz = stage.startHz + (stage.endHz - stage.startHz) * frac
                setBeatFrequency(hz, updateCarriersForFlow: true)
                return
            }
            cursor = end
        }

        if let last = beatProgramStages.last {
            setBeatFrequency(last.endHz, updateCarriersForFlow: true)
        }
    }

    // MARK: - Configuration
    func configureForFrequency(_ stimulation: StimulationFrequency) {

        // Reset any ramp program first
        beatProgramActive = false
        beatProgramStages = []
        beatProgramStartTime = nil

        // Dual-carrier for ALL binaural beats
        useDualCarriers = true
        useVolumeModulation = false

        // Octave-related carriers (robust on most earbuds)
        leftFrequency = 200.0
        leftFrequency2 = 400.0

        switch stimulation {
        case .binaural:
            beatFrequency = 0.5
            // Optional helper for ultra-slow beats
            useVolumeModulation = true

        case .delta:
            beatFrequency = 2.0

        case .theta:
            beatFrequency = 6.0

        case .alpha:
            beatFrequency = 10.0

        case .beta:
            beatFrequency = 17.0

        case .gamma:
            beatFrequency = 40.0

        case .flowState:
            setupFlowStateProgram()
            beatFrequency = 14.0

        @unknown default:
            // If you ever add new cases, fall back to rawValue if available,
            // otherwise keep current beatFrequency.
            // (If StimulationFrequency is Double-backed, this is perfect.)
            beatFrequency = Double(stimulation.rawValue)
    }

        rightFrequency  = leftFrequency  + beatFrequency
        rightFrequency2 = leftFrequency2 + beatFrequency
    }

    // MARK: - Beat Programs
    private func setupFlowStateProgram() {
        beatProgramStages = [
            BeatStage(startHz: 14.0, endHz: 12.0, duration: 3.5 * 60.0),
            BeatStage(startHz: 12.0, endHz: 10.0, duration: 3.0 * 60.0),
            BeatStage(startHz: 10.0, endHz:  8.0, duration: 2.0 * 60.0)
        ]

        beatProgramActive = true
        beatProgramStartTime = nil
    }

    // MARK: - Control Methods

    /// Starts the binaural beat generator
    /// - Parameter muted: If true, starts with volume at 0 and skips fade-in (for light-only mode)
    func start(muted: Bool = false) {
        guard !isRunning else { return }

        do {
            if audioEngine == nil {
                try setupAudioEngine()
            }

            leftPhase = 0
            rightPhase = 0
            leftPhase2 = 0
            rightPhase2 = 0
            modulationPhase = 0

            // Set initial volume based on muted parameter
            if muted {
                currentVolume = 0
            } else {
                currentVolume = 0
            }

            isRunning = true

            startLightSync()

            // Only fade in if not muted
            if !muted {
                fadeIn()
            } else {
                // Ensure volume stays at 0 for muted mode
                currentVolume = 0
                audioEngine?.mainMixerNode.outputVolume = 0
            }

            if useDualCarriers {
                print("Enhanced binaural beat started (dual carriers):")
                print("  - Left ear: \(leftFrequency) Hz + \(leftFrequency2) Hz")
                print("  - Right ear: \(rightFrequency) Hz + \(rightFrequency2) Hz")
                if useVolumeModulation {
                    print("  - Volume modulation: ENABLED at \(beatFrequency) Hz")
                }
            } else {
                print("Binaural beat started:")
                print("  - Left ear: \(leftFrequency) Hz")
                print("  - Right ear: \(rightFrequency) Hz")
            }
            print("  - Beat frequency: \(beatFrequency) Hz")
            print("  - Muted: \(muted)")
            if !muted {
                print("  - IMPORTANT: Requires stereo headphones for binaural effect!")
            }

        } catch {
            print("Failed to start binaural beat generator: \(error)")
            stop()
        }
    }

    func stop() {
        guard isRunning else { return }

        displayLink?.invalidate()
        displayLink = nil

        if lightIsOn {
            lightIsOn = false
            delegate?.binauralBeatGeneratorDidReleaseLightPulse()
        }

        sourceNode?.reset()
        audioEngine?.stop()

        isRunning = false
        beatProgramStartTime = nil

        fadeTimer?.invalidate()
        fadeTimer = nil

        print("Binaural beat stopped")
    }

    func pause() {
        if isRunning {
            audioEngine?.pause()
            displayLink?.isPaused = true

            if lightIsOn {
                lightIsOn = false
                delegate?.binauralBeatGeneratorDidReleaseLightPulse()
            }
        }
    }

    func resume() {
        if isRunning {
            do {
                try audioEngine?.start()
                displayLink?.isPaused = false
                beatStartTime = CACurrentMediaTime()

                // Optional: restart the ramp cleanly after resume
                if beatProgramActive {
                    beatProgramStartTime = CACurrentMediaTime()
                }
            } catch {
                print("Failed to resume: \(error)")
            }
        }
    }

    // MARK: - Volume Control
    private func fadeIn(duration: TimeInterval = 2.0) {
        fadeTimer?.invalidate()

        let steps = 40
        let interval = duration / Double(steps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            currentStep += 1
            self.currentVolume = (Float(currentStep) / Float(steps)) * self.targetVolume

            if currentStep >= steps {
                timer.invalidate()
                self.fadeTimer = nil
            }
        }
    }

    /// Sets the volume of the binaural beat generator (0.0 to 1.0)
    func setVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        if let engine = self.audioEngine {
            engine.mainMixerNode.outputVolume = clampedVolume
        }
    }

    // MARK: - Cleanup
    func cleanup() {
        stop()
        audioEngine = nil
        sourceNode = nil
        audioFormat = nil
    }
}
