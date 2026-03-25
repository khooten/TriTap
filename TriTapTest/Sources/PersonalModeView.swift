import SwiftUI
import SwiftData
import TypingAuthSDK

struct PersonalModeView: View {
    @Binding var isEnrolled: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var samplesCollected = 0
    @State private var captureMode: CaptureMode?

    enum CaptureMode: Identifiable {
        case train, test
        var id: String { self == .train ? "train" : "test" }
    }
    @State private var showResetConfirm = false
    @State private var stats: EnrollmentStats?

    private let sdk = TypingAuthSDK.shared
    private let minimumSamples = 20

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Info
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Typing Pattern Lock", systemImage: "lock.shield")
                            .font(.headline)
                        if samplesCollected == 0 {
                            Text("Choose a private 6-digit passcode and train your typing signature. Vary your grip — right thumb, left thumb, index finger, on a table.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(samplesCollected) training samples across \(stats?.digitCount ?? 6) digit positions. Add more training to improve accuracy, or test to see if it recognizes you.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                // Progress (if training has started)
                if samplesCollected > 0 {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(min(samplesCollected, minimumSamples)), total: Double(minimumSamples))
                            .tint(samplesCollected >= minimumSamples ? .green : .blue)
                        Text("\(samplesCollected) samples")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                // Training stats
                if let stats, stats.sampleCount > 0 {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Training Quality")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(stats.quality)
                                    .font(.subheadline)
                                    .foregroundStyle(qualityColor(stats.quality))
                            }

                            HStack {
                                Text("Reference samples:")
                                Spacer()
                                Text("\(stats.sampleCount)")
                                    .bold()
                            }
                            .font(.caption)

                            if !stats.activeFeaturesPerDigit.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(Array(stats.activeFeaturesPerDigit.enumerated()), id: \.offset) { idx, active in
                                        VStack(spacing: 2) {
                                            Text("\(active)")
                                                .font(.system(size: 16, weight: .bold))
                                            Text("D\(idx)")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                                Text("Active features per digit")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Buttons
                VStack(spacing: 12) {
                    // Train + Test — opens the unified capture view
                    Button {
                        captureMode = .train
                    } label: {
                        Label(samplesCollected == 0 ? "Start Training" : "Train", systemImage: "figure.walk")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    // Quick Test shortcut (only if enough samples)
                    if samplesCollected >= minimumSamples {
                        Button {
                            sdk.finalizeEnrollment()
                            tuneFromHistory()
                            isEnrolled = true
                            captureMode = .test
                        } label: {
                            Label("Quick Test", systemImage: "checkmark.shield")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }

                    // Diagnostics
                    if samplesCollected >= 3 {
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            Label("Feature Diagnostics", systemImage: "chart.bar.xaxis")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    // Reset
                    if samplesCollected > 0 {
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Label("Reset Training Data", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .confirmationDialog(
                            "Reset all training data?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Delete \(samplesCollected) samples", role: .destructive) {
                                sdk.resetEnrollment()
                                isEnrolled = false
                                samplesCollected = 0
                                stats = nil
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will erase all training data and you'll need to start over.")
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .fullScreenCover(item: $captureMode) { mode in
            PersonalCaptureView(
                startInTestMode: mode == .test,
                onSampleCaptured: { sample in
                    sdk.addEnrollmentSample(sample)
                    samplesCollected = sdk.enrollmentSampleCount
                },
                onAuthAttempt: { sample in
                    sdk.authenticateSample(sample)
                },
                onAttemptRecorded: { [modelContext] attemptResult, isImpostor in
                    let record = AttemptRecord(
                        overallPassed: attemptResult.passed,
                        overallScore: attemptResult.score,
                        isImpostor: isImpostor
                    )
                    for feature in FeatureName.ordered {
                        let wasBlocker = !(attemptResult.featureResults[feature] ?? true)
                        let zScore = attemptResult.featureZScores[feature] ?? 0
                        let featureRec = FeatureRecord(
                            featureName: feature.rawValue,
                            wasBlocker: wasBlocker,
                            bestZScore: zScore
                        )
                        record.featureRecords.append(featureRec)
                    }
                    modelContext.insert(record)
                    try? modelContext.save()
                },
                onFinalized: { [modelContext] in
                    // Auto-tune tolerances from labeled SwiftData history
                    let descriptor = FetchDescriptor<AttemptRecord>(
                        predicate: #Predicate { $0.isImpostor != nil }
                    )
                    guard let labeled = try? modelContext.fetch(descriptor),
                          labeled.contains(where: { $0.isImpostor == true }),
                          labeled.contains(where: { $0.isImpostor == false }) else { return }

                    var history: [(feature: FeatureName, zScore: Double, isImpostor: Bool)] = []
                    for attempt in labeled {
                        guard let isImp = attempt.isImpostor else { continue }
                        for rec in attempt.featureRecords {
                            guard let feature = FeatureName(rawValue: rec.featureName) else { continue }
                            history.append((feature: feature, zScore: rec.bestZScore, isImpostor: isImp))
                        }
                    }

                    if !history.isEmpty {
                        sdk.tuneTolerancesFromHistory(history)
                    }
                },
                onDone: {
                    captureMode = nil
                    samplesCollected = sdk.enrollmentSampleCount
                    if samplesCollected >= 3 {
                        stats = sdk.enrollmentStats()
                    }
                    isEnrolled = sdk.isEnrolled
                }
            )
        }
        .onAppear {
            samplesCollected = sdk.enrollmentSampleCount
            if samplesCollected >= 3 {
                stats = sdk.enrollmentStats()
            }
            isEnrolled = sdk.isEnrolled
        }
    }

    private func tuneFromHistory() {
        let descriptor = FetchDescriptor<AttemptRecord>(
            predicate: #Predicate { $0.isImpostor != nil }
        )
        guard let labeled = try? modelContext.fetch(descriptor),
              labeled.contains(where: { $0.isImpostor == true }),
              labeled.contains(where: { $0.isImpostor == false }) else { return }

        var history: [(feature: FeatureName, zScore: Double, isImpostor: Bool)] = []
        for attempt in labeled {
            guard let isImp = attempt.isImpostor else { continue }
            for rec in attempt.featureRecords {
                guard let feature = FeatureName(rawValue: rec.featureName) else { continue }
                history.append((feature: feature, zScore: rec.bestZScore, isImpostor: isImp))
            }
        }

        if !history.isEmpty {
            sdk.tuneTolerancesFromHistory(history)
        }
    }

    private func qualityColor(_ quality: String) -> Color {
        switch quality {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair — keep going": return .orange
        default: return .secondary
        }
    }
}

#Preview {
    PersonalModeView(isEnrolled: .constant(false))
}
