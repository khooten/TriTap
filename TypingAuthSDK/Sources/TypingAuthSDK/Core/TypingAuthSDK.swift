import UIKit

public final class TypingAuthSDK {
    public static let shared = TypingAuthSDK()

    private let secureStore: SecureModelStore
    private var sampleStore: SampleStore
    private let rawMatchEngine: RawMatchEngine

    public var threshold: Double = 0.65
    public var passcodeLength: Int = 6
    public private(set) var enrolledPasscode: [Int]?

    private static let rawMatchDataKey = "raw_match_engine_state"

    private init() {
        secureStore = SecureModelStore()
        sampleStore = EnrollmentStore()  // Default file-based, replaced by app with SwiftData
        rawMatchEngine = RawMatchEngine()

        loadRawMatch()

        if let data = UserDefaults.standard.data(forKey: "com.notary.enrolledPasscode"),
           let digits = try? JSONDecoder().decode([Int].self, from: data) {
            enrolledPasscode = digits
        }
    }

    // MARK: - Configuration

    public func configure(threshold: Double = 0.65, passcodeLength: Int = 6) {
        self.threshold = threshold
        self.passcodeLength = passcodeLength
    }

    /// Replace the default file-based sample store with an external one (e.g. SwiftData).
    /// Call this early in app launch before any enrollment operations.
    public func setSampleStore(_ store: SampleStore) {
        sampleStore = store
    }

    // MARK: - Scoring

    public func scoreSample(_ sample: AuthenticationSample) -> Double? {
        guard rawMatchEngine.isReady else {
            print("[TypingAuthSDK] Not enrolled — need enrollment first")
            return nil
        }

        let score = rawMatchEngine.score(sample)
        print("[TypingAuthSDK] Score: \(String(format: "%.3f", score)) | touches: \(sample.touchEvents.count) | motion: \(sample.motionSamples.count)")
        return score
    }

    /// Authenticate a sample using the RawMatch AND-gate engine.
    public func authenticateSample(_ sample: AuthenticationSample) -> AuthResult {
        guard rawMatchEngine.isReady else {
            return AuthResult(confidence: 0, passed: false)
        }

        let result = rawMatchEngine.scoreDetailed(sample)

        print("[TypingAuthSDK] Auth: raw=\(String(format: "%.3f", result.confidence)) \(result.matchedDigits)/\(result.totalDigits) digits → \(result.passed ? "PASS" : "FAIL")")

        if result.passed && result.avgQuality >= 0.80 {
            // High-confidence pass — save to training data to tighten the model over time
            try? sampleStore.saveSample(sample)
            rawMatchEngine.buildFromSamples(sampleStore.loadSamples())
            saveRawMatch()
            print("[TypingAuthSDK] PASS (high confidence) — saved to training data (\(sampleStore.sampleCount()) samples)")
        } else if result.passed {
            print("[TypingAuthSDK] PASS")
        }

        return AuthResult(confidence: result.confidence, passed: result.passed)
    }

    // MARK: - Enrollment

    public var isEnrolled: Bool {
        rawMatchEngine.isReady
    }

    public var enrollmentSampleCount: Int {
        sampleStore.sampleCount()
    }

    public func addEnrollmentSample(_ sample: AuthenticationSample) {
        try? sampleStore.saveSample(sample)
    }

    public func setEnrolledPasscode(_ digits: [Int]) {
        enrolledPasscode = digits
        if let data = try? JSONEncoder().encode(digits) {
            UserDefaults.standard.set(data, forKey: "com.notary.enrolledPasscode")
        }
    }

    /// Build the RawMatch engine from enrollment samples
    public func finalizeEnrollment() {
        let samples = sampleStore.loadSamples()
        guard samples.count >= 3 else {
            print("[TypingAuthSDK] Need at least 3 enrollment samples")
            return
        }

        rawMatchEngine.buildFromSamples(samples)
        saveRawMatch()

        let diag = rawMatchEngine.diagnostics()
        print("[TypingAuthSDK] Enrollment finalized with \(samples.count) samples → \(diag.numDigits) digits × \(diag.numSamples) reference samples, \(diag.featuresPerDigit) features per digit")
    }

    // MARK: - Diagnostics

    public func rawMatchDiagnostics() -> RawMatchEngine.RawMatchDiagnostic? {
        guard rawMatchEngine.isReady else { return nil }
        return rawMatchEngine.diagnostics()
    }

    public func recentAttemptHistory() -> [RawMatchEngine.AttemptFeatureResult] {
        return rawMatchEngine.recentAttemptHistory
    }

    public func enrollmentStats() -> EnrollmentStats {
        let count = sampleStore.sampleCount()
        if let diag = rawMatchEngine.isReady ? rawMatchEngine.diagnostics() : nil {
            let quality: String
            if count >= 40 { quality = "Excellent" }
            else if count >= 20 { quality = "Good" }
            else if count >= 10 { quality = "Fair — keep going" }
            else { quality = "Needs more samples" }

            return EnrollmentStats(
                sampleCount: count,
                digitCount: diag.numDigits,
                activeFeaturesPerDigit: diag.activeFeaturesPerDigit,
                quality: quality
            )
        }
        return EnrollmentStats(sampleCount: count, digitCount: 0, activeFeaturesPerDigit: [], quality: "Needs more samples")
    }

    // MARK: - Reset

    /// Callback for the app to perform additional cleanup (e.g. clear SwiftData attempt history)
    public var onReset: (() -> Void)?

    public func resetEnrollment() {
        sampleStore.clearSamples()
        secureStore.deleteModel()
        secureStore.deletePasscodeHash()
        enrolledPasscode = nil
        UserDefaults.standard.removeObject(forKey: "com.notary.enrolledPasscode")
        UserDefaults.standard.removeObject(forKey: TypingAuthSDK.rawMatchDataKey)
        // Clean up legacy keys from retired engines
        UserDefaults.standard.removeObject(forKey: "trellis_engine_state")
        UserDefaults.standard.removeObject(forKey: "paired_engine_state")
        UserDefaults.standard.removeObject(forKey: "graph_engine_state")
        onReset?()
        print("[TypingAuthSDK] Enrollment reset")
    }

    // MARK: - Persistence

    private func saveRawMatch() {
        if let data = rawMatchEngine.save() {
            UserDefaults.standard.set(data, forKey: TypingAuthSDK.rawMatchDataKey)
        }
    }

    private func loadRawMatch() {
        if let data = UserDefaults.standard.data(forKey: TypingAuthSDK.rawMatchDataKey) {
            let loaded = rawMatchEngine.load(from: data)
            if loaded {
                print("[TypingAuthSDK] Loaded raw match engine from storage")
            }
        }
    }
}

public struct AuthResult {
    public let confidence: Double
    public let passed: Bool
}

/// Simple enrollment statistics for UI display
public struct EnrollmentStats {
    public let sampleCount: Int
    public let digitCount: Int
    public let activeFeaturesPerDigit: [Int]
    public let quality: String
}

