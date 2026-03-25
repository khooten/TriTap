import UIKit
import SwiftUI
import TypingAuthSDK

/// Unified capture view for both Training and Testing.
/// The keyboard, dots, and feedback are always present.
/// A segmented control switches between Train and Test modes.
/// In Train mode: samples are saved, counter/progress shown.
/// In Test mode: samples are scored, passcode revealed, score history shown.
final class PersonalCaptureViewController: UIViewController, PasscodeKeyboardDelegate {
    private let motionRecorder = MotionRecorder()
    private var keyboard: PasscodeKeyboardView!
    private var dotsView: PasscodeDotsView!
    var modeControl: UISegmentedControl!
    private var subtitleLabel: UILabel!
    private var checkmarkView: UIImageView!
    private var doneButton: UIButton!
    private var viewPresentedTimestamp: TimeInterval = 0
    private var digitCount = 0
    private var lockedPasscode: [Int]?

    // Training panel
    private var trainPanel: UIView!
    private var counterLabel: UILabel!
    private var progressBar: UIProgressView!
    private var sampleCount = 0
    private let minimumSamples = 20

    // Test panel
    private var testPanel: UIView!
    private var passcodeRevealLabel: UILabel!
    private var lastScoreLabel: UILabel!
    private var scoreHistoryStack: UIStackView!
    private var impostorToggle: UISegmentedControl!

    // Current mode
    private var isTesting: Bool {
        modeControl?.selectedSegmentIndex == 1
    }

    // Callbacks
    var onSampleCaptured: ((AuthenticationSample) -> Void)?
    var onAuthAttempt: ((AuthenticationSample) -> AuthResult)?
    var onAttemptRecorded: ((RawMatchEngine.AttemptFeatureResult, Bool?) -> Void)?  // (result, isImpostor)
    var onDone: (() -> Void)?

