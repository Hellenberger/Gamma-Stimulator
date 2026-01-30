import UIKit
import AVFoundation
import AudioToolbox

// MARK: - Protocols

protocol SynchronizedFlasherDelegate: AnyObject {
    func toggleFlash(on: Bool)
    func onAudioPulse()
}

protocol AuroraViewDelegate: AnyObject {
    func toggleLEDFlash(on: Bool, level: Float)
}

protocol SleepMonitoringDelegate: AnyObject {
    func startStimulation(duration: TimeInterval)
    func stopStimulation()
    func didUpdateSleepState(stage: SleepStage, description: String)
    func didDetectMorningWakeUp()
}

// MARK: - ViewController

class ViewController: UIViewController, SynchronizedFlasherDelegate, AuroraViewDelegate, FrequencySequenceDelegate, SleepMonitoringDelegate {
    
    // MARK: - UI Outlets
    @IBOutlet var mainView: UIView!
    @IBOutlet weak var countdownLabel: UILabel!
    @IBOutlet weak var phaseLabel: UILabel!
    @IBOutlet weak var cycleLabel: UILabel!
    @IBOutlet weak var selectOptionsButton: UIButton!
    
    // MARK: - UI State
    private var sleepStatusLabel: UILabel!
    private var sleepStageLabel: UILabel!
    private var monitoringButton: UIButton!
    private var clockView: DigitalClockView?
    
    private(set) var currentFrequency: StimulationFrequency = .gamma
    private var visualStimulationEnabled: Bool = true
    
    // MARK: - Sequence Control UI
    private var sequenceControlButton: UIButton!
    private var sequenceStatusLabel: UILabel!
    private var isSequenceRunning = false
    private var isSequencePaused = false
    private var backButton: UIButton!
    
    private lazy var statusInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 16, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.text = "--"
        return label
    }()
    
    private var uiUpdateTimer: Timer?
    private var stepEndTime: Date?
    
    // MARK: - Binaural/Resonate Properties
    private var binauralBeatGenerator: BinauralBeatGenerator?
    private var binauralTimer: Timer?
    private var binauralWasRunningBeforePause = false
    private var remainingBinauralDuration: TimeInterval = 0
    private var binauralPauseTime: Date?
    private var wasPausedDuringBinaural = false
    
    // MARK: - Sleep Monitoring
    private let sleepStimulationController = SleepStimulationController()
    private let sleepCycleManager = SleepCycleManager()
    private var stimulationDelegateAdapter: SleepStimulationControllerDelegateAdapter?
    private var cycleDelegateAdapter: SleepCycleManagerDelegateAdapter?
    var isSleepMonitoringActive = false
    var audioPulseCount = 0
    
    // MARK: - Stimulation & Flash
    lazy var synchronizedFlasher: SynchronizedFlasher? = {
        let flasher = SynchronizedFlasher()
        flasher.delegate = self
        if !flasher.setup() {
            print("Resonate Error: Failed to setup the SynchronizedFlasher.")
            return nil
        }
        return flasher
    }()
    
    lazy var auroraView: AuroraView = {
        let view = AuroraView(frame: self.view.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.delegate = self
        return view
    }()
    
    // MARK: - Flash Logic
    var isFlashOn = false
    var flashTimer: Timer?
    var flashCount = 0
    var flashCountTimer: Timer?
    private let flashCountQueue = DispatchQueue(label: "com.resonate.flashCountQueue")
    
    // MARK: - Back Button
    private func setupBackButton() {
        backButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "Stop & Back"
        config.image = UIImage(systemName: "xmark.circle.fill")
        config.imagePadding = 8
        config.baseBackgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        backButton.configuration = config
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        view.addSubview(backButton)
        
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
    }
    
    @objc private func backButtonTapped() {
        stopStimulation()
        stopBinaural()
        FrequencySequenceManager.shared.stopSequence()
        uiUpdateTimer?.invalidate()
        dismiss(animated: true)
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        setupBackButton()
        self.loadViewIfNeeded()
        setupSequenceControls()
        setupSequenceObservers()
        setupStatusLabel()
        setupAudioInterruptionObservers()

        view.insertSubview(auroraView, at: 0)
        auroraView.setupView()

        // Setup Adapters for Sleep Delegates
        stimulationDelegateAdapter = SleepStimulationControllerDelegateAdapter(viewController: self)
        cycleDelegateAdapter = SleepCycleManagerDelegateAdapter(viewController: self)

        // Load saved frequency
        let savedFrequency = UserDefaults.standard.integer(forKey: UserDefaultsKey.selectedFrequency)
        if let frequency = StimulationFrequency(rawValue: savedFrequency) {
            currentFrequency = frequency
            FrequencySequenceManager.shared.delegate = self
        }

        // Listen for frequency changes
        NotificationCenter.default.addObserver(self, selector: #selector(handleFrequencyChange), name: .frequencyChanged, object: nil)

        // Load sequence
        FrequencySequenceManager.shared.loadSequence()
        FrequencySequenceManager.shared.delegate = self

        // Clock - using guard let instead of force unwrap
        let clock = DigitalClockView(frame: .zero)
        clock.translatesAutoresizingMaskIntoConstraints = false
        clock.alpha = 0.25
        view.addSubview(clock)
        clockView = clock

        NSLayoutConstraint.activate([
            clock.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: +10),
            clock.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0)
        ])

        view.bringSubviewToFront(clock)
        if let button = sequenceControlButton, let label = sequenceStatusLabel {
               view.bringSubviewToFront(label)
               view.bringSubviewToFront(button)
        }

        // Setup accessibility
        setupAccessibility()

        // Check active sequence or restore previous session
        if FrequencySequenceManager.shared.isRunning {
            print("ViewController loaded with active sequence.")
            isSequenceRunning = true
            isSequencePaused = false
            updateSequenceControlUI()
            FrequencySequenceManager.shared.delegate = self

            if let firstStep = FrequencySequenceManager.shared.steps.first {
                 self.frequencyChanged(to: firstStep.frequency, stepIndex: 0, totalSteps: FrequencySequenceManager.shared.steps.count)
            }
        } else if FrequencySequenceManager.shared.restoreSessionIfAvailable() {
            // Session was restored from previous run
            print("ViewController restored previous session")
            isSequenceRunning = true
            isSequencePaused = true
            updateSequenceControlUI()
            showSessionRestoreAlert()
        }
    }

    private func showSessionRestoreAlert() {
        let manager = FrequencySequenceManager.shared
        guard manager.currentStepIndex < manager.steps.count else { return }

        let step = manager.steps[manager.currentStepIndex]
        let remaining = manager.remainingTimeInCurrentStep ?? 0
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60

        let alert = UIAlertController(
            title: "Resume Previous Session?",
            message: "You have an unfinished session: \(step.frequency.name) with \(minutes)m \(seconds)s remaining.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Resume", style: .default) { [weak self] _ in
            FrequencySequenceManager.shared.resumeSequence()
            self?.updateSequenceControlUI()
        })

        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            FrequencySequenceManager.shared.stopSequence()
            self?.isSequenceRunning = false
            self?.isSequencePaused = false
            self?.updateSequenceControlUI()
        })

        present(alert, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Show safety warning if user hasn't consented
        if !SafetyManager.shared.hasUserConsented {
            showSafetyWarning()
        }
    }

    // MARK: - Safety Warning
    private func showSafetyWarning() {
        let alert = UIAlertController(
            title: SafetyManager.warningTitle,
            message: SafetyManager.warningMessage,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "I Understand & Accept", style: .default) { _ in
            SafetyManager.shared.recordConsent()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            // User declined - dismiss the view controller
            self?.dismiss(animated: true)
        })

        present(alert, animated: true)
    }

    // MARK: - Headphone Detection
    private func checkHeadphonesForBinaural(completion: @escaping (Bool) -> Void) {
        guard !AudioRouteManager.shared.isHeadphonesConnected else {
            completion(true)
            return
        }

        let alert = UIAlertController(
            title: AudioRouteManager.headphoneWarningTitle,
            message: AudioRouteManager.headphoneWarningMessage,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Continue Anyway", style: .default) { _ in
            completion(true)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })

        present(alert, animated: true)
    }

    // MARK: - Audio Interruption Handling
    private func setupAudioInterruptionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Audio interrupted (phone call, etc.)
            print("Audio interrupted - pausing stimulation")
            if isSequenceRunning && !isSequencePaused {
                FrequencySequenceManager.shared.pauseSequence()
                pauseBinauralBeats()
            }
            NotificationCenter.default.post(name: .audioInterrupted, object: nil)

        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) {
                print("Audio interruption ended - can resume")
                // Don't auto-resume, let user decide
                NotificationCenter.default.post(name: .audioInterruptionEnded, object: nil)
            }

        @unknown default:
            break
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged
            print("Audio route changed - headphones disconnected")
            if binauralBeatGenerator?.isRunning == true {
                DispatchQueue.main.async { [weak self] in
                    self?.showHeadphonesDisconnectedAlert()
                }
            }
        default:
            break
        }
    }

    private func showHeadphonesDisconnectedAlert() {
        let alert = UIAlertController(
            title: "Headphones Disconnected",
            message: "Binaural beats work best with headphones. Audio is now playing through speakers.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Accessibility
    private func setupAccessibility() {
        auroraView.isAccessibilityElement = true
        auroraView.accessibilityLabel = "Visual stimulation display"
        auroraView.accessibilityHint = "Shows flashing lights synchronized with audio. Swipe up or down to adjust brightness."

        sequenceControlButton.accessibilityLabel = "Sequence control"
        sequenceControlButton.accessibilityHint = "Double tap to start, pause, or resume the stimulation sequence"

        backButton.accessibilityLabel = "Stop and go back"
        backButton.accessibilityHint = "Stops all stimulation and returns to previous screen"

        clockView?.isAccessibilityElement = true
        clockView?.accessibilityLabel = "Current time display"

        statusInfoLabel.isAccessibilityElement = true
        statusInfoLabel.accessibilityLabel = "Session status"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkSequenceState()
        if StimulationTimerManager.shared.isRunning {
            StimulationTimerManager.shared.updateDisplay()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        uiUpdateTimer?.invalidate()
    }
    
    private func setupStatusLabel() {
        view.addSubview(statusInfoLabel)
        view.bringSubviewToFront(statusInfoLabel)
        NSLayoutConstraint.activate([
            statusInfoLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            statusInfoLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            statusInfoLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            statusInfoLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
    }
    
    // MARK: - Frequency Sequence Delegate
    func frequencyChanged(to frequency: StimulationFrequency, stepIndex: Int, totalSteps: Int) {
        print("Resonate: Step \(stepIndex + 1)/\(totalSteps) -> \(frequency.name)")
        currentFrequency = frequency
        
        DispatchQueue.main.async {
            self.sequenceStatusLabel.text = "Step \(stepIndex + 1)/\(totalSteps): \(frequency.name)"
        }
        
        let currentStep = FrequencySequenceManager.shared.steps[stepIndex]
        let duration = currentStep.effectiveDurationSeconds
        stepEndTime = Date().addingTimeInterval(duration)
        
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusLabel(freqName: frequency.name, stepIndex: stepIndex, totalSteps: totalSteps)
        }
        updateStatusLabel(freqName: frequency.name, stepIndex: stepIndex, totalSteps: totalSteps)
        
        stopStimulation()
        stopBinaural()
        
        if FrequencySequenceManager.shared.isPaused { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard stepIndex < FrequencySequenceManager.shared.steps.count else { return }
            let step = FrequencySequenceManager.shared.steps[stepIndex]
            
            // 1. Handle Visuals
            if step.mode == .audioOnly {
                self.visualStimulationEnabled = false
                self.auroraView.setColorGradientVisible(false)
                self.toggleLEDFlash(on: false)
            } else {
                self.visualStimulationEnabled = true
                self.auroraView.delegate = self
            }
            
            // 2. Handle Audio
            let isMuted = (step.mode == .lightOnly)
            
            // 3. Start Engine
            if step.isBinaural || frequency.isBinauralOnly {
                self.startBinauralStimulation(frequency: frequency, duration: duration, muted: isMuted)
            } else {
                self.startRegularStimulation(frequency: frequency, duration: duration, muted: isMuted)
            }
        }
    }
    
    func sequenceCompleted() {
        isSequenceRunning = false
        isSequencePaused = false
        DispatchQueue.main.async {
            self.stopStimulation()
            self.updateSequenceControlUI()
            let alert = UIAlertController(title: "Sequence Complete", message: "The frequency sequence has finished.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    private func updateStatusLabel(freqName: String, stepIndex: Int, totalSteps: Int) {
        guard let endTime = stepEndTime else { return }
        let remaining = endTime.timeIntervalSinceNow
        if remaining <= 0 {
            statusInfoLabel.text = "Step Complete"
            uiUpdateTimer?.invalidate()
            return
        }
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        statusInfoLabel.text = "\(freqName) • \(stepIndex + 1)/\(totalSteps)\n\(String(format: "%02d:%02d", m, s))"
    }
    
    @IBAction func selectOptionsTapped(_ sender: UIButton) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let sequenceVC = storyboard.instantiateViewController(withIdentifier: "SequenceBuilderViewController")
        let nav = UINavigationController(rootViewController: sequenceVC)
        nav.modalPresentationStyle = .fullScreen
        nav.modalTransitionStyle = .crossDissolve
        present(nav, animated: true)
    }
    
    // MARK: - Sequence Controls
    private func setupSequenceControls() {
        sequenceControlButton = UIButton(type: .system)
        sequenceControlButton.setTitle("Start Sequence", for: .normal)
        sequenceControlButton.setTitleColor(.white, for: .normal)
        sequenceControlButton.backgroundColor = UIColor.systemBlue
        sequenceControlButton.layer.cornerRadius = 8
        sequenceControlButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        sequenceControlButton.addTarget(self, action: #selector(sequenceControlTapped), for: .touchUpInside)
        sequenceControlButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sequenceControlButton)
        
        sequenceStatusLabel = UILabel()
        sequenceStatusLabel.text = "No sequence running"
        sequenceStatusLabel.textColor = .white
        sequenceStatusLabel.font = UIFont.systemFont(ofSize: 16)
        sequenceStatusLabel.textAlignment = .center
        sequenceStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sequenceStatusLabel)
        
        NSLayoutConstraint.activate([
            sequenceControlButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sequenceControlButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            sequenceControlButton.widthAnchor.constraint(equalToConstant: 150),
            sequenceControlButton.heightAnchor.constraint(equalToConstant: 44),
            sequenceStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sequenceStatusLabel.bottomAnchor.constraint(equalTo: sequenceControlButton.topAnchor, constant: -10),
            sequenceStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            sequenceStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    private func checkSequenceState() {
        let sequenceManager = FrequencySequenceManager.shared
        isSequenceRunning = sequenceManager.isRunning
        isSequencePaused = sequenceManager.isPaused
        updateSequenceControlUI()
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func sequenceControlTapped() {
        let sequenceManager = FrequencySequenceManager.shared
        if sequenceManager.steps.isEmpty {
            showAlert(title: "No Sequence", message: "Please add frequency steps in the Sequence Builder first.")
            return
        }
        
        if !sequenceManager.isRunning {
            sequenceManager.startSequence()
        } else if sequenceManager.isPaused {
            sequenceManager.resumeSequence()
            resumeBinauralBeats()
        } else {
            sequenceManager.pauseSequence()
            pauseBinauralBeats()
        }
    }
    
    private func pauseBinauralBeats() {
        if let generator = binauralBeatGenerator, generator.isRunning {
            binauralWasRunningBeforePause = true
            if let timer = binauralTimer, timer.isValid {
                let fireDate = timer.fireDate
                remainingBinauralDuration = fireDate.timeIntervalSinceNow
                if remainingBinauralDuration < 0 { remainingBinauralDuration = 0 }
            }
            generator.stop()
        } else {
            binauralWasRunningBeforePause = false
        }
        binauralTimer?.invalidate()
        binauralTimer = nil
        
        if let flasher = synchronizedFlasher, flasher.isRunning { flasher.stopLoop() }
        stopFlashCountTimer()
        toggleLEDFlash(on: false)
        isFlashOn = false
        auroraView.setColorGradientVisible(false)
    }

    private func resumeBinauralBeats() {
        if binauralWasRunningBeforePause {
            binauralBeatGenerator?.cleanup()
            binauralBeatGenerator = nil
            binauralBeatGenerator = BinauralBeatGenerator()
            binauralBeatGenerator?.delegate = self
            binauralBeatGenerator?.configureForFrequency(currentFrequency)
            binauralBeatGenerator?.start()
            
            if remainingBinauralDuration > 0 {
                binauralTimer = Timer.scheduledTimer(withTimeInterval: remainingBinauralDuration, repeats: false) { [weak self] _ in
                    self?.stopBinaural()
                }
            }
            startFlashCountTimer()
        }
        binauralWasRunningBeforePause = false
        remainingBinauralDuration = 0
    }
    
    private func updateSequenceControlUI() {
        DispatchQueue.main.async {
            if !self.isSequenceRunning {
                self.sequenceControlButton.setTitle("Start Sequence", for: .normal)
                self.sequenceControlButton.backgroundColor = UIColor.systemBlue
                self.sequenceStatusLabel.text = "No sequence running"
            } else if self.isSequencePaused {
                self.sequenceControlButton.setTitle("Resume", for: .normal)
                self.sequenceControlButton.backgroundColor = UIColor.systemGreen
                self.sequenceStatusLabel.text = "Sequence paused"
            } else {
                self.sequenceControlButton.setTitle("Pause", for: .normal)
                self.sequenceControlButton.backgroundColor = UIColor.systemOrange
                self.sequenceStatusLabel.text = "Sequence running"
            }
        }
    }
    
    // MARK: - Stimulation Control (REGULAR)
    private func startRegularStimulation(frequency: StimulationFrequency, duration: TimeInterval, muted: Bool) {
        guard let flasher = self.synchronizedFlasher else { return }
        
        if !flasher.isRunning {
            flasher.delegate = self
            flasher.setFrequency(frequency)
            // Pass mute preference to startLoop
            flasher.startLoop(muted: muted)
            startFlashCountTimer()
            print("Resonate: Started \(frequency.name) (Muted: \(muted))")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.stopStimulation()
        }
    }
    
    func stopStimulation() {
        guard let flasher = self.synchronizedFlasher else { return }
        if flasher.isRunning {
            flasher.stopLoop()
            stopFlashCountTimer()
            toggleLEDFlash(on: false)
            print("Resonate: Stopped Regular Stimulation")
        }
        stopBinaural()
        auroraView.hideColorGradient()
        auroraView.setColorGradientVisible(false)
    }
    
    // MARK: - Flash Handling
    func onAudioPulse() {
        guard visualStimulationEnabled else { return }
        DispatchQueue.main.async {
            let period = self.binauralBeatGenerator?.currentBeatPeriod ?? self.currentFrequency.period
            self.auroraView.startColorCycleFade(duration: period)
            self.toggleLEDFlash(on: true, level: Float(UIScreen.main.brightness))
            let offDelay = self.currentFrequency.onDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + offDelay) {
                self.toggleLEDFlash(on: false)
            }
            self.flashCount += 1
            self.audioPulseCount += 1
        }
    }

    func toggleFlash(on: Bool) {
        isFlashOn = on
        if on { auroraView.setColorGradientVisible(true) } else { auroraView.setColorGradientVisible(false) }
    }

    func toggleLEDFlash(on: Bool, level: Float = 1.0) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on && level > 0 { try device.setTorchModeOn(level: level) } else { device.torchMode = .off }
            device.unlockForConfiguration()
        } catch { print("Torch error: \(error)") }
    }
    
    func startFlashCountTimer() {
        flashTimer?.invalidate()
        flashCount = 0
        audioPulseCount = 0
        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.flashCount = 0
            self.audioPulseCount = 0
        }
        if let flashTimer { RunLoop.main.add(flashTimer, forMode: .common) }
    }

    func stopFlashCountTimer() {
        flashTimer?.invalidate()
        flashTimer = nil
    }
    
    // MARK: - Sleep Monitoring Delegate
    
    func startStimulation(duration: TimeInterval) {
        print("Sleep Monitor Triggered Stimulation for \(duration)s")
        visualStimulationEnabled = true
        auroraView.delegate = self
        
        if currentFrequency.isBinauralOnly {
            startBinauralStimulation(frequency: currentFrequency, duration: duration, muted: false)
        } else {
            startRegularStimulation(frequency: currentFrequency, duration: duration, muted: false)
        }
    }
    
    func didUpdateSleepState(stage: SleepStage, description: String) {
        DispatchQueue.main.async {
            if let label = self.sleepStageLabel {
                label.text = "Sleep Stage: \(description)"
            }
        }
    }
    
    func didDetectMorningWakeUp() {
        DispatchQueue.main.async {
            self.sleepStatusLabel.text = "Morning Wake-Up Detected"
        }
    }
    
    // MARK: - Sequence Observers
    func setupSequenceObservers() {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(sequenceStartedNotification), name: .sequenceStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sequencePausedNotification), name: .sequencePaused, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sequenceResumedNotification), name: .sequenceResumed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sequenceStoppedNotification), name: .sequenceStopped, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sequenceCompletedNotification), name: .sequenceCompleted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startFrequencySequence), name: .startFrequencySequence, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFrequencyChange), name: .frequencyChanged, object: nil)
    }
    
    @objc private func sequenceStartedNotification() {
        isSequenceRunning = true
        isSequencePaused = false
        updateSequenceControlUI()
    }
    
    @objc private func sequencePausedNotification() {
        isSequencePaused = true
        updateSequenceControlUI()
        pauseBinauralBeats()
    }
    
    @objc private func sequenceResumedNotification() {
        isSequencePaused = false
        updateSequenceControlUI()
        resumeBinauralBeats()
    }
    
    @objc private func startFrequencySequence() {
        isSequenceRunning = true
        isSequencePaused = false
        updateSequenceControlUI()
        FrequencySequenceManager.shared.delegate = self
    }
    
    @objc private func sequenceStoppedNotification() {
        isSequenceRunning = false
        isSequencePaused = false
        updateSequenceControlUI()
        stopStimulation()
    }
    
    @objc private func sequenceCompletedNotification() {
        sequenceCompleted()
    }
    
    @objc private func handleFrequencyChange(_ notification: Notification) {
        if let frequency = notification.userInfo?["frequency"] as? StimulationFrequency {
            currentFrequency = frequency
            synchronizedFlasher?.setFrequency(frequency)
        }
    }
}

// MARK: - Binaural/Resonate Extension

extension ViewController: BinauralBeatGeneratorDelegate {

    func startBinauralStimulation(frequency: StimulationFrequency, duration: TimeInterval, muted: Bool) {
        // Check for headphones before starting binaural (only if not muted, since audio matters)
        if !muted {
            checkHeadphonesForBinaural { [weak self] shouldProceed in
                guard shouldProceed else { return }
                self?.performBinauralStart(frequency: frequency, duration: duration, muted: muted)
            }
        } else {
            performBinauralStart(frequency: frequency, duration: duration, muted: muted)
        }
    }

    private func performBinauralStart(frequency: StimulationFrequency, duration: TimeInterval, muted: Bool) {
        stopStimulation()
        stopBinaural()

        binauralBeatGenerator = BinauralBeatGenerator()
        binauralBeatGenerator?.delegate = self
        binauralBeatGenerator?.configureForFrequency(frequency)

        // Use the proper muted parameter instead of the hack
        binauralBeatGenerator?.start(muted: muted)

        if duration > 0 {
            binauralTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.stopBinaural()
                print("Resonate: Binaural finished after \(duration)s")
            }
        }
        startFlashCountTimer()
        print("Resonate: Started Binaural \(frequency.name) (Muted: \(muted))")
    }
    
    func stopBinaural() {
        binauralBeatGenerator?.stop()
        binauralBeatGenerator?.cleanup()
        binauralBeatGenerator = nil
        
        binauralTimer?.invalidate()
        binauralTimer = nil
        
        DispatchQueue.main.async {
            self.isFlashOn = false
            self.auroraView.setColorGradientVisible(false)
            self.toggleLEDFlash(on: false)
        }
    }
    
    func binauralBeatGeneratorDidTriggerLightPulse() {
        guard visualStimulationEnabled else { return }
        DispatchQueue.main.async {
            let period = self.binauralBeatGenerator?.currentBeatPeriod ?? self.currentFrequency.period
            self.auroraView.startColorCycleFade(duration: period)
            self.toggleLEDFlash(on: true, level: Float(UIScreen.main.brightness))
            self.flashCount += 1
        }
    }

    func binauralBeatGeneratorDidReleaseLightPulse() {
        DispatchQueue.main.async {
            self.toggleLEDFlash(on: false)
        }
    }
}

