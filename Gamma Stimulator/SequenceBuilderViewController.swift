import UIKit

class SequenceBuilderViewController: UIViewController {
    
    // MARK: - Properties
    private let sequenceManager = FrequencySequenceManager.shared
    
    // MARK: - UI Components
    
    // Custom Header
    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Sequence Builder"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var helpButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "questionmark.circle")
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(showGuidebook), for: .touchUpInside)
        return btn
    }()
    
    private lazy var clearButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Clear"
        config.baseForegroundColor = .systemRed
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(confirmClear), for: .touchUpInside)
        return btn
    }()
    
    // Horizontal Collection View (The Strip of Cards)
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        // Card size optimized for Landscape
        layout.itemSize = CGSize(width: 200, height: 180)
        layout.minimumInteritemSpacing = 20
        layout.minimumLineSpacing = 20
        layout.sectionInset = UIEdgeInsets(top: 0, left: 40, bottom: 0, right: 40)
        
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(SequenceStepCell.self, forCellWithReuseIdentifier: SequenceStepCell.identifier)
        return cv
    }()
    
    private lazy var bottomControlContainer: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemChromeMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 20
        view.clipsToBounds = true
        return view
    }()
    
    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.text = "Total: 0 min"
        return label
    }()
    
    private lazy var startButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Start Sequence"
        config.image = UIImage(systemName: "play.fill")
        config.imagePadding = 12
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .systemGreen
        
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: #selector(startSequenceTapped), for: .touchUpInside)
        return btn
    }()
    
    private lazy var addButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.image = UIImage(systemName: "plus")
        config.title = "Add Segment"
        config.imagePadding = 12
        config.cornerStyle = .capsule
        
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: #selector(showAddStepScreen), for: .touchUpInside)
        return btn
    }()
    
    private lazy var deleteButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "trash")
        config.baseForegroundColor = .systemRed
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: #selector(toggleEditingMode), for: .touchUpInside)
        return btn
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        setupLayout()
        setupCollectionView()
        setupAccessibility()
        updateUI()
    }

    // MARK: - Accessibility
    private func setupAccessibility() {
        titleLabel.accessibilityTraits = .header

        helpButton.accessibilityLabel = "Help"
        helpButton.accessibilityHint = "Opens the guidebook with information about frequencies"

        clearButton.accessibilityLabel = "Clear all segments"
        clearButton.accessibilityHint = "Removes all segments from the sequence"

        addButton.accessibilityLabel = "Add segment"
        addButton.accessibilityHint = "Adds a new frequency segment to the sequence"

        startButton.accessibilityLabel = "Start sequence"
        startButton.accessibilityHint = "Begins playing the stimulation sequence"

        deleteButton.accessibilityLabel = "Delete mode"
        deleteButton.accessibilityHint = "Toggle editing mode to delete segments"

        collectionView.accessibilityLabel = "Sequence segments"
        collectionView.accessibilityHint = "Horizontal list of frequency segments in the sequence"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateUI()
    }
    
    // MARK: - Setup
    
    private func setupLayout() {
        view.addSubview(headerView)
        headerView.addSubview(clearButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(helpButton)
        
        view.addSubview(collectionView)
        view.addSubview(bottomControlContainer)
        
        // Configure Buttons to fit text
        [addButton, startButton].forEach { btn in
            btn.titleLabel?.adjustsFontSizeToFitWidth = true
            btn.titleLabel?.minimumScaleFactor = 0.8
        }
        
        // Bottom Stack
        let buttonStack = UIStackView(arrangedSubviews: [deleteButton, addButton, startButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fill
        buttonStack.alignment = .fill
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Constraints for bottom buttons
        deleteButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        addButton.widthAnchor.constraint(equalTo: startButton.widthAnchor).isActive = true
        addButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        startButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        let mainStack = UIStackView(arrangedSubviews: [durationLabel, buttonStack])
        mainStack.axis = .vertical
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        bottomControlContainer.contentView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),
            
            clearButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            clearButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            helpButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            helpButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            // Collection View (The Horizontal Strip)
            // It spans the full width of the screen
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40), // Shifted up slightly
            collectionView.heightAnchor.constraint(equalToConstant: 220), // Fixed height for cards
            
            // Bottom Control Bar
            bottomControlContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            bottomControlContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomControlContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 850),
            bottomControlContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            bottomControlContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            // Stack Inside Bar
            mainStack.topAnchor.constraint(equalTo: bottomControlContainer.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: bottomControlContainer.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: bottomControlContainer.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: bottomControlContainer.bottomAnchor, constant: -16),
            
            startButton.heightAnchor.constraint(equalToConstant: 50),
            addButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func setupCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = self
    }
    
    // MARK: - Actions
    
    @objc private func showGuidebook() {
        let guideVC = GuidebookViewController()
        let nav = UINavigationController(rootViewController: guideVC)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
        }
        present(nav, animated: true)
    }
    
    @objc private func showAddStepScreen() {
        let addVC = AddSequenceStepViewController()
        addVC.delegate = self
        if let sheet = addVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(addVC, animated: true)
    }
    
    @objc private func toggleEditingMode() {
        // For collection view, we'll just toggle a visual state if needed,
        // but we have explicit delete buttons on cells now.
        // We can pulse the delete buttons or shake the cells here if desired.
    }
    
    @objc private func confirmClear() {
        guard !sequenceManager.steps.isEmpty else { return }
        let alert = UIAlertController(title: "Clear All", message: "Remove all segments?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.sequenceManager.clearSteps()
            self?.collectionView.reloadData()
            self?.updateUI()
        })
        present(alert, animated: true)
    }
    
    @objc private func startSequenceTapped() {
        guard !sequenceManager.steps.isEmpty else { return }

        sequenceManager.startSequence()
        NotificationCenter.default.post(name: .startFrequencySequence, object: nil)
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let playerVC = storyboard.instantiateViewController(withIdentifier: "ViewController") as? ViewController {
            playerVC.modalPresentationStyle = .fullScreen
            playerVC.modalTransitionStyle = .crossDissolve
            present(playerVC, animated: true)
        } else {
            print("Error: ID 'ViewController' not found in Storyboard")
        }
    }
    
    private func updateUI() {
        let totalMinutes = sequenceManager.getTotalDuration()
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        
        if totalMinutes == 0 {
            durationLabel.text = "Add a segment to begin"
        } else {
            let timeString = hours > 0 ? "\(hours)h \(mins)m" : "\(mins) min"
            durationLabel.text = "Total Duration: \(timeString)"
        }
        
        let hasSteps = !sequenceManager.steps.isEmpty
        startButton.isEnabled = hasSteps
        startButton.configuration?.baseBackgroundColor = hasSteps ? .systemGreen : .systemGray4
        
        clearButton.isEnabled = hasSteps
        clearButton.alpha = hasSteps ? 1.0 : 0.5
    }
    
    func deleteStep(at index: Int) {
        sequenceManager.removeStep(at: index)
        collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        
        // Refresh numbers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.collectionView.reloadData()
        }
        updateUI()
    }
}

