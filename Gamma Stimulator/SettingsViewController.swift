import UIKit

class SettingsViewController: UIViewController {
    
    // MARK: - IBOutlets (Connect these in storyboard)
    @IBOutlet weak var startDelayField: UITextField!
    @IBOutlet weak var durationField: UITextField!
    @IBOutlet weak var restDurationField: UITextField!
    @IBOutlet weak var cyclesField: UITextField!
    @IBOutlet weak var startTimerButton: UIButton!
    @IBOutlet weak var cancelTimerButton: UIButton!
    @IBOutlet weak var closeButton: UIButton!
    
    // Frequency button outlets
    @IBOutlet weak var startDeltaButton: UIButton!
    @IBOutlet weak var startThetaButton: UIButton!
    @IBOutlet weak var startAlphaButton: UIButton!
    @IBOutlet weak var startBetaButton: UIButton!
    @IBOutlet weak var startGammaButton: UIButton!
    
    @IBOutlet weak var sequenceButton: UIButton!
    
    @IBAction func showSequenceBuilder(_ sender: UIButton) {
        // Prevent double presentation
        guard presentedViewController == nil else { return }
        performSegue(withIdentifier: "showSequenceBuilder", sender: self)
    }
    
    
    // MARK: - Properties
    private var timerManager = StimulationTimerManager.shared
    private var selectedFrequency: StimulationFrequency = .gamma
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupFunctionality()
        loadSavedValues()
        
