import UIKit

// Protocol definition
protocol AddSequenceStepDelegate: AnyObject {
    func didAddStep(_ step: FrequencyStep)
    func didUpdateStep(_ step: FrequencyStep, at index: Int)
}

class AddSequenceStepViewController: UIViewController {

    weak var delegate: AddSequenceStepDelegate?

    // MARK: - Edit Mode
    /// If set, the controller is in edit mode for an existing step
    var editingStep: FrequencyStep?
    var editingIndex: Int?

    // MARK: - Selections
    private var selectedFrequency: StimulationFrequency?
    private var selectedMode: StimulationMode = .both
    private var isBinaural: Bool = false
    
    // MARK: - UI Components
    
    // Scroll View to handle smaller screens without squashing UI
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = true
        return sv
    }()
    
    private let contentView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    // Header Title
    private let headerLabel: UILabel = {
        let l = UILabel()
        l.text = "New Segment"
        l.font = .systemFont(ofSize: 28, weight: .bold)
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    
    // Cancel Button
    private lazy var cancelButton: UIButton = {
        var config = UIButton.Configuration.gray()
        config.image = UIImage(systemName: "xmark")
        config.cornerStyle = .capsule
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return btn
    }()
    
    // Main Container (Holds Left and Right columns)
    private let mainHStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 24
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let leftVStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        return stack
    }()
    
    private let rightVStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        return stack
    }()
    
    // --- Inputs ---
    
    private let durationField: UITextField = {
        let tf = UITextField()
        tf.text = "10"
        tf.borderStyle = .none
        tf.backgroundColor = .systemBackground
        tf.layer.cornerRadius = 8
        tf.keyboardType = .numberPad
        tf.font = .monospacedDigitSystemFont(ofSize: 32, weight: .bold)
        tf.textAlignment = .center
        // Height 72 for readability
        tf.heightAnchor.constraint(equalToConstant: 72).isActive = true
        return tf
    }()
    
    private let modeSegmentedControl: UISegmentedControl = {
        let items = ["Light & Audio", "Light Only", "Audio Only"]
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        let attr = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]
        sc.setTitleTextAttributes(attr, for: .normal)
        // Height 72
        sc.heightAnchor.constraint(equalToConstant: 72).isActive = true
        return sc
    }()
    
    private let typeSegmentedControl: UISegmentedControl = {
        let items = ["Standard Pulses", "Binaural Beat"]
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        let attr = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]
        sc.setTitleTextAttributes(attr, for: .normal)
        // Height 72
        sc.heightAnchor.constraint(equalToConstant: 72).isActive = true
        return sc
    }()
    
    private let frequencyGridStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.distribution = .fillEqually
        return stack
    }()
    
    private var frequencyButtons: [UIButton] = []
    
    private let addButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Add Segment"
        config.subtitle = "Tap to confirm"
        config.image = UIImage(systemName: "checkmark.circle.fill")
        config.imagePadding = 8
        config.imagePlacement = .trailing
        config.cornerStyle = .large
        config.baseBackgroundColor = .systemBlue
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 20, weight: .bold)
            return outgoing
        }
        
        let btn = UIButton(configuration: config)
        btn.heightAnchor.constraint(equalToConstant: 72).isActive = true
        btn.isEnabled = false
        
        btn.layer.shadowColor = UIColor.systemBlue.cgColor
        btn.layer.shadowOpacity = 0.3
        btn.layer.shadowOffset = CGSize(width: 0, height: 4)
        btn.layer.shadowRadius = 6
        return btn
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        setupUI()
        setupActions()
        setupAccessibility()
        refreshFrequencyButtons()

        // If editing an existing step, populate the fields
        if let step = editingStep {
            configureForEditing(step)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tap)
    }

    // MARK: - Edit Mode Configuration
    private func configureForEditing(_ step: FrequencyStep) {
        // Update header and button text
        headerLabel.text = "Edit Segment"

        var config = addButton.configuration
        config?.title = "Save Changes"
        config?.subtitle = "Tap to confirm"
        config?.image = UIImage(systemName: "checkmark.circle.fill")
        addButton.configuration = config

        // Set duration
        durationField.text = "\(step.durationMinutes)"

        // Set mode
        selectedMode = step.mode
        switch step.mode {
        case .both: modeSegmentedControl.selectedSegmentIndex = 0
        case .lightOnly: modeSegmentedControl.selectedSegmentIndex = 1
        case .audioOnly: modeSegmentedControl.selectedSegmentIndex = 2
        }

        // Set binaural/standard
        isBinaural = step.isBinaural
        typeSegmentedControl.selectedSegmentIndex = step.isBinaural ? 1 : 0

        // Refresh frequency buttons for the correct mode (binaural vs standard)
        refreshFrequencyButtons()

        // Select the correct frequency button
        selectedFrequency = step.frequency
        selectFrequencyButton(for: step.frequency)

        updateAddButtonState()
    }

    private func selectFrequencyButton(for frequency: StimulationFrequency) {
        // Find and select the button matching this frequency
        let frequencies: [StimulationFrequency]
        if isBinaural {
            frequencies = [.binaural, .delta, .theta, .alpha, .flowState, .beta, .gamma]
        } else {
            frequencies = [.delta, .theta, .alpha, .beta, .gamma]
        }

        guard let index = frequencies.firstIndex(of: frequency),
              index < frequencyButtons.count else { return }

        let button = frequencyButtons[index]
        selectFrequency(frequency, sender: button)
    }

    // MARK: - Accessibility
    private func setupAccessibility() {
        headerLabel.accessibilityTraits = .header

        cancelButton.accessibilityLabel = "Cancel"
        cancelButton.accessibilityHint = editingStep != nil
            ? "Closes this screen without saving changes"
            : "Closes this screen without adding a segment"

        durationField.accessibilityLabel = "Duration in minutes"
        durationField.accessibilityHint = "Enter the number of minutes for this segment"

        modeSegmentedControl.accessibilityLabel = "Stimulation mode"
        modeSegmentedControl.accessibilityHint = "Choose between light and audio, light only, or audio only"

        typeSegmentedControl.accessibilityLabel = "Audio engine type"
        typeSegmentedControl.accessibilityHint = "Choose between standard pulses or binaural beat"

        addButton.accessibilityLabel = editingStep != nil ? "Save changes" : "Add segment"
        addButton.accessibilityHint = editingStep != nil
            ? "Saves changes to this segment"
            : "Confirms and adds this segment to the sequence"
    }
    
    // MARK: - Setup UI
    
    private func setupUI() {
        view.addSubview(headerLabel)
        view.addSubview(cancelButton)
        
        // Scroll View Setup
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(mainHStack)
        
        // --- LEFT COLUMN CARDS ---
        
        // Step 1: Duration
        let durationCard = createCard(number: "1", title: "Duration (Minutes)", content: durationField)
        leftVStack.addArrangedSubview(durationCard)
        
        // Step 2: Mode
        let modeCard = createCard(number: "2", title: "Stimulation Mode", content: modeSegmentedControl)
        leftVStack.addArrangedSubview(modeCard)
        
        // Step 3: Engine
        let engineCard = createCard(number: "3", title: "Audio Engine", content: typeSegmentedControl)
        leftVStack.addArrangedSubview(engineCard)
        
        // --- RIGHT COLUMN CARDS ---
        
        // Step 4: Frequency
        let freqCard = createCard(number: "4", title: "Target Frequency", content: frequencyGridStack)
        rightVStack.addArrangedSubview(freqCard)
        
        // Add Button
        rightVStack.addArrangedSubview(addButton)
        
        // --- ASSEMBLY ---
        mainHStack.addArrangedSubview(leftVStack)
        mainHStack.addArrangedSubview(rightVStack)
        
        NSLayoutConstraint.activate([
            // Header Fixed at Top
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            headerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            cancelButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            
            // Scroll View fills rest of screen
            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content View Constraints
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            
            // Main Stack Constraints (Inside Content View)
            mainHStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mainHStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),
            mainHStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            mainHStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
        ])
    }
    
    // MARK: - Card Generator Helper
    private func createCard(number: String, title: String, content: UIView) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 16
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.08
        container.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.layer.shadowRadius = 4
        
        let numLabel = UILabel()
        numLabel.text = number
        numLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .black)
        numLabel.textColor = .white
        numLabel.textAlignment = .center
        numLabel.backgroundColor = .systemBlue
        numLabel.layer.cornerRadius = 12
        numLabel.layer.masksToBounds = true
        numLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = title.uppercased()
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(numLabel)
        container.addSubview(titleLabel)
        container.addSubview(content)
        
        content.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            numLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            numLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            numLabel.widthAnchor.constraint(equalToConstant: 24),
            numLabel.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.centerYAnchor.constraint(equalTo: numLabel.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: numLabel.trailingAnchor, constant: 8),
            
            content.topAnchor.constraint(equalTo: numLabel.bottomAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        
        return container
    }
    
    private func setupActions() {
        modeSegmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        typeSegmentedControl.addTarget(self, action: #selector(typeChanged), for: .valueChanged)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
    }
    
    // MARK: - Logic
    
    @objc private func modeChanged() {
        switch modeSegmentedControl.selectedSegmentIndex {
        case 0: selectedMode = .both
        case 1: selectedMode = .lightOnly
        case 2: selectedMode = .audioOnly
        default: break
        }
    }
    
    @objc private func typeChanged() {
        isBinaural = (typeSegmentedControl.selectedSegmentIndex == 1)
        refreshFrequencyButtons()
    }
    
    private func refreshFrequencyButtons() {
        frequencyGridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        frequencyButtons.removeAll()
        selectedFrequency = nil
        updateAddButtonState()
        
        let frequencies: [StimulationFrequency]
        if isBinaural {
            frequencies = [.binaural, .delta, .theta, .alpha, .flowState, .beta, .gamma]
        } else {
            frequencies = [.delta, .theta, .alpha, .beta, .gamma]
        }
        
        let columns = 2
        var currentRow: UIStackView?
        
        for (index, freq) in frequencies.enumerated() {
            if index % columns == 0 {
                currentRow = UIStackView()
                currentRow?.axis = .horizontal
                currentRow?.spacing = 12
                currentRow?.distribution = .fillEqually
                frequencyGridStack.addArrangedSubview(currentRow!)
            }
            
            let btn = createFreqButton(for: freq)
            currentRow?.addArrangedSubview(btn)
            frequencyButtons.append(btn)
        }
        
        if let lastRow = currentRow, lastRow.arrangedSubviews.count < columns {
            let missing = columns - lastRow.arrangedSubviews.count
            for _ in 0..<missing {
                let spacer = UIView()
                lastRow.addArrangedSubview(spacer)
            }
        }
    }
    
    private func createFreqButton(for freq: StimulationFrequency) -> UIButton {
        let btn = UIButton(type: .system)
        var config = UIButton.Configuration.tinted()
        
        let title: String
        let subtitle: String
        
        if freq == .binaural {
            title = "Delta Slow"
            subtitle = "0.5 Hz"
        } else if freq == .flowState {
            title = "Flow State"
            subtitle = "14→12→10→8 Hz"
        } else {
            title = freq.name
            subtitle = "\(freq.rawValue) Hz"
        }
        
        config.title = title
        config.subtitle = subtitle
        config.titleAlignment = .center
        config.cornerStyle = .medium
        config.baseBackgroundColor = .systemGray5
        config.baseForegroundColor = .label
        
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        
        btn.configuration = config
        btn.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        btn.addAction(UIAction { [weak self] _ in
            self?.selectFrequency(freq, sender: btn)
        }, for: .touchUpInside)
        
        return btn
    }
    
    private func selectFrequency(_ freq: StimulationFrequency, sender: UIButton) {
        selectedFrequency = freq

        // Flow State default hold time = 30 minutes (ramp time is added automatically at runtime).
        if freq == .flowState {
            let current = durationField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current.isEmpty || current == "10" {
                durationField.text = "30"
            }
        }
        for btn in frequencyButtons {
            var config = btn.configuration
            if btn == sender {
                config?.baseBackgroundColor = .systemBlue
                config?.baseForegroundColor = .white
            } else {
                config?.baseBackgroundColor = .systemGray5
                config?.baseForegroundColor = .label
            }
            btn.configuration = config
        }
        updateAddButtonState()
    }
    
    private func updateAddButtonState() {
        let hasDuration = !(durationField.text?.isEmpty ?? true)
        let hasFrequency = selectedFrequency != nil
        addButton.isEnabled = hasDuration && hasFrequency
    }
    
    @objc private func addTapped() {
        guard let freq = selectedFrequency,
              let text = durationField.text,
              let minutes = Int(text), minutes > 0 else { return }

        let step = FrequencyStep(frequency: freq,
                                 durationMinutes: minutes,
                                 isBinaural: isBinaural,
                                 mode: selectedMode)

        // Check if we're editing an existing step or adding a new one
        if let index = editingIndex {
            delegate?.didUpdateStep(step, at: index)
        } else {
            delegate?.didAddStep(step)
        }
        dismiss(animated: true)
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
}
