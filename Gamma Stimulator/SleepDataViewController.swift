import UIKit
import Foundation
import DGCharts

class SleepDataViewController: UIViewController {
    private let stackView = UIStackView()
    
    private let cyclesLabel = UILabel()
    private let slowWaveLabel = UILabel()
    private let stimulationLabel = UILabel()
    
    private var cyclesCount = 0
    private var slowWaveCount = 0
    private var stimulationCount = 0
    private var sleepChartView = LineChartView()
    private var stageSamples: [(time: Date, stage: SleepStage)] = []
    
    let chart = LineChartView()
    let entry = ChartDataEntry(x: 0, y: 0)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        // Start observing data from PhoneWatchConnector
        registerForWatchUpdates()
    }
    
    private func setupUI() {
        title = "Sleep Statistics"
        
        // Set background to blue
        view.backgroundColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) // System blue color
        
        // Setup stack view
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        // Configure labels with white text
        setupLabel(cyclesLabel)
        setupLabel(slowWaveLabel)
        setupLabel(stimulationLabel)
        
        // Add labels to stack view
        stackView.addArrangedSubview(cyclesLabel)
        stackView.addArrangedSubview(slowWaveLabel)
        stackView.addArrangedSubview(stimulationLabel)
        
        // Set constraints with proper indentation
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40), // Increased indentation
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        sleepChartView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sleepChartView)

        NSLayoutConstraint.activate([
            sleepChartView.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 30),
            sleepChartView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            sleepChartView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            sleepChartView.heightAnchor.constraint(equalToConstant: 250)
        ])
        
        // Add close button
        setupCloseButton()
        
        // Initial update
        updateLabels()
    }
    
    private func setupLabel(_ label: UILabel) {
        label.font = UIFont.systemFont(ofSize: 22) // Slightly larger font
        label.textColor = .white // White text
    }
    
    private func setupCloseButton() {
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        closeButton.addTarget(self, action: #selector(closeScreen), for: .touchUpInside)
        
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    @objc private func closeScreen() {
        dismiss(animated: true)
    }
    
    private func updateLabels() {
        cyclesLabel.text = "Number of Sleep Cycles: \(cyclesCount)"
        slowWaveLabel.text = "Number of Slow Wave Periods: \(slowWaveCount)"
        stimulationLabel.text = "Stimulation Triggers: \(stimulationCount)"
    }
    
    private func registerForWatchUpdates() {
        // Add observer for sleep stage updates from PhoneWatchConnector
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSleepStageUpdate),
            name: NSNotification.Name("SleepStageUpdate"),
            object: nil
        )
        
        // Add observer for stimulation triggers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStimulationTrigger),
            name: NSNotification.Name("StimulationTrigger"),
            object: nil
        )
    }
    
    @objc private func handleSleepStageUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let stageValue = userInfo["stage"] as? Int,
              let stage = SleepStage(rawValue: stageValue) else {
            return
        }
        
        // Count slow wave (deep sleep) periods
        if stage == .deep {
            slowWaveCount += 1
        }
        
        // Detect sleep cycle transitions (e.g., when going from REM to another stage)
        if let previousStage = userInfo["previousStage"] as? Int,
           let previous = SleepStage(rawValue: previousStage),
           previous == .rem && stage != .rem {
            cyclesCount += 1
        }
        let timestamp = Date()
        stageSamples.append((timestamp, stage))
        if stageSamples.count > 300 {
            stageSamples.removeFirst()
        }
        updateChart()
        // Update UI on main thread
        DispatchQueue.main.async {
            self.updateLabels()
        }
    }
    
    private func updateChart() {
        let entries = stageSamples.map { sample in
            ChartDataEntry(x: sample.time.timeIntervalSince1970,
                           y: Double(sample.stage.rawValue))
        }

        let dataSet = LineChartDataSet(entries: entries, label: "Sleep Stage")
        dataSet.colors = [UIColor.white]
        dataSet.circleColors = [UIColor.yellow]
        dataSet.valueColors = [UIColor.white]
        dataSet.circleRadius = 3

        let data = LineChartData(dataSet: dataSet)
        sleepChartView.data = data

        sleepChartView.xAxis.labelTextColor = UIColor.white
        sleepChartView.leftAxis.labelTextColor = UIColor.white
        sleepChartView.rightAxis.labelTextColor = UIColor.white
        sleepChartView.legend.textColor = UIColor.white
        sleepChartView.backgroundColor = UIColor.clear

        sleepChartView.xAxis.valueFormatter = DateValueFormatter() // Optional: show HH:mm instead of raw time
    }

    @objc private func handleStimulationTrigger(_ notification: Notification) {
        stimulationCount += 1
        
        DispatchQueue.main.async {
            self.updateLabels()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

class DateValueFormatter: AxisValueFormatter {
    private let formatter: DateFormatter

    init() {
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        return formatter.string(from: Date(timeIntervalSince1970: value))
    }
}