// MARK: - SynchronizedFlasher

class SynchronizedFlasher {
    weak var delegate: SynchronizedFlasherDelegate?
    
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?
    private var fadeInTimer: Timer?
    
    private(set) var currentFrequency: StimulationFrequency = .gamma
    
    private let numberOfBuffers = 3
    private var bufferIndex = 0
    private var scheduledBufferCount = 0
    private let bufferQueue = DispatchQueue(label: "com.resonate.bufferQueue")
    private var bufferDuration: TimeInterval = 0
    
    var isRunning = false
    private var targetVolume: Float = 1.0
    
    init() { }
    
    func setVolume(_ volume: Float) {
        targetVolume = volume
        fadeInTimer?.invalidate()
        fadeInTimer = nil
        playerNode?.volume = volume
    }
    
    func setFrequency(_ frequency: StimulationFrequency) {
        if isRunning { stopLoop() }
        currentFrequency = frequency
        let _ = loadAudioFileForFrequency(frequency)
    }
    
    private func loadAudioFileForFrequency(_ frequency: StimulationFrequency) -> Bool {
        if frequency.isBinauralOnly { return true }
        let filename = "\(frequency.rawValue)Hz"
        guard let fileURL = Bundle.main.url(forResource: filename, withExtension: "aiff") else { return false }
        
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
            guard let file = audioFile else { return false }
            
            let format = file.processingFormat
            let frameLength = file.length
            bufferDuration = Double(frameLength) / format.sampleRate
            let outputFormat: AVAudioFormat
            
            if format.channelCount == 1 {
                guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2),
                      let stereoBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: AVAudioFrameCount(frameLength)),
                      let monoBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength)) else { return false }
                
                outputFormat = stereoFormat
                monoBuffer.frameLength = AVAudioFrameCount(frameLength)
                try file.read(into: monoBuffer)
                
                stereoBuffer.frameLength = monoBuffer.frameLength
                if let monoData = monoBuffer.floatChannelData?[0],
                   let leftData = stereoBuffer.floatChannelData?[0],
                   let rightData = stereoBuffer.floatChannelData?[1] {
                    for i in 0..<Int(monoBuffer.frameLength) {
                        leftData[i] = monoData[i]
                        rightData[i] = monoData[i]
                    }
                }
                audioBuffer = stereoBuffer
            } else {
                outputFormat = format
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength)) else { return false }
                buffer.frameLength = AVAudioFrameCount(frameLength)
                try file.read(into: buffer)
                audioBuffer = buffer
            }
            
            if let engine = engine, let playerNode = playerNode, engine.isRunning {
                engine.disconnectNodeOutput(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
            }
            return true
        } catch { return false }
    }
    
    func setup() -> Bool {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setPreferredIOBufferDuration(0.005)
            try audioSession.setActive(true)
            
            engine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()
            guard let engine = engine, let playerNode = playerNode else { return false }
            engine.attach(playerNode)
            
            if !loadAudioFileForFrequency(currentFrequency) { return false }
            guard let audioBuffer = audioBuffer else { return false }
            engine.connect(playerNode, to: engine.mainMixerNode, format: audioBuffer.format)
            try engine.start()
            return true
        } catch { return false }
    }
    
    func startLoop(muted: Bool = false) {
        guard !isRunning, let engine = engine, let playerNode = playerNode, audioBuffer != nil else { return }
        do {
            if !engine.isRunning { try engine.start() }
            isRunning = true
            playerNode.play()
            bufferQueue.sync { scheduleNextBuffer() }
            
            if muted {
                targetVolume = 0.0
                playerNode.volume = 0.0
            } else {
                targetVolume = 1.0
                startFadeIn()
            }
        } catch { print("Resonate Start Error: \(error)") }
    }
    
    private func scheduleNextBuffer() {
        guard isRunning, let playerNode = playerNode, let buffer = audioBuffer else { return }
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            guard let self = self else { return }
            self.bufferQueue.async {
                if self.isRunning { self.scheduleNextBuffer() }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.onAudioPulse()
        }
    }
    
    private func startFadeIn(duration: TimeInterval = 2.0) {
        fadeInTimer?.invalidate()
        playerNode?.volume = 0.0
        var currentStep = 0
        let steps = 20
        
        fadeInTimer = Timer.scheduledTimer(withTimeInterval: duration / 20.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            currentStep += 1
            self.playerNode?.volume = Float(min(1.0, Double(currentStep) / 20.0)) * self.targetVolume
            if currentStep >= steps { timer.invalidate() }
        }
    }
    
    func stopLoop() {
        isRunning = false
        playerNode?.stop()
        playerNode?.reset()
        engine?.stop()
        fadeInTimer?.invalidate()
    }
}