    /// Start in training or test mode
    var startInTestMode = false

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-apply mode in case SwiftUI set startInTestMode after viewDidLoad
        modeControl.selectedSegmentIndex = startInTestMode ? 1 : 0
        updateModeUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startNewCapture()
    }

    // MARK: - Setup

    private func setupUI() {
        let sdk = TypingAuthSDK.shared
        sampleCount = sdk.enrollmentSampleCount

        // Done button (top right)
        doneButton = UIButton(type: .system)
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)

        // Segmented control: Train | Test
        modeControl = UISegmentedControl(items: ["Train", "Test"])
        modeControl.selectedSegmentIndex = startInTestMode ? 1 : 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeControl)

        // Disable Test segment if not enough samples
        let hasEnoughSamples = sampleCount >= minimumSamples || sdk.isEnrolled
        modeControl.setEnabled(hasEnoughSamples, forSegmentAt: 1)

        // Subtitle
        subtitleLabel = UILabel()
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        // --- Training Panel ---
        trainPanel = UIView()
        trainPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(trainPanel)

        counterLabel = UILabel()
        counterLabel.text = "\(sampleCount) / \(minimumSamples)"
        counterLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        counterLabel.textColor = .secondaryLabel
        counterLabel.textAlignment = .center
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        trainPanel.addSubview(counterLabel)

        progressBar = UIProgressView(progressViewStyle: .bar)
        progressBar.progress = Float(min(sampleCount, minimumSamples)) / Float(minimumSamples)
        progressBar.tintColor = sampleCount >= minimumSamples ? .systemGreen : .systemBlue
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        trainPanel.addSubview(progressBar)

        NSLayoutConstraint.activate([
            counterLabel.topAnchor.constraint(equalTo: trainPanel.topAnchor),
            counterLabel.centerXAnchor.constraint(equalTo: trainPanel.centerXAnchor),
            progressBar.topAnchor.constraint(equalTo: counterLabel.bottomAnchor, constant: 8),
            progressBar.leadingAnchor.constraint(equalTo: trainPanel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trainPanel.trailingAnchor),
            progressBar.bottomAnchor.constraint(equalTo: trainPanel.bottomAnchor),
        ])

        // --- Test Panel ---
        testPanel = UIView()
        testPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(testPanel)

        passcodeRevealLabel = UILabel()
        if let digits = sdk.enrolledPasscode {
            passcodeRevealLabel.text = "Passcode: " + digits.map { String($0) }.joined(separator: "  ")
        } else {
            passcodeRevealLabel.text = ""
        }
        passcodeRevealLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        passcodeRevealLabel.textColor = .tertiaryLabel
        passcodeRevealLabel.textAlignment = .center
        passcodeRevealLabel.translatesAutoresizingMaskIntoConstraints = false
        testPanel.addSubview(passcodeRevealLabel)

        lastScoreLabel = UILabel()
        lastScoreLabel.text = ""
        lastScoreLabel.font = .monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        lastScoreLabel.textAlignment = .center
        lastScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        testPanel.addSubview(lastScoreLabel)

        scoreHistoryStack = UIStackView()
        scoreHistoryStack.axis = .horizontal
        scoreHistoryStack.spacing = 6
        scoreHistoryStack.alignment = .center
        scoreHistoryStack.translatesAutoresizingMaskIntoConstraints = false
        testPanel.addSubview(scoreHistoryStack)

        impostorToggle = UISegmentedControl(items: ["Me", "Impostor"])
        impostorToggle.selectedSegmentIndex = 0
        impostorToggle.translatesAutoresizingMaskIntoConstraints = false
        testPanel.addSubview(impostorToggle)

        NSLayoutConstraint.activate([
            passcodeRevealLabel.topAnchor.constraint(equalTo: testPanel.topAnchor),
            passcodeRevealLabel.centerXAnchor.constraint(equalTo: testPanel.centerXAnchor),
            lastScoreLabel.topAnchor.constraint(equalTo: passcodeRevealLabel.bottomAnchor, constant: 8),
            lastScoreLabel.centerXAnchor.constraint(equalTo: testPanel.centerXAnchor),
            scoreHistoryStack.topAnchor.constraint(equalTo: lastScoreLabel.bottomAnchor, constant: 4),
            scoreHistoryStack.centerXAnchor.constraint(equalTo: testPanel.centerXAnchor),
            scoreHistoryStack.heightAnchor.constraint(equalToConstant: 24),
            impostorToggle.topAnchor.constraint(equalTo: scoreHistoryStack.bottomAnchor, constant: 8),
            impostorToggle.centerXAnchor.constraint(equalTo: testPanel.centerXAnchor),
            impostorToggle.bottomAnchor.constraint(equalTo: testPanel.bottomAnchor),
        ])

        // Checkmark overlay
        let checkConfig = UIImage.SymbolConfiguration(pointSize: 48, weight: .bold)
        checkmarkView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: checkConfig))
        checkmarkView.tintColor = .systemGreen
        checkmarkView.alpha = 0
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(checkmarkView)

        // Dots
        dotsView = PasscodeDotsView(count: 6)
        dotsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dotsView)

        // Keyboard
        keyboard = PasscodeKeyboardView(passcodeLength: 6, viewPresentedAt: 0)
        keyboard.delegate = self
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)

        // Layout
        NSLayoutConstraint.activate([
            doneButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            modeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            modeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeControl.widthAnchor.constraint(equalToConstant: 160),

            subtitleLabel.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            // Both panels occupy the same space
            trainPanel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            trainPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            trainPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            testPanel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            testPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            testPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            dotsView.topAnchor.constraint(greaterThanOrEqualTo: trainPanel.bottomAnchor, constant: 16),
            dotsView.topAnchor.constraint(greaterThanOrEqualTo: testPanel.bottomAnchor, constant: 16),
            dotsView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dotsView.heightAnchor.constraint(equalToConstant: 24),

            checkmarkView.centerXAnchor.constraint(equalTo: dotsView.centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: dotsView.centerYAnchor),

            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        updateModeUI()
    }

    func updateModeUI() {
        let testing = isTesting
        trainPanel.isHidden = testing
        testPanel.isHidden = !testing

        if testing {
            subtitleLabel.text = "It's not WHAT you type — it's HOW you type it"
            subtitleLabel.textColor = .secondaryLabel
        } else {
            subtitleLabel.text = "Type your passcode — vary your grip between entries"
            subtitleLabel.textColor = .secondaryLabel
        }
    }

    @objc private func modeChanged() {
        if isTesting {
            // Rebuild clusters before switching to test
            TypingAuthSDK.shared.finalizeEnrollment()
            // Update passcode display
            if let digits = TypingAuthSDK.shared.enrolledPasscode {
                passcodeRevealLabel.text = "Passcode: " + digits.map { String($0) }.joined(separator: "  ")
            }
        }
        updateModeUI()
        startNewCapture()
    }

    // MARK: - Capture Lifecycle

    private func startNewCapture() {
        viewPresentedTimestamp = ProcessInfo.processInfo.systemUptime

        keyboard.removeFromSuperview()
        keyboard = PasscodeKeyboardView(passcodeLength: 6, viewPresentedAt: viewPresentedTimestamp)
        keyboard.delegate = self
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)

        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        digitCount = 0
        dotsView.setFilledCount(0)
        motionRecorder.reset()
        motionRecorder.start(viewPresentedAt: viewPresentedTimestamp)
    }

    private func flashFeedback(passed: Bool) {
        let symbolName = passed ? "checkmark.circle.fill" : "xmark.circle.fill"
        let color: UIColor = passed ? .systemGreen : .systemRed
        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .bold)
        checkmarkView.image = UIImage(systemName: symbolName, withConfiguration: config)
        checkmarkView.tintColor = color

        checkmarkView.alpha = 1
        checkmarkView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: 0.2, animations: {
            self.checkmarkView.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0.2) {
                self.checkmarkView.alpha = 0
            }
        }
    }

    private func updateProgress() {
        counterLabel?.text = "\(sampleCount) / \(minimumSamples)"
        let progress = Float(min(sampleCount, minimumSamples)) / Float(minimumSamples)
        progressBar?.setProgress(progress, animated: true)
        if sampleCount >= minimumSamples {
            progressBar?.tintColor = .systemGreen
            modeControl.setEnabled(true, forSegmentAt: 1)
        }
    }

    private func addScoreToHistory(_ score: Double, passed: Bool) {
        guard let stack = scoreHistoryStack else { return }

        let pill = UILabel()
        pill.text = "\(Int(score * 100))"
        pill.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        pill.textColor = .white
        pill.textAlignment = .center
        pill.backgroundColor = passed ? .systemGreen : .systemRed
        pill.layer.cornerRadius = 10
        pill.clipsToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            pill.heightAnchor.constraint(equalToConstant: 20),
        ])

        stack.addArrangedSubview(pill)

        while stack.arrangedSubviews.count > 10 {
            let old = stack.arrangedSubviews[0]
            stack.removeArrangedSubview(old)
            old.removeFromSuperview()
        }
    }

    private func buildSample() -> AuthenticationSample {
        let touchEvents = keyboard.collectedTouchEvents()
        let motionSnapshots = motionRecorder.collectedSnapshots()
        let reactionTime = touchEvents.first?.touchBegan ?? 0
        let totalDuration: TimeInterval
        if let first = touchEvents.first, let last = touchEvents.last {
            totalDuration = last.touchEnded - first.touchBegan
        } else {
            totalDuration = 0
        }

        return AuthenticationSample(
            label: .authorized,
            touchEvents: touchEvents,
            motionSamples: motionSnapshots,
            reactionTime: reactionTime,
            totalDuration: totalDuration
        )
    }

    // MARK: - PasscodeKeyboardDelegate

    func keyboardDidEnterDigit(_ digit: Int, touchEvent: TouchEvent) {
        digitCount += 1
        dotsView.setFilledCount(digitCount)
    }

    func keyboardDidDeleteDigit() {
        digitCount = 0
        dotsView.setFilledCount(0)
        keyboard.reset()
        motionRecorder.reset()
        motionRecorder.start(viewPresentedAt: viewPresentedTimestamp)
        subtitleLabel.text = "Reset — start over"
        subtitleLabel.textColor = .systemOrange
    }

    func keyboardDidComplete(digits: [Int]) {
        // Passcode validation (both modes)
        if let locked = lockedPasscode {
            if digits != locked {
                motionRecorder.stop()
                dotsView.shake()
                subtitleLabel.text = "Wrong code — doesn't match your first entry"
                subtitleLabel.textColor = .systemRed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startNewCapture()
                }
                return
            }
        } else {
            lockedPasscode = digits
            if TypingAuthSDK.shared.enrolledPasscode == nil {
                TypingAuthSDK.shared.setEnrolledPasscode(digits)
            }
        }

        motionRecorder.stop()
        let sample = buildSample()

        if isTesting {
            // Score and show result
            if let result = onAuthAttempt?(sample) {
                let pct = Int(result.confidence * 100)
                lastScoreLabel.text = "\(pct)%"
                lastScoreLabel.textColor = result.passed ? .systemGreen : .systemRed
                subtitleLabel.text = result.passed ? "Authenticated" : "Rejected"
                subtitleLabel.textColor = result.passed ? .systemGreen : .systemRed
                addScoreToHistory(result.confidence, passed: result.passed)
                flashFeedback(passed: result.passed)

                // Persist to SwiftData with user label
                let isImpostor = impostorToggle.selectedSegmentIndex == 1
                let sdk = TypingAuthSDK.shared
                if let lastAttempt = sdk.recentAttemptHistory().last {
                    onAttemptRecorded?(lastAttempt, isImpostor)
                }
            }
        } else {
            // Training — save sample
            sampleCount += 1
            updateProgress()
            onSampleCaptured?(sample)
            flashFeedback(passed: true)
            subtitleLabel.text = "Saved!"
            subtitleLabel.textColor = .systemGreen
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startNewCapture()
        }
    }

    @objc private func doneTapped() {
        motionRecorder.stop()
        onDone?()
        dismiss(animated: true)
    }
}

// MARK: - SwiftUI Wrapper

struct PersonalCaptureView: UIViewControllerRepresentable {
    var startInTestMode: Bool = false
    let onSampleCaptured: (AuthenticationSample) -> Void
    let onAuthAttempt: (AuthenticationSample) -> AuthResult
    var onAttemptRecorded: ((RawMatchEngine.AttemptFeatureResult, Bool?) -> Void)?
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> PersonalCaptureViewController {
        let vc = PersonalCaptureViewController()
        vc.startInTestMode = startInTestMode
        vc.onSampleCaptured = onSampleCaptured
        vc.onAuthAttempt = onAuthAttempt
        vc.onAttemptRecorded = onAttemptRecorded
        vc.onDone = onDone
        return vc
    }

    func updateUIViewController(_ vc: PersonalCaptureViewController, context: Context) {
        // If the mode changed (e.g., Quick Test sets startInTestMode=true),
        // update the VC and refresh the UI
        if vc.startInTestMode != startInTestMode {
            vc.startInTestMode = startInTestMode
            vc.modeControl.selectedSegmentIndex = startInTestMode ? 1 : 0
            vc.updateModeUI()
        }
    }
}