// MARK: - Delegates

extension SequenceBuilderViewController: AddSequenceStepDelegate {
    func didAddStep(_ step: FrequencyStep) {
        sequenceManager.addStep(step)
        let indexPath = IndexPath(item: sequenceManager.steps.count - 1, section: 0)
        collectionView.insertItems(at: [indexPath])
        // Scroll to the new item
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        updateUI()
    }

    func didUpdateStep(_ step: FrequencyStep, at index: Int) {
        sequenceManager.updateStep(at: index, with: step)
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.reloadItems(at: [indexPath])
        updateUI()
    }
}

extension SequenceBuilderViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return sequenceManager.steps.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SequenceStepCell.identifier, for: indexPath) as! SequenceStepCell
        let step = sequenceManager.steps[indexPath.item]

        cell.configure(with: step, index: indexPath.item)

        cell.deleteHandler = { [weak self] in
            self?.deleteStep(at: indexPath.item)
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let step = sequenceManager.steps[indexPath.item]
        showEditStepScreen(for: step, at: indexPath.item)
    }

    private func showEditStepScreen(for step: FrequencyStep, at index: Int) {
        let editVC = AddSequenceStepViewController()
        editVC.delegate = self
        editVC.editingStep = step
        editVC.editingIndex = index

        if let sheet = editVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(editVC, animated: true)
    }
}

// MARK: - Custom Card Cell (Horizontal Layout)
class SequenceStepCell: UICollectionViewCell {
    static let identifier = "SequenceStepCell"
    
    var deleteHandler: (() -> Void)?
    