// MARK: - AuroraView

// MARK: - AuroraView

class AuroraView: UIView {
    weak var delegate: AuroraViewDelegate?

    private let dimView = UIView()
    // Replicator isn't strictly necessary for a single pulse, but kept for original visual style
    private let replicatorLayer = CAReplicatorLayer()
    private let whiteRadialLayer = CALayer()     // The white flash behind
    private let gradientImageLayer = CALayer()   // The colorful gradient on top

    // Cache to avoid redrawing the gradient every frame (performance optimization)
    private var cachedSide: CGFloat = 0
    private var cachedWhiteCG: CGImage?
    private var cachedColorCG: CGImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupAccessibility()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupAccessibility()
    }

    private func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityLabel = "Visual stimulation display"
        accessibilityHint = "Shows flashing lights synchronized with audio. Swipe up to increase brightness, down to decrease."
        accessibilityTraits = .adjustable
    }

    // MARK: - Accessibility Actions
    override func accessibilityIncrement() {
        UIScreen.main.brightness = min(1.0, UIScreen.main.brightness + 0.1)
        delegate?.toggleLEDFlash(on: true, level: Float(UIScreen.main.brightness))
    }

    override func accessibilityDecrement() {
        UIScreen.main.brightness = max(0.0, UIScreen.main.brightness - 0.1)
        delegate?.toggleLEDFlash(on: UIScreen.main.brightness > 0, level: Float(UIScreen.main.brightness))
    }

    func setupView() {
        // Distinctive Light Blue Background
        backgroundColor = UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)

        // Dimming view for gesture brightness control
        dimView.frame = bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.backgroundColor = .black
        dimView.alpha = 0.1
        addSubview(dimView)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        dimView.addGestureRecognizer(panGesture)

        if replicatorLayer.superlayer == nil { layer.addSublayer(replicatorLayer) }

        // Add layers: Color goes first, then White (z-position handles visibility)
        if gradientImageLayer.superlayer == nil { replicatorLayer.addSublayer(gradientImageLayer) }
        if whiteRadialLayer.superlayer == nil { replicatorLayer.addSublayer(whiteRadialLayer) }

        // Layer ordering
        whiteRadialLayer.zPosition = 0
        gradientImageLayer.zPosition = 1

        // Disable implicit animations for snapping changes
        let noActions: [String: CAAction] = [
            "opacity": NSNull(), "contents": NSNull(), "bounds": NSNull(), "position": NSNull()
        ]
        whiteRadialLayer.actions = noActions
        gradientImageLayer.actions = noActions

        // Initial Opacity
        whiteRadialLayer.opacity = 1.0
        gradientImageLayer.opacity = 0.0 // Start invisible, flash triggers it
    }

    @objc func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        let velocity = recognizer.velocity(in: dimView)
        let verticalVelocity = abs(velocity.y)
        let scaled = verticalVelocity / (dimView.bounds.height * 15)
        UIScreen.main.brightness = max(0, min(1,
            UIScreen.main.brightness + (velocity.y > 0 ? -scaled : +scaled)
        ))
        delegate?.toggleLEDFlash(on: UIScreen.main.brightness > 0,
                                 level: Float(UIScreen.main.brightness))
    }

    // The Missing Function: Generates the Gradient Image
    private func makeRadialGradientImage(size: CGSize,
                                         colors: [UIColor],
                                         locations: [CGFloat]) -> CGImage? {
        let w = size.width, h = size.height
        let center = CGPoint(x: w/2, y: h/2)
        let endRadius = min(w, h) / 2

        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        guard
            let ctx = UIGraphicsGetCurrentContext(),
            let gradient = CGGradient(colorsSpace: nil,
                                      colors: colors.map { $0.cgColor } as CFArray,
                                      locations: locations)
        else { return nil }

        ctx.drawRadialGradient(gradient,
                               startCenter: center, startRadius: 0,
                               endCenter: center,   endRadius: endRadius,
                               options: [])
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        replicatorLayer.frame = bounds
        for L in [whiteRadialLayer, gradientImageLayer] {
            L.frame = bounds
            L.contentsGravity = .resize
            L.contentsScale = UIScreen.main.scale
        }

        // Use the shortest side for the source circle
        let side = floor(min(bounds.width, bounds.height))
        guard side > 0 else { return }

        // Only regenerate image if size changed
        if side != cachedSide || cachedWhiteCG == nil || cachedColorCG == nil {
            cachedSide = side
            let srcSize = CGSize(width: side, height: side)

            // 1. Create White Gradient (Background Flash)
            let whiteCG = makeRadialGradientImage(
                size: srcSize,
                colors: [UIColor.white.withAlphaComponent(0.90),
                         UIColor.white.withAlphaComponent(0.60),
                         UIColor.white.withAlphaComponent(0.05),
                         UIColor.white.withAlphaComponent(0.00)],
                locations: [0.0, 0.70, 0.90, 1.0]
            )

            // 2. Create The Multi-Color Gradient (The "Aurora" part)
            let lightBlue = UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
            let colors: [UIColor] = [.black, .darkGray, .gray, .lightGray, .white, .yellow, .green, .red, lightBlue]
            let locations: [CGFloat] = [0.0, 0.0010, 0.0015, 0.005, 0.030, 0.10 , 0.25, 0.5, 0.75]
            let colorCG = makeRadialGradientImage(size: srcSize, colors: colors, locations: locations)

            // Apply images to layers
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let cg = colorCG {
                gradientImageLayer.contents = cg
                cachedColorCG = cg
            }
            if let cg = whiteCG {
                whiteRadialLayer.contents = cg
                cachedWhiteCG = cg
            }
            CATransaction.commit()
        }
    }

    // Called by ViewController to flash the screen
    public func startColorCycleFade(duration: TimeInterval) {
        guard duration > 0 else {
            setColorGradientAlpha(0)
            return
        }

        // 1. Reset to full opacity immediately
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientImageLayer.removeAllAnimations()
        gradientImageLayer.opacity = 1.0
        CATransaction.commit()

        // 2. Animate fade out over the duration of the pulse
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue   = 0.0
        anim.duration  = duration
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        gradientImageLayer.add(anim, forKey: "cycleFade")
        
        // 3. Cleanup at end of pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.gradientImageLayer.opacity = 0.0
        }
    }

    public func setColorGradientVisible(_ visible: Bool) {
        setColorGradientAlpha(visible ? 1.0 : 0.0)
    }

    public func hideColorGradient() {
        setColorGradientAlpha(0)
    }
    
    public func setColorGradientAlpha(_ alpha: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientImageLayer.removeAllAnimations()
        gradientImageLayer.opacity = Float(max(0, min(1, alpha)))
        CATransaction.commit()
    }
}

