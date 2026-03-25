import SwiftUI
import SwiftData
import TypingAuthSDK

struct DiagnosticsView: View {
    @State private var diagnostics: RawMatchEngine.RawMatchDiagnostic?
    @Query(sort: \AttemptRecord.timestamp, order: .reverse)
    private var allAttempts: [AttemptRecord]

    private let sdk = TypingAuthSDK.shared
    private let features = FeatureName.ordered

    /// Show the most recent N attempts
    private let displayLimit = 20

    var body: some View {
        List {
            if let diag = diagnostics {
                Section {
                    HStack {
                        Text("Reference Samples")
                        Spacer()
                        Text("\(diag.numSamples)")
                            .bold()
                    }
                    HStack {
                        Text("Digits Tracked")
                        Spacer()
                        Text("\(diag.numDigits)")
                            .bold()
                    }
                    HStack {
                        Text("Features per Digit")
                        Spacer()
                        Text("\(diag.featuresPerDigit)")
                            .bold()
                    }
                } header: {
                    Text("RawMatch Engine")
                } footer: {
                    Text("Each digit independently matches against ALL \(diag.numSamples) training samples. Every feature must be within 2.5\u{03C3} of a single training sample (AND gate).")
                }

                Section("Active Features per Digit") {
                    ForEach(Array(diag.activeFeaturesPerDigit.enumerated()), id: \.offset) { idx, active in
                        HStack {
                            Text("Digit \(idx)")
                                .font(.subheadline)
                            Spacer()
                            Text("\(active) / \(diag.featuresPerDigit) active")
                                .font(.subheadline)
                                .foregroundStyle(active >= 10 ? .green : active >= 6 ? .blue : .orange)
                        }
                    }
                }

                // Recent attempts from SwiftData
                let recentAttempts = Array(allAttempts.prefix(displayLimit).reversed())

                Section {
                    if recentAttempts.isEmpty {
                        Text("No attempts yet — run some tests first")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        // Overall attempt history row
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Overall")
                                .font(.subheadline.weight(.semibold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 3) {
                                    ForEach(recentAttempts) { attempt in
                                        Circle()
                                            .fill(attempt.overallPassed ? Color.green : Color.red)
                                            .frame(width: 10, height: 10)
                                            .overlay {
                                                if attempt.isImpostor == true {
                                                    Circle()
                                                        .stroke(Color.orange, lineWidth: 1.5)
                                                        .frame(width: 13, height: 13)
                                                }
                                            }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)

                        // Per-feature rows
                        ForEach(features, id: \.self) { feature in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.displayName)
                                    .font(.subheadline)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 3) {
                                        ForEach(recentAttempts) { attempt in
                                            let record = attempt.featureRecords.first { $0.featureName == feature.rawValue }
                                            let wasBlocker = record?.wasBlocker ?? false
                                            Circle()
                                                .fill(wasBlocker ? Color.red : Color.green)
                                                .frame(width: 10, height: 10)
                                                .overlay {
                                                    if attempt.isImpostor == true {
                                                        Circle()
                                                            .stroke(Color.orange, lineWidth: 1.5)
                                                            .frame(width: 13, height: 13)
                                                    }
                                                }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Recent Attempts (\(recentAttempts.count))")
                } footer: {
                    if !recentAttempts.isEmpty {
                        let genuineAttempts = recentAttempts.filter { $0.isImpostor == false }
                        let impostorAttempts = recentAttempts.filter { $0.isImpostor == true }
                        let genuinePass = genuineAttempts.filter { $0.overallPassed }.count
                        let impostorPass = impostorAttempts.filter { $0.overallPassed }.count

                        VStack(alignment: .leading, spacing: 2) {
                            if !genuineAttempts.isEmpty {
                                Text("Genuine: \(genuinePass)/\(genuineAttempts.count) passed (\(genuineAttempts.isEmpty ? 0 : genuinePass * 100 / genuineAttempts.count)%)")
                            }
                            if !impostorAttempts.isEmpty {
                                Text("Impostor: \(impostorPass)/\(impostorAttempts.count) passed (\(impostorAttempts.isEmpty ? 0 : impostorPass * 100 / impostorAttempts.count)% FAR)")
                            }
                            Text("Orange ring = impostor-labeled attempt")
                        }
                    }
                }

                // Discrimination analysis
                if allAttempts.contains(where: { $0.isImpostor == true }) && allAttempts.contains(where: { $0.isImpostor == false }) {
                    Section("Feature Discrimination") {
                        ForEach(features, id: \.self) { feature in
                            let genuineBlockRate = blockRate(for: feature, impostor: false)
                            let impostorBlockRate = blockRate(for: feature, impostor: true)
                            let discrimination = impostorBlockRate - genuineBlockRate

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.displayName)
                                        .font(.subheadline)
                                    HStack(spacing: 12) {
                                        Text("Me: \(Int(genuineBlockRate * 100))% blocked")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Imp: \(Int(impostorBlockRate * 100))% blocked")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Text(discrimination > 0.1 ? "Good" : discrimination > 0 ? "Weak" : "Noise")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(discrimination > 0.1 ? .green : discrimination > 0 ? .yellow : .red)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("No enrollment data available")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            diagnostics = sdk.rawMatchDiagnostics()
        }
    }

    /// Compute how often a feature blocks for genuine or impostor attempts
    private func blockRate(for feature: FeatureName, impostor: Bool) -> Double {
        let attempts = allAttempts.filter { $0.isImpostor == impostor }
        guard !attempts.isEmpty else { return 0 }
        let blocked = attempts.filter { attempt in
            attempt.featureRecords.first { $0.featureName == feature.rawValue }?.wasBlocker ?? false
        }.count
        return Double(blocked) / Double(attempts.count)
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
    }
}
