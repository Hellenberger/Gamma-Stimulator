//
//  DigitalClockView.swift
//  Gamma Stimulator
//

import UIKit

final class DigitalClockView: UIView {
    private let timeLabel = UILabel()
    private var timer: Timer?
    private lazy var formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Background styling
        backgroundColor     = UIColor.black.withAlphaComponent(0.10)
        layer.cornerRadius  = 16
        layer.masksToBounds = true

        // Label styling
        timeLabel.textColor     = .white
        timeLabel.font          = .monospacedDigitSystemFont(ofSize: 80, weight: .medium)
        timeLabel.textAlignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        // Make the view "wrap" the label with padding on all sides
        let insetH: CGFloat = 0
        let insetV: CGFloat = 8
        
        
        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(equalTo: topAnchor, constant: insetV),
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insetH),
            trailingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: insetH),
            bottomAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: insetV)
        ])

        // Hug the content so the container stays compact
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        startTimer()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // If the parent hasn't constrained this view, pin it to bottom-right of the screen.
        guard let s = superview else { return }

        if translatesAutoresizingMaskIntoConstraints {
            translatesAutoresizingMaskIntoConstraints = false
            let guide = s.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
                bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16)
            ])
        }
    }

    private func startTimer() {
        timer?.invalidate()

        // Fire at the next whole minute, then every 60 s
        let now = Date()
        let nextMinute = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .strict
        ) ?? now.addingTimeInterval(60)

        timer = Timer(fireAt: nextMinute,
                      interval: 60,
                      target: self,
                      selector: #selector(updateTime),
                      userInfo: nil,
                      repeats: true)
        if let timer { RunLoop.main.add(timer, forMode: .common) }

        updateTime() // show current time immediately
    }

    @objc private func updateTime() {
        timeLabel.text = formatter.string(from: Date())
    }

    deinit {
        timer?.invalidate()
    }
}