    private let bgView: UIView = {
        let v = UIView()
        v.backgroundColor = .secondarySystemGroupedBackground
        v.layer.cornerRadius = 16
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.systemGray5.cgColor
        // Shadow
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.1
        v.layer.shadowOffset = CGSize(width: 0, height: 4)
        v.layer.shadowRadius = 6
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private let numberLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 60, weight: .black) // Very large step number
        l.textColor = .tertiaryLabel.withAlphaComponent(0.15)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    
    private let freqLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 24, weight: .bold)
        l.textAlignment = .center
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    
    private let typeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    
    private let badgeStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    private let durationBadge: UIButton = {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .systemBlue.withAlphaComponent(0.15)
        config.baseForegroundColor = .systemBlue
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        let btn = UIButton(configuration: config)
        btn.isUserInteractionEnabled = false
        return btn
    }()
    
    private let modeBadge: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemGray
        iv.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return iv
    }()
    
    private lazy var trashButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        btn.tintColor = .systemGray3
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        return btn
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }
    
    @objc private func deleteTapped() {
        deleteHandler?()
    }
    
    private func setupUI() {
        contentView.addSubview(bgView)
        bgView.addSubview(numberLabel)
        bgView.addSubview(trashButton)
        bgView.addSubview(freqLabel)
        bgView.addSubview(typeLabel)
        bgView.addSubview(badgeStack)
        
        badgeStack.addArrangedSubview(modeBadge)
        badgeStack.addArrangedSubview(durationBadge)
        
        NSLayoutConstraint.activate([
            bgView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            bgView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            bgView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            bgView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            
            // Number in background
            numberLabel.topAnchor.constraint(equalTo: bgView.topAnchor, constant: 0),
            numberLabel.leadingAnchor.constraint(equalTo: bgView.leadingAnchor, constant: 12),
            
            // Trash (Top Right)
            trashButton.topAnchor.constraint(equalTo: bgView.topAnchor, constant: 8),
            trashButton.trailingAnchor.constraint(equalTo: bgView.trailingAnchor, constant: -8),
            trashButton.widthAnchor.constraint(equalToConstant: 30),
            trashButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Center Content
            freqLabel.centerXAnchor.constraint(equalTo: bgView.centerXAnchor),
            freqLabel.centerYAnchor.constraint(equalTo: bgView.centerYAnchor, constant: -10),
            
            typeLabel.topAnchor.constraint(equalTo: freqLabel.bottomAnchor, constant: 4),
            typeLabel.centerXAnchor.constraint(equalTo: bgView.centerXAnchor),
            
            // Bottom Badges
            badgeStack.centerXAnchor.constraint(equalTo: bgView.centerXAnchor),
            badgeStack.bottomAnchor.constraint(equalTo: bgView.bottomAnchor, constant: -16)
        ])
    }
    
    func configure(with step: FrequencyStep, index: Int) {
        numberLabel.text = String(format: "%02d", index + 1)

        freqLabel.text = step.frequency.name

        let typeText = step.isBinaural ? "Binaural" : "Pulse"
        let hzText: String
        if step.frequency == .binaural {
            hzText = "0.5 Hz"
        } else if step.frequency == .flowState {
            hzText = "8 Hz (ramp)"
        } else {
            hzText = "\(step.frequency.rawValue) Hz"
        }

        if step.frequency == .flowState && step.isBinaural {
            typeLabel.text = "14→12→10→8 Hz ramp • Hold \(step.durationMinutes)m • \(typeText)"
        } else {
            typeLabel.text = "\(hzText) • \(typeText)"
        }

        var config = durationBadge.configuration
        if step.frequency == .flowState && step.isBinaural {
            config?.title = "\(step.durationMinutes)m hold"
        } else {
            config?.title = "\(step.durationMinutes)m"
        }
        config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 13, weight: .bold)
            return outgoing
        }
        durationBadge.configuration = config

        modeIcon.image = UIImage(systemName: step.mode.icon)

        // Accessibility
        setupCellAccessibility(step: step, index: index, typeText: typeText, hzText: hzText)
    }

    private func setupCellAccessibility(step: FrequencyStep, index: Int, typeText: String, hzText: String) {
        // The cell itself is not an accessibility element since we want users to tap the content area
        isAccessibilityElement = false

        // Make the background view tappable for accessibility
        bgView.isAccessibilityElement = true
        bgView.accessibilityLabel = "Step \(index + 1): \(step.frequency.name), \(hzText), \(typeText), \(step.durationMinutes) minutes, \(step.mode.label)"
        bgView.accessibilityHint = "Double tap to edit this segment"
        bgView.accessibilityTraits = .button

        trashButton.isAccessibilityElement = true
        trashButton.accessibilityLabel = "Delete step \(index + 1)"
        trashButton.accessibilityHint = "Removes this segment from the sequence"
    }
    
    // Helper for icon assignment
    private var modeIcon: UIImageView { return modeBadge }
}