        // Dismiss keyboard on tap outside
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tap)
        
        // Load saved frequency
        let savedFrequency = UserDefaults.standard.integer(forKey: "selectedFrequency")
        if let frequency = StimulationFrequency(rawValue: savedFrequency) {
            selectedFrequency = frequency
        }
        updateFrequencyButtonStates()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTimerButtonStates()
        
        // Listen for sequence start to dismiss settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sequenceStarted),
            name: NSNotification.Name("SequenceStarted"),
            object: nil
        )
    }
    
    @objc private func sequenceStarted() {
        // Dismiss settings view when sequence starts
        DispatchQueue.main.async {
            self.dismiss(animated: true)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    private func setupFunctionality() {
        // Only set functional properties, not visual ones
        [startDelayField, durationField, restDurationField, cyclesField].forEach { field in
            field?.keyboardType = .numberPad
        }
        
        // Initial state
        updateTimerButtonStates()
    }
    
    private func loadSavedValues() {
        timerManager.loadSettings()
        
        startDelayField?.text = "\(timerManager.startDelayMinutes)"
        durationField?.text = "\(timerManager.stimulationDurationMinutes)"
        restDurationField?.text = "\(timerManager.restDurationMinutes)"
        cyclesField?.text = "\(timerManager.totalCycles)"
    }
    
    private func updateTimerButtonStates() {
        let isRunning = timerManager.isRunning
        
        // Enable/disable controls
        startDelayField?.isEnabled = !isRunning
        durationField?.isEnabled = !isRunning
        restDurationField?.isEnabled = !isRunning
        cyclesField?.isEnabled = !isRunning
        startTimerButton?.isEnabled = !isRunning
        cancelTimerButton?.isEnabled = isRunning
        
        // Update alpha for visual feedback
        startTimerButton?.alpha = isRunning ? 0.5 : 1.0
        cancelTimerButton?.alpha = isRunning ? 1.0 : 0.5
    }
    
    private func updateFrequencyButtonStates() {
        // Reset all buttons to default state (as designed in storyboard)
        let buttons = [startDeltaButton, startThetaButton, startAlphaButton, startBetaButton, startGammaButton]
        
        for button in buttons {
            button?.isSelected = false
        }
        
        // Mark the selected frequency button
        let selectedButton: UIButton?
        
        switch selectedFrequency {
        case .delta:
            selectedButton = startDeltaButton
        case .theta:
            selectedButton = startThetaButton
        case .alpha:
            selectedButton = startAlphaButton
        case .beta:
            selectedButton = startBetaButton
        case .gamma:
            selectedButton = startGammaButton
        case .binaural: // CORRECTED: Changed from .migrainator to .binaural
            selectedButton = nil  // No button for binaural in settings view
        case .flowState:
            selectedButton = nil  // Flow State is configured via the Sequence Builder (binaural-only)
        }
        
        selectedButton?.isSelected = true
    }
    // MARK: - IBActions (Connect these in storyboard)
    
    @IBAction func startTimerTapped(_ sender: UIButton) {
        saveAndStartTimer()
    }
    
    @IBAction func cancelTimerTapped(_ sender: UIButton) {
        timerManager.cancel()
        updateTimerButtonStates()
    }
    
    @IBAction func closeTapped(_ sender: UIButton) {
        dismiss(animated: true)
    }
    
    // MARK: - Frequency Button Actions
    
    @IBAction func startDelta(_ sender: Any) {
        selectedFrequency = .delta
        updateFrequencyButtonStates()
        saveFrequencySetting()
        print("Delta frequency selected (2 Hz)")
    }
    
    @IBAction func startTheta(_ sender: Any) {
        selectedFrequency = .theta
        updateFrequencyButtonStates()
        saveFrequencySetting()
        print("Theta frequency selected (6 Hz)")
    }
    
    @IBAction func startAlpha(_ sender: Any) {
        selectedFrequency = .alpha
        updateFrequencyButtonStates()
        saveFrequencySetting()
        print("Alpha frequency selected (10 Hz)")
    }
    
    @IBAction func startBeta(_ sender: Any) {
        selectedFrequency = .beta
        updateFrequencyButtonStates()
        saveFrequencySetting()
        print("Beta frequency selected (17 Hz)")
    }
    
    @IBAction func startGamma(_ sender: Any) {
        selectedFrequency = .gamma
        updateFrequencyButtonStates()
        saveFrequencySetting()
        print("Gamma frequency selected (40 Hz)")
    }
    
    // MARK: - Timer Management
    
    private func saveAndStartTimer() {
        let startDelay = Int(startDelayField?.text ?? "") ?? 0
        let duration = Int(durationField?.text ?? "") ?? 0
        let rest = Int(restDurationField?.text ?? "") ?? 0
        let cycles = Int(cyclesField?.text ?? "") ?? 0
        
        // Validate inputs
        guard startDelay >= 0, duration > 0, rest >= 0, cycles > 0 else {
            showAlert(title: "Invalid Input",
                     message: "Please enter valid positive numbers. Duration and Cycles must be greater than 0.")
            return
        }
        
        // Additional validation
        if duration > 120 {
            showAlert(title: "Warning",
                     message: "Stimulation duration is very long (\(duration) minutes). Are you sure?",
                     dismissAfterOK: false)
            return
        }
        
        timerManager.configureTimer(
            startDelay: startDelay,
            stimulationDuration: duration,
            restDuration: rest,
            cycles: cycles
        )
        timerManager.saveSettings()
        timerManager.start()
        
        updateTimerButtonStates()
        
        // Show confirmation and dismiss
        let totalMinutes = Int(timerManager.getTotalSessionDuration() / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        let message = "Timer started!\nTotal session: \(hours > 0 ? "\(hours)h " : "")\(minutes)min"
        
        // Show alert with completion handler to dismiss the view
        showAlert(title: "Timer Started", message: message, dismissAfterOK: true)
    }
    
    private func showAlert(title: String, message: String, dismissAfterOK: Bool = false) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            if dismissAfterOK {
                self?.dismiss(animated: true)
            }
        }
        
        alert.addAction(okAction)
        present(alert, animated: true)
    }
    
    private func saveFrequencySetting() {
        UserDefaults.standard.set(selectedFrequency.rawValue, forKey: "selectedFrequency")
        
        // Notify the timer manager or main view controller
        NotificationCenter.default.post(
            name: NSNotification.Name("FrequencyChanged"),
            object: nil,
            userInfo: ["frequency": selectedFrequency]
        )
    }
}
