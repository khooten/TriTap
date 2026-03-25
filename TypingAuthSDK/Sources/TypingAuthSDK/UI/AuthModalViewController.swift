import UIKit

public final class AuthModalViewController: UIViewController, PasscodeKeyboardDelegate {
    private let reason: String
    private let passcodeLength: Int
    private let motionRecorder = MotionRecorder()
    private var keyboard: PasscodeKeyboardView!
    private var dotsView: PasscodeDotsView!
    private var reasonLabel: UILabel!
    private var viewPresentedTimestamp: TimeInterval = 0
    private var digitCount = 0

    public var onComplete: ((AuthenticationSample) -> Void)?
    public var onCancel: (() -> Void)?

    public init(reason: String, passcodeLength: Int = 6) {
        self.reason = reason
        self.passcodeLength = passcodeLength
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewPresentedTimestamp = ProcessInfo.processInfo.systemUptime
        motionRecorder.start(viewPresentedAt: viewPresentedTimestamp)
    }

    private func setupUI() {
        // Cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Reason label
        reasonLabel = UILabel()
        reasonLabel.text = reason
        reasonLabel.font = .systemFont(ofSize: 18, weight: .medium)
        reasonLabel.textAlignment = .center
        reasonLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reasonLabel)

        // Dots
        dotsView = PasscodeDotsView(count: passcodeLength)
        dotsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dotsView)

        // Keyboard
        keyboard = PasscodeKeyboardView(passcodeLength: passcodeLength, viewPresentedAt: ProcessInfo.processInfo.systemUptime)
        keyboard.delegate = self
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            reasonLabel.topAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 40),
            reasonLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            dotsView.topAnchor.constraint(equalTo: reasonLabel.bottomAnchor, constant: 32),
            dotsView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dotsView.heightAnchor.constraint(equalToConstant: 24),

            keyboard.topAnchor.constraint(equalTo: dotsView.bottomAnchor, constant: 48),
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            keyboard.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.45),
        ])
    }

    // MARK: - PasscodeKeyboardDelegate

    public func keyboardDidEnterDigit(_ digit: Int, touchEvent: TouchEvent) {
        digitCount += 1
        dotsView.setFilledCount(digitCount)
    }

    public func keyboardDidDeleteDigit() {
        digitCount = max(0, digitCount - 1)
        dotsView.setFilledCount(digitCount)
    }

    public func keyboardDidComplete(digits: [Int]) {
        motionRecorder.stop()

        let touchEvents = keyboard.collectedTouchEvents()
        let motionSnapshots = motionRecorder.collectedSnapshots()

        let reactionTime: TimeInterval
        if let firstTouch = touchEvents.first {
            reactionTime = firstTouch.touchBegan
        } else {
            reactionTime = 0
        }

        let totalDuration: TimeInterval
        if let first = touchEvents.first, let last = touchEvents.last {
            totalDuration = last.touchEnded - first.touchBegan
        } else {
            totalDuration = 0
        }

        let sample = AuthenticationSample(
            label: .unknown,
            touchEvents: touchEvents,
            motionSamples: motionSnapshots,
            reactionTime: reactionTime,
            totalDuration: totalDuration
        )

        onComplete?(sample)
    }

    @objc private func cancelTapped() {
        motionRecorder.stop()
        onCancel?()
        dismiss(animated: true)
    }
}