// MARK: - Delegates Adapters

class SleepStimulationControllerDelegateAdapter: NSObject, SleepStimulationControllerDelegate {
    weak var viewController: (SleepMonitoringDelegate & AnyObject)?
    init(viewController: SleepMonitoringDelegate & AnyObject) { self.viewController = viewController }
    func startStimulation(duration: TimeInterval) { viewController?.startStimulation(duration: duration) }
    func stopStimulation() { viewController?.stopStimulation() }
    func didUpdateSleepState(stage: SleepStage, description: String) { viewController?.didUpdateSleepState(stage: stage, description: description) }
}

class SleepCycleManagerDelegateAdapter: NSObject, SleepCycleManagerDelegate {
    weak var viewController: (SleepMonitoringDelegate & AnyObject)?
    init(viewController: SleepMonitoringDelegate & AnyObject) { self.viewController = viewController }
    func sleepCycleManager(_ manager: SleepCycleManager, didStartStimulation: Bool) { }
    func sleepCycleManager(_ manager: SleepCycleManager, didStopStimulation: Bool) { }
    func sleepCycleManager(_ manager: SleepCycleManager, didDetectSleepStage stage: SleepStage) { }
    func sleepCycleManager(_ manager: SleepCycleManager, didDetectMorningWakeUp: Bool) { }
}
