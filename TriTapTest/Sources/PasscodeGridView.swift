import SwiftUI

struct PasscodeGridView: View {
    @Binding var enteredDigits: [String]
    let onComplete: () -> Void

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(1...9, id: \.self) { digit in
                DigitButton(digit: "\(digit)") {
                    appendDigit("\(digit)")
                }
            }
            Color.clear.frame(height: 64) // spacer
            DigitButton(digit: "0") {
                appendDigit("0")
            }
            DigitButton(digit: "\u{232B}", isDestructive: true) {
                if !enteredDigits.isEmpty {
                    enteredDigits.removeLast()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func appendDigit(_ d: String) {
        guard enteredDigits.count < 6 else { return }
        enteredDigits.append(d)
        if enteredDigits.count >= 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onComplete()
            }
        }
    }
}

struct DigitButton: View {
    let digit: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(digit)
                .font(.system(size: 28, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
