import UIKit

class GuidebookViewController: UIViewController {
    
    // MARK: - UI Components
    
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        return sv
    }()
    
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "User Guide"
        
        setupLayout()
        setupContent()
        
        // Close button
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeTapped))
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - Layout
    
    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }
    
    // MARK: - Content Generation
    
    private func setupContent() {
        // 1. Intro
        addSectionTitle("How it Works")
        addCard(icon: "arrow.triangle.2.circlepath", title: "The Flow", body: "1. Build a Sequence: Add steps with specific frequencies and durations.\n2. Start Sequence: The app plays through your steps automatically.\n3. Entrainment: Your brainwaves synchronize with the pulses.")
        
        // 2. Audio Engines
        addSectionTitle("Audio Engine Types")
        addCard(icon: "waveform", title: "Standard Frequency", body: "Uses Isochronic tones. These are distinct, sharp audio pulses. Best for general use and works well without headphones.")
        addCard(icon: "headphones", title: "Binaural Beats", body: "Plays slightly different frequencies in each ear to create a 'phantom' beat inside the brain.\n\n• MUST use Stereo Headphones.\n• smoother, hypnotic experience.\n• 'Resonate Slow' is a special 0.5Hz Delta wave for deep sleep.")
        
        // 3. Frequencies
        addSectionTitle("Frequencies & Uses")
        
        addFreqCard(freq: "10 Hz", name: "Alpha", desc: "Relaxation, Light Meditation, Calm focus.\n\n★ Tinnitus Relief: Many users find 10Hz helps mask or reduce ringing in the ears.", color: .systemGreen)
        
        addFreqCard(freq: "40 Hz", name: "Gamma", desc: "High-level processing, Cognition, Memory.\n\n★ Migraine Relief: Research suggests 40Hz visual/audio stimulation can reduce migraine frequency and severity.", color: .systemBlue)
        
        addFreqCard(freq: "2 Hz", name: "Delta", desc: "Deep Sleep, Healing, Detachment from awareness.", color: .systemIndigo)
        
        addFreqCard(freq: "6 Hz", name: "Theta", desc: "Deep Meditation, REM Sleep, Creativity.", color: .systemPurple)
        
        addFreqCard(freq: "17 Hz", name: "Beta", desc: "Active Focus, Alertness, Analytical thinking.", color: .systemOrange)
    }
    
    // MARK: - Helper Views
    
    private func addSectionTitle(_ text: String) {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .secondaryLabel
        contentStack.addArrangedSubview(label)
    }
    
    private func addCard(icon: String, title: String, body: String) {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 12
        
        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        
        let vStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(iconView)
        container.addSubview(vStack)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            vStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            vStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            vStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            vStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        
        contentStack.addArrangedSubview(container)
    }
    
    private func addFreqCard(freq: String, name: String, desc: String, color: UIColor) {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 12
        
        let freqLabel = UILabel()
        freqLabel.text = freq
        freqLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        freqLabel.textColor = color
        
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        
        let headerStack = UIStackView(arrangedSubviews: [freqLabel, nameLabel])
        headerStack.spacing = 8
        
        let descLabel = UILabel()
        descLabel.text = desc
        descLabel.font = .systemFont(ofSize: 15)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        
        let vStack = UIStackView(arrangedSubviews: [headerStack, descLabel])
        vStack.axis = .vertical
        vStack.spacing = 8
        vStack.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(vStack)
        
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            vStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            vStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            vStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        
        contentStack.addArrangedSubview(container)
    }
}