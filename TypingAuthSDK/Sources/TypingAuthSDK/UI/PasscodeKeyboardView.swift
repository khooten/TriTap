import UIKit

public protocol PasscodeKeyboardDelegate: AnyObject {
    func keyboardDidEnterDigit(_ digit: Int, touchEvent: TouchEvent)
    func keyboardDidDeleteDigit()
    func keyboardDidComplete(digits: [Int])
}

// MARK: - Circular Key Button (Apple passcode style)

protocol KeyButtonDelegate: AnyObject {
    func keyButtonTouchBegan(_ key: KeyButton, touch: UITouch)
    func keyButtonTouchMoved(_ key: KeyButton, touch: UITouch)
    func keyButtonTouchEnded(_ key: KeyButton, touch: UITouch)
}

final class KeyButton: UIView {
    let digit: Int
    weak var keyDelegate: KeyButtonDelegate?
    private let digitLabel = UILabel()
    private let lettersLabel = UILabel()
    private var activeTouch: UITouch?

    private static let keySize: CGFloat = 80
    private static let letterMap: [Int: String] = [
        2: "A B C", 3: "D E F", 4: "G H I",
        5: "J K L", 6: "M N O", 7: "P Q R S",
        8: "T U V", 9: "W X Y Z",
    ]

    init(digit: Int, title: String) {
        self.digit = digit
        super.init(frame: .zero)

        isUserInteractionEnabled = true

        if digit >= 0 {
            // Circular digit key
            backgroundColor = .tertiarySystemFill
            layer.cornerRadius = Self.keySize / 2

            digitLabel.text = title
            digitLabel.font = .systemFont(ofSize: 36, weight: .light)
            digitLabel.textColor = .label
            digitLabel.textAlignment = .center
            digitLabel.isUserInteractionEnabled = false
            digitLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(digitLabel)

            if let letters = Self.letterMap[digit] {
                lettersLabel.text = letters
                lettersLabel.font = .systemFont(ofSize: 10, weight: .semibold)
                lettersLabel.textColor = .label
                lettersLabel.textAlignment = .center
                lettersLabel.isUserInteractionEnabled = false
                lettersLabel.translatesAutoresizingMaskIntoConstraints = false
                addSubview(lettersLabel)

                NSLayoutConstraint.activate([
                    digitLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                    digitLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
                    lettersLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                    lettersLabel.topAnchor.constraint(equalTo: digitLabel.bottomAnchor, constant: -4),
                ])
            } else {
                // 0 and 1 — no letters
                NSLayoutConstraint.activate([
                    digitLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                    digitLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                ])
            }

            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: Self.keySize),
                heightAnchor.constraint(equalToConstant: Self.keySize),
            ])
        } else {
            // Delete button — text only, no circle
            backgroundColor = .clear
            digitLabel.text = title
            digitLabel.font = .systemFont(ofSize: 16, weight: .regular)
            digitLabel.textColor = .label
            digitLabel.textAlignment = .center
            digitLabel.isUserInteractionEnabled = false
            digitLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(digitLabel)

            NSLayoutConstraint.activate([
                digitLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                digitLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                widthAnchor.constraint(equalToConstant: Self.keySize),
                heightAnchor.constraint(equalToConstant: Self.keySize),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        // If there's already an active touch (fast typing), end the previous one first
        if activeTouch != nil {
            activeTouch = nil
        }
        activeTouch = touch
        if digit >= 0 {
            backgroundColor = .secondarySystemFill
        }
        keyDelegate?.keyButtonTouchBegan(self, touch: touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch === activeTouch else { return }
        keyDelegate?.keyButtonTouchMoved(self, touch: touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch === activeTouch else { return }
        activeTouch = nil
        if digit >= 0 {
            backgroundColor = .tertiarySystemFill
        }
        keyDelegate?.keyButtonTouchEnded(self, touch: touch)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch != nil else { return }
        // Treat cancelled as ended — don't silently drop the keystroke
        if let touch = touches.first, touch === activeTouch {
            keyDelegate?.keyButtonTouchEnded(self, touch: touch)
        }
        activeTouch = nil
        if digit >= 0 {
            backgroundColor = .tertiarySystemFill
        }
    }
}

// MARK: - Passcode Keyboard View

public final class PasscodeKeyboardView: UIView, KeyButtonDelegate {
    public weak var delegate: PasscodeKeyboardDelegate?

    private var enteredDigits: [Int] = []
    private let passcodeLength: Int
    private var digitKeys: [KeyButton] = []

    private let touchRecorder: TouchEventRecorder
    private var pendingDigit: Int?

    // Apple passcode spacing
    private static let keySize: CGFloat = 80
    private static let horizontalSpacing: CGFloat = 24
    private static let verticalSpacing: CGFloat = 16

    public init(passcodeLength: Int = 6, viewPresentedAt: TimeInterval) {
        self.passcodeLength = passcodeLength
        self.touchRecorder = TouchEventRecorder(viewPresentedAt: viewPresentedAt)
        super.init(frame: .zero)
        setupKeyboard()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(passcodeLength:viewPresentedAt:)")
    }

    private func setupKeyboard() {
        backgroundColor = .clear

        let layout: [[Int]] = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
            [-1, 0, -2],
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Self.verticalSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        for row in layout {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = Self.horizontalSpacing
            rowStack.alignment = .center

            for digit in row {
                if digit == -1 {
                    // Invisible spacer same size as a key
                    let spacer = UIView()
                    spacer.isUserInteractionEnabled = false
                    spacer.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        spacer.widthAnchor.constraint(equalToConstant: Self.keySize),
                        spacer.heightAnchor.constraint(equalToConstant: Self.keySize),
                    ])
                    rowStack.addArrangedSubview(spacer)
                } else {
                    let title = digit == -2 ? "Delete" : "\(digit)"
                    let key = KeyButton(digit: digit, title: title)
                    key.keyDelegate = self
                    digitKeys.append(key)
                    rowStack.addArrangedSubview(key)
                }
            }
            stack.addArrangedSubview(rowStack)
        }
    }

    // MARK: - KeyButtonDelegate

    func keyButtonTouchBegan(_ key: KeyButton, touch: UITouch) {
        let digit = key.digit
        guard digit >= 0, enteredDigits.count < passcodeLength else { return }

        let boundsInSelf = key.convert(key.bounds, to: self)
        touchRecorder.recordTouchBegan(touch, in: self, keyBounds: boundsInSelf)
        pendingDigit = digit
    }

    func keyButtonTouchMoved(_ key: KeyButton, touch: UITouch) {
        touchRecorder.recordTouchMoved(touch)
    }

    func keyButtonTouchEnded(_ key: KeyButton, touch: UITouch) {
        let digit = key.digit

        if digit == -2 {
            guard !enteredDigits.isEmpty else { return }
            enteredDigits.removeLast()
            delegate?.keyboardDidDeleteDigit()
            return
        }

        guard digit >= 0, enteredDigits.count < passcodeLength else {
            pendingDigit = nil
            return
        }
        pendingDigit = nil

        let boundsInSelf = key.convert(key.bounds, to: self)
        touchRecorder.recordTouchEnded(touch, in: self, keyBounds: boundsInSelf)
        enteredDigits.append(digit)

        if let lastEvent = touchRecorder.collectedEvents().last {
            delegate?.keyboardDidEnterDigit(digit, touchEvent: lastEvent)
        }

        if enteredDigits.count >= passcodeLength {
            delegate?.keyboardDidComplete(digits: enteredDigits)
        }
    }

    // MARK: - Public

    public func collectedTouchEvents() -> [TouchEvent] {
        touchRecorder.collectedEvents()
    }

    public func reset() {
        enteredDigits.removeAll()
        touchRecorder.reset()
        pendingDigit = nil
    }
}
