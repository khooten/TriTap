import Foundation

/// Raw per-digit matching engine.
///
/// No bins, no Gaussian, no abstraction. Keeps every training sample's raw
/// per-keystroke feature values. For each digit position in a test attempt,
/// finds the training sample whose features are ALL closest simultaneously.
///
/// The AND gate is the key: a knuckle might match training timing, but no
/// training sample has both that timing AND that radius. One outlier feature
/// blocks the entire match at that digit.
///
/// Digits are scored independently — digit 0 can match training sample #5
/// while digit 3 matches training sample #23. This is fine because people
/// naturally vary between keystrokes but are consistent at each position.
public final class RawMatchEngine {

    /// Default tolerance — overridden per-feature by adaptive tolerance based on CV.
    private let defaultToleranceSigma = 2.5

    /// Per-feature adaptive tolerances, computed from training data CV.
    /// Low CV (consistent) → tighter tolerance (more discriminating).
    /// High CV (noisy) → looser tolerance (fewer false rejections).
    private var featureTolerances: [Double] = []

    /// Per-feature tolerances that have been tuned from labeled history (SwiftData).
    /// When set, these override the CV-based tolerances.
    private var tunedTolerances: [Double]?

    /// Minimum quality score for any single digit that passes the AND gate.
    /// Digits below this are treated as blocked.
    private let minimumDigitQuality = 0.65

    /// Maximum number of digits allowed to fail (blocked or below floor).
    /// 1 = require 5 out of 6 digits to pass. Accommodates natural variation
    /// on one keystroke without compromising security.
    private let maxAllowedFailedDigits = 1

    // MARK: - Data Structures

    /// Raw feature values for one keystroke from one training sample
    struct TrainingSample: Codable {
        let features: [Double]  // One value per feature, in featureNames order
    }

    /// All training samples' features at one digit position, plus statistics
    struct DigitStore: Codable {
        let position: Int
        var samples: [TrainingSample]
        var means: [Double]     // Per-feature mean across training samples
        var stddevs: [Double]   // Per-feature stddev across training samples
    }

    /// Per-keystroke features extracted from a touch + motion segment
    struct KeystrokeFeatures {
        let dwellTime: Double
        let flightTime: Double
        let peakRadius: Double         // Max contact size during press (more stable than initial)
        let touchOffsetX: Double
        let touchOffsetY: Double
        let motionDuringDwell: Double
        let motionDuringFlight: Double
        let tremorDuringDwell: Double
        let tremorDuringFlight: Double
        let pitchDuringDwell: Double
        let rollDuringDwell: Double
        let pitchChange: Double
        let driftX: Double             // Finger slide X during press
        let driftY: Double             // Finger slide Y during press
    }

    private var digits: [DigitStore] = []
    private var numTrainingSamples: Int = 0

    /// Per-feature pass/fail history for recent attempts (in-memory, for quick UI access).
    private(set) var recentAttemptHistory: [AttemptFeatureResult] = []
    private let maxHistoryCount = 15

    /// One auth attempt's per-feature results
    public struct AttemptFeatureResult {
        public let passed: Bool                         // Overall pass/fail
        public let score: Double                        // Overall score
        public let featureResults: [FeatureName: Bool]  // true = OK, false = was a blocker or weak
        public let featureZScores: [FeatureName: Double] // Best (lowest) z-score across all digits per feature
        public let isImpostor: Bool?                    // User-labeled: true=impostor, false=genuine, nil=unknown
    }

    /// Callback for persisting attempt data externally (set by SDK to write to SwiftData)
    public var onAttemptRecorded: ((AttemptFeatureResult) -> Void)?

    static let featureNames = FeatureName.ordered.map { $0.rawValue }

    // MARK: - Training

    public func buildFromSamples(_ samples: [AuthenticationSample]) {
        guard samples.count >= 3 else { return }

        // Find the minimum number of keystrokes across all samples
        let keystrokeCounts = samples.map { $0.touchEvents.count }
        let numDigits = keystrokeCounts.min() ?? 0
        guard numDigits >= 1 else { return }

        // Extract per-keystroke features and normalize within each attempt
        let allNormalized = samples.map { sample -> [[Double]] in
            let keystrokes = extractPerKeystroke(from: sample)
            return normalizedFeatureArrays(keystrokes)
        }

        digits = []
        for d in 0..<numDigits {
            var digitSamples: [TrainingSample] = []

            for normalizedArrays in allNormalized {
                guard d < normalizedArrays.count else { continue }
                digitSamples.append(TrainingSample(features: normalizedArrays[d]))
            }

            // Compute per-feature stats
            let numFeatures = Self.featureNames.count
            var means = [Double](repeating: 0, count: numFeatures)
            var stddevs = [Double](repeating: 0, count: numFeatures)

            for f in 0..<numFeatures {
                let values = digitSamples.map { $0.features[f] }
                let mean = values.reduce(0, +) / Double(values.count)
                let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(values.count - 1, 1))
                means[f] = mean
                stddevs[f] = sqrt(variance)
            }

            digits.append(DigitStore(
                position: d,
                samples: digitSamples,
                means: means,
                stddevs: stddevs
            ))
        }

        numTrainingSamples = samples.count

        // Compute per-feature adaptive tolerances based on CV
        computeAdaptiveTolerances()

        let activePerDigit = digits.map { d in d.stddevs.filter { $0 > 1e-10 }.count }
        let activeStr = activePerDigit.map { String($0) }.joined(separator: "/")
        print("[RawMatch] Built: \(samples.count) samples, \(numDigits) digits, features: \(activeStr) (floor: \(Int(minimumDigitQuality * 100))%)")

        // Log feature stats with per-feature tolerances
        let stats = featureStatistics()
        for (f, s) in stats.enumerated() {
            let tol = toleranceForFeature(f)
            let window = tol * s.stddevAcrossDigits
            print("[RawMatch] \(s.feature.rawValue): mean=\(String(format: "%.4f", s.meanAcrossDigits)) ±\(String(format: "%.4f", s.stddevAcrossDigits)) tol=\(String(format: "%.1f", tol))σ window=±\(String(format: "%.4f", window))")
        }
    }

    // MARK: - Adaptive Tolerance

    /// Compute per-feature tolerance from coefficient of variation.
    /// Consistent features (low CV) get tighter tolerances → better impostor rejection.
    /// Noisy features (high CV) get looser tolerances → fewer false rejections.
    private func computeAdaptiveTolerances() {
        let numFeatures = Self.featureNames.count
        featureTolerances = [Double](repeating: defaultToleranceSigma, count: numFeatures)

        guard !digits.isEmpty else { return }

        for f in 0..<numFeatures {
            // Average CV across all digits that have this feature active
            var cvSum = 0.0
            var activeDigits = 0

            for digit in digits {
                guard digit.stddevs[f] > 1e-10 else { continue }
                let mean = digit.means[f]
                let stddev = digit.stddevs[f]
                // CV = stddev/|mean| — but for features near zero, use stddev directly
                let cv: Double
                if abs(mean) > 1e-6 {
                    cv = stddev / abs(mean)
                } else {
                    // For features centered near zero (like drift, pitch_change),
                    // use stddev relative to the feature's range
                    let values = digit.samples.map { $0.features[f] }
                    let range = (values.max() ?? 0) - (values.min() ?? 0)
                    cv = range > 1e-10 ? stddev / range : 0.5
                }
                cvSum += cv
                activeDigits += 1
            }

            guard activeDigits > 0 else { continue }
            let avgCV = cvSum / Double(activeDigits)

            // Map CV to tolerance:
            // CV < 0.15  → 1.5σ  (very tight — strong discriminator)
            // CV 0.15-0.25 → 2.0σ  (tight)
            // CV 0.25-0.40 → 2.5σ  (standard)
            // CV 0.40-0.60 → 3.0σ  (loose — noisy feature)
            // CV > 0.60  → 3.5σ  (very loose — mostly noise)
            let tolerance: Double
            if avgCV < 0.15 {
                tolerance = 1.5
            } else if avgCV < 0.25 {
                // Linear interpolation: 0.15→1.5, 0.25→2.0
                tolerance = 1.5 + (avgCV - 0.15) / 0.10 * 0.5
            } else if avgCV < 0.40 {
                // 0.25→2.0, 0.40→2.5
                tolerance = 2.0 + (avgCV - 0.25) / 0.15 * 0.5
            } else if avgCV < 0.60 {
                // 0.40→2.5, 0.60→3.0
                tolerance = 2.5 + (avgCV - 0.40) / 0.20 * 0.5
            } else {
                // 0.60+→3.0-3.5
                tolerance = min(3.5, 3.0 + (avgCV - 0.60) / 0.40 * 0.5)
            }

            featureTolerances[f] = tolerance
        }

        // Log the adaptive tolerances
        let tolStrs = zip(Self.featureNames, featureTolerances).map { "\($0.0.split(separator: "_").last ?? "?"):\(String(format: "%.1f", $0.1))σ" }
        print("[RawMatch] Adaptive tolerances: \(tolStrs.joined(separator: " "))")
    }

    /// Get the tolerance for a specific feature index.
    /// Uses tuned tolerances if available (from SwiftData history), otherwise CV-based.
    func toleranceForFeature(_ featureIndex: Int) -> Double {
        if let tuned = tunedTolerances, featureIndex < tuned.count {
            return tuned[featureIndex]
        }
        guard featureIndex < featureTolerances.count else { return defaultToleranceSigma }
        return featureTolerances[featureIndex]
    }

    /// Apply tuned tolerances from external analysis (e.g., SwiftData history auto-tune).
    public func setTunedTolerances(_ tolerances: [Double]) {
        tunedTolerances = tolerances
    }

    // MARK: - Scoring

    public struct ScoreResult {
        public let confidence: Double   // For display (matchRatio × avgQuality)
        public let passed: Bool         // Engine's pass/fail decision (respects 5/6 rule + floor)
        public let matchedDigits: Int
        public let totalDigits: Int
        public let avgQuality: Double   // Average quality of passing digits
    }

    public func score(_ sample: AuthenticationSample) -> Double {
        return scoreDetailed(sample).confidence
    }

    public func scoreDetailed(_ sample: AuthenticationSample) -> ScoreResult {
        guard !digits.isEmpty else { return ScoreResult(confidence: 0, passed: false, matchedDigits: 0, totalDigits: 0, avgQuality: 0) }
        return computeScore(sample)
    }

    private let emptyResult = ScoreResult(confidence: 0, passed: false, matchedDigits: 0, totalDigits: 0, avgQuality: 0)

    private func computeScore(_ sample: AuthenticationSample) -> ScoreResult {
        guard !digits.isEmpty else { return emptyResult }

        let keystrokes = extractPerKeystroke(from: sample)
        guard keystrokes.count >= digits.count else { return emptyResult }

        // Normalize the test sample the same way training samples were normalized
        let normalizedArrays = normalizedFeatureArrays(keystrokes)
        guard normalizedArrays.count >= digits.count else { return emptyResult }

        var digitScores: [Double] = []
        var digitLabels: [String] = []

        // Track which features cause blocks across all digits
        var blockCounts: [String: Int] = [:]  // feature name → how many digits it blocked
        var totalBlocked = 0

        // Per-feature best z-score across all digits (for history tracking)
        var bestZScoresPerFeature: [String: Double] = [:]  // lowest z-score seen for each feature
        // Features that contributed to floor failures
        var floorWeakFeatures: Set<String> = []

        for digit in digits {
            guard digit.position < keystrokes.count else { continue }
            let testFeatures = normalizedArrays[digit.position]

            // Find the best matching training sample at this digit.
            // "Best" = the one where this test sample's features are closest
            // across ALL features simultaneously (AND gate).
            var bestScore = 0.0
            var bestSampleIdx = -1
            var bestOutliers: [(String, Double, Double, Double)] = [] // (name, testVal, trainVal, zScore)
            var closestMaxZ = Double.infinity  // Track closest-to-passing sample
            var closestOutliers: [(String, Double, Double, Double)] = []
            var closestSampleIdx = -1

            var bestZScoresThisDigit: [String: Double] = [:]  // Per-feature z-scores on best/closest sample

            for (sIdx, trainingSample) in digit.samples.enumerated() {
                // TRUE AND GATE: check if ALL active features are within tolerance.
                var allWithinTolerance = true
                var featureMatchSum = 0.0
                var activeCount = 0
                var outliers: [(String, Double, Double, Double)] = []
                var maxZScore = 0.0
                var perFeatureZ: [String: Double] = [:]

                for f in 0..<Self.featureNames.count {
                    let stddev = digit.stddevs[f]
                    guard stddev > 1e-10 else { continue }
                    activeCount += 1

                    let featureTol = toleranceForFeature(f)
                    let diff = abs(testFeatures[f] - trainingSample.features[f])
                    let zScore = diff / stddev
                    maxZScore = max(maxZScore, zScore)
                    perFeatureZ[Self.featureNames[f]] = zScore

                    if zScore > featureTol {
                        allWithinTolerance = false
                        outliers.append((Self.featureNames[f], testFeatures[f], trainingSample.features[f], zScore))
                    }

                    let quality = max(0, 1.0 - zScore / featureTol)
                    featureMatchSum += quality
                }

                let sampleScore: Double
                if allWithinTolerance && activeCount > 0 {
                    sampleScore = featureMatchSum / Double(activeCount)
                } else {
                    sampleScore = 0
                }

                if sampleScore > bestScore {
                    bestScore = sampleScore
                    bestSampleIdx = sIdx
                    bestOutliers = outliers
                    bestZScoresThisDigit = perFeatureZ
                }

                // Track the sample closest to passing: lowest max z-score
                // This is the sample where the worst feature was least bad
                if !allWithinTolerance && maxZScore < closestMaxZ {
                    closestMaxZ = maxZScore
                    closestOutliers = outliers
                    closestSampleIdx = sIdx
                    if bestScore == 0 {
                        // No passing sample yet — use closest for z-score tracking
                        bestZScoresThisDigit = perFeatureZ
                    }
                }
            }

            // Merge this digit's best z-scores into the global per-feature tracker
            // Keep the LOWEST z-score seen for each feature across all digits (best case)
            for (name, z) in bestZScoresThisDigit {
                if let existing = bestZScoresPerFeature[name] {
                    bestZScoresPerFeature[name] = min(existing, z)
                } else {
                    bestZScoresPerFeature[name] = z
                }
            }

            digitScores.append(bestScore)

            let matched = bestScore > 0
            digitLabels.append(String(format: "D%d:%@%.0f%%", digit.position, matched ? "✓" : "✗", bestScore * 100))

            if !matched {
                totalBlocked += 1
                let reportOutliers = closestSampleIdx >= 0 ? closestOutliers : bestOutliers
                for outlier in reportOutliers {
                    blockCounts[outlier.0, default: 0] += 1
                }
            }
        }

        guard !digitScores.isEmpty else { return emptyResult }

        // Per-digit floor: if ANY digit is below minimum quality, fail entirely
        let belowFloor = digitScores.enumerated().filter { $0.element > 0 && $0.element < minimumDigitQuality }
        if !belowFloor.isEmpty {
            for (idx, score) in belowFloor {
                digitScores[idx] = 0
                digitLabels[idx] = String(format: "D%d:⚠%.0f%%", idx, score * 100)
            }
            for (f, name) in Self.featureNames.enumerated() {
                let tol = toleranceForFeature(f)
                if let z = bestZScoresPerFeature[name], z > tol * 0.75 {
                    floorWeakFeatures.insert(name)
                }
            }
        }

        let matchedDigits = digitScores.filter { $0 > 0 }.count
        let failedDigits = digitScores.count - matchedDigits
        let avgQuality = matchedDigits > 0
            ? digitScores.filter { $0 > 0 }.reduce(0, +) / Double(matchedDigits)
            : 0
        // Confidence based on matched digits only (don't let 1 failed digit tank the average)
        let matchRatio = Double(matchedDigits) / Double(digitScores.count)
        let confidence = matchRatio * avgQuality

        // One concise line per attempt
        print("[RawMatch] \(String(format: "%.3f", confidence)) | \(digitLabels.joined(separator: " "))")

        let finalConfidence = min(max(confidence, 0), 1)
        // Pass if enough digits matched with sufficient quality
        let overallPassed = failedDigits <= maxAllowedFailedDigits && avgQuality >= 0.70

        // Build per-feature results using enum keys
        var featureResults: [FeatureName: Bool] = [:]
        var featureZScores: [FeatureName: Double] = [:]
        for feature in FeatureName.ordered {
            let name = feature.rawValue
            let wasBlocker = blockCounts[name] != nil
            let wasFloorWeak = floorWeakFeatures.contains(name)
            featureResults[feature] = !wasBlocker && !wasFloorWeak
            if let z = bestZScoresPerFeature[name] {
                featureZScores[feature] = z
            }
        }

        let attemptResult = AttemptFeatureResult(
            passed: overallPassed,
            score: finalConfidence,
            featureResults: featureResults,
            featureZScores: featureZScores,
            isImpostor: nil  // Will be set by SDK based on user toggle
        )
        recentAttemptHistory.append(attemptResult)
        if recentAttemptHistory.count > maxHistoryCount {
            recentAttemptHistory.removeFirst()
        }

        // Notify external persistence (SwiftData)
        onAttemptRecorded?(attemptResult)

        return ScoreResult(
            confidence: finalConfidence,
            passed: overallPassed,
            matchedDigits: matchedDigits,
            totalDigits: digitScores.count,
            avgQuality: avgQuality
        )
    }

    // MARK: - Diagnostics

    public struct RawMatchDiagnostic {
        public let numDigits: Int
        public let numSamples: Int
        public let featuresPerDigit: Int
        public let activeFeaturesPerDigit: [Int]
    }

    /// Per-feature stats across all digits
    public struct FeatureStats {
        public let feature: FeatureName
        public let meanAcrossDigits: Double
        public let stddevAcrossDigits: Double
        public let minValue: Double
        public let maxValue: Double
        public let toleranceWindow: Double  // 2 * toleranceSigma * stddev
    }

    public func diagnostics() -> RawMatchDiagnostic {
        return RawMatchDiagnostic(
            numDigits: digits.count,
            numSamples: numTrainingSamples,
            featuresPerDigit: Self.featureNames.count,
            activeFeaturesPerDigit: digits.map { d in d.stddevs.filter { $0 > 1e-10 }.count }
        )
    }

    /// Get detailed per-feature statistics from training data
    public func featureStatistics() -> [FeatureStats] {
        guard !digits.isEmpty else { return [] }

        var results: [FeatureStats] = []

        for (f, featureName) in Self.featureNames.enumerated() {
            guard let feature = FeatureName(rawValue: featureName) else { continue }

            var allValues: [Double] = []
            var meanSum = 0.0
            var stddevSum = 0.0
            var activeDigits = 0

            for digit in digits {
                guard digit.stddevs[f] > 1e-10 else { continue }
                activeDigits += 1
                meanSum += digit.means[f]
                stddevSum += digit.stddevs[f]

                // Collect all raw training values for this feature at this digit
                for sample in digit.samples {
                    allValues.append(sample.features[f])
                }
            }

            guard activeDigits > 0 else { continue }

            let avgMean = meanSum / Double(activeDigits)
            let avgStddev = stddevSum / Double(activeDigits)

            results.append(FeatureStats(
                feature: feature,
                meanAcrossDigits: avgMean,
                stddevAcrossDigits: avgStddev,
                minValue: allValues.min() ?? 0,
                maxValue: allValues.max() ?? 0,
                toleranceWindow: 2.0 * toleranceForFeature(f) * avgStddev
            ))
        }

        return results
    }


    // MARK: - Persistence

    public func save() -> Data? {
        let state = RawMatchState(
            digits: digits,
            numTrainingSamples: numTrainingSamples,
            featureTolerances: featureTolerances.isEmpty ? nil : featureTolerances,
            tunedTolerances: tunedTolerances
        )
        return try? JSONEncoder().encode(state)
    }

    public func load(from data: Data) -> Bool {
        guard let state = try? JSONDecoder().decode(RawMatchState.self, from: data) else {
            return false
        }
        digits = state.digits
        numTrainingSamples = state.numTrainingSamples
        if let tol = state.featureTolerances {
            featureTolerances = tol
        }
        tunedTolerances = state.tunedTolerances
        return true
    }

    public var isReady: Bool { !digits.isEmpty }

    // MARK: - Per-Keystroke Feature Extraction

    private func extractPerKeystroke(from sample: AuthenticationSample) -> [KeystrokeFeatures] {
        let touches = sample.touchEvents
        let motion = sample.motionSamples
        guard !touches.isEmpty else { return [] }

        var results: [KeystrokeFeatures] = []

        for (i, touch) in touches.enumerated() {
            let dwellTime = touch.touchEnded - touch.touchBegan

            let flightTime: Double
            if i > 0 {
                flightTime = touch.touchBegan - touches[i - 1].touchEnded
            } else {
                flightTime = 0
            }

            let touchRadius = Double(touch.majorRadius)
            let touchOffsetX = Double(touch.normalizedKeyX)
            let touchOffsetY = Double(touch.normalizedKeyY)

            // Motion during dwell (finger on screen)
            let dwellMotion = motion.filter { $0.timestamp >= touch.touchBegan && $0.timestamp <= touch.touchEnded }

            // Motion during flight (between keys)
            let flightMotion: [MotionSnapshot]
            if i > 0 {
                let prevEnd = touches[i - 1].touchEnded
                flightMotion = motion.filter { $0.timestamp >= prevEnd && $0.timestamp <= touch.touchBegan }
            } else {
                flightMotion = []
            }

            let motionDwell = accelRMS(dwellMotion)
            let motionFlight = accelRMS(flightMotion)
            let tremorDwell = gyroRMS(dwellMotion)
            let tremorFlight = gyroRMS(flightMotion)

            let pitchDwell = dwellMotion.isEmpty ? 0 : dwellMotion.map { $0.attitudePitch }.reduce(0, +) / Double(dwellMotion.count)
            let rollDwell = dwellMotion.isEmpty ? 0 : dwellMotion.map { $0.attitudeRoll }.reduce(0, +) / Double(dwellMotion.count)

            let pitchChange: Double
            if i > 0 {
                let prevDwell = motion.filter { $0.timestamp >= touches[i-1].touchBegan && $0.timestamp <= touches[i-1].touchEnded }
                let prevPitch = prevDwell.isEmpty ? 0 : prevDwell.map { $0.attitudePitch }.reduce(0, +) / Double(prevDwell.count)
                pitchChange = pitchDwell - prevPitch
            } else {
                pitchChange = 0
            }

            // Peak contact size during press (more stable than initial snapshot)
            let peakRadius = touch.radiusSampleCount > 0 ? Double(touch.radiusMax) : touchRadius

            // Finger drift during press (how far finger slid on key)
            let driftX = Double(touch.endNormalizedKeyX - touch.normalizedKeyX)
            let driftY = Double(touch.endNormalizedKeyY - touch.normalizedKeyY)

            results.append(KeystrokeFeatures(
                dwellTime: dwellTime,
                flightTime: flightTime,
                peakRadius: peakRadius,
                touchOffsetX: touchOffsetX,
                touchOffsetY: touchOffsetY,
                motionDuringDwell: motionDwell,
                motionDuringFlight: motionFlight,
                tremorDuringDwell: tremorDwell,
                tremorDuringFlight: tremorFlight,
                pitchDuringDwell: pitchDwell,
                rollDuringDwell: rollDwell,
                pitchChange: pitchChange,
                driftX: driftX,
                driftY: driftY
            ))
        }

        return results
    }

    /// Convert raw keystroke features to absolute feature array (preserved for reference)
    private func absoluteFeatureArray(_ kf: KeystrokeFeatures) -> [Double] {
        return [
            kf.dwellTime, kf.flightTime, kf.peakRadius,
            kf.touchOffsetX, kf.touchOffsetY,
            kf.motionDuringDwell, kf.motionDuringFlight,
            kf.tremorDuringDwell, kf.tremorDuringFlight,
            kf.pitchDuringDwell, kf.rollDuringDwell,
            kf.pitchChange,
            kf.driftX, kf.driftY,
        ]
    }

    /// Normalize keystroke features relative to per-attempt ranges.
    /// Timing → fraction of total duration. Sensor data → 0-1 within attempt range.
    /// Touch position and drift stay absolute.
    private func normalizedFeatureArrays(_ keystrokes: [KeystrokeFeatures]) -> [[Double]] {
        guard !keystrokes.isEmpty else { return [] }

        // Compute per-attempt totals and ranges for relative features
        let totalDuration = keystrokes.reduce(0.0) { $0 + $1.dwellTime + $1.flightTime }

        // Helper: compute min/max across all keystrokes for a given property
        func range(_ extract: (KeystrokeFeatures) -> Double) -> (min: Double, max: Double, span: Double) {
            let values = keystrokes.map(extract)
            let lo = values.min() ?? 0
            let hi = values.max() ?? 0
            return (lo, hi, hi - lo)
        }

        let pitchRange = range(\.pitchDuringDwell)
        let rollRange = range(\.rollDuringDwell)
        let tremorDwellRange = range(\.tremorDuringDwell)
        let tremorFlightRange = range(\.tremorDuringFlight)
        let motionDwellRange = range(\.motionDuringDwell)
        let motionFlightRange = range(\.motionDuringFlight)

        // Helper: normalize a value to 0-1 within a range (returns 0.5 if no range)
        func normalize(_ value: Double, _ r: (min: Double, max: Double, span: Double)) -> Double {
            guard r.span > 1e-10 else { return 0.5 }
            return (value - r.min) / r.span
        }

        // Build normalized feature array for each keystroke
        return keystrokes.map { kf in
            let relDwell = totalDuration > 1e-10 ? kf.dwellTime / totalDuration : 0
            let relFlight = totalDuration > 1e-10 ? kf.flightTime / totalDuration : 0

            return [
                relDwell,                                           // rel_dwell_time
                relFlight,                                          // rel_flight_time
                kf.peakRadius,                                      // peak_radius (absolute)
                kf.touchOffsetX,                                    // offset_x (absolute)
                kf.touchOffsetY,                                    // offset_y (absolute)
                normalize(kf.motionDuringDwell, motionDwellRange),  // rel_motion_dwell
                normalize(kf.motionDuringFlight, motionFlightRange),// rel_motion_flight
                normalize(kf.tremorDuringDwell, tremorDwellRange),  // rel_tremor_dwell
                normalize(kf.tremorDuringFlight, tremorFlightRange),// rel_tremor_flight
                normalize(kf.pitchDuringDwell, pitchRange),         // rel_pitch
                normalize(kf.rollDuringDwell, rollRange),           // rel_roll
                kf.pitchChange,                                     // pitch_change (already relative)
                kf.driftX,                                          // drift_x (absolute)
                kf.driftY,                                          // drift_y (absolute)
            ]
        }
    }

    // MARK: - Motion Helpers

    private func accelRMS(_ snapshots: [MotionSnapshot]) -> Double {
        guard !snapshots.isEmpty else { return 0 }
        let n = Double(snapshots.count)
        let rms = sqrt(snapshots.reduce(0.0) {
            $0 + $1.userAccelX * $1.userAccelX + $1.userAccelY * $1.userAccelY + $1.userAccelZ * $1.userAccelZ
        } / n)
        return rms
    }

    private func gyroRMS(_ snapshots: [MotionSnapshot]) -> Double {
        guard !snapshots.isEmpty else { return 0 }
        let n = Double(snapshots.count)
        let rms = sqrt(snapshots.reduce(0.0) {
            $0 + $1.gyroX * $1.gyroX + $1.gyroY * $1.gyroY + $1.gyroZ * $1.gyroZ
        } / n)
        return rms
    }
}

// MARK: - Persistence State

private struct RawMatchState: Codable {
    let digits: [RawMatchEngine.DigitStore]
    let numTrainingSamples: Int
    let featureTolerances: [Double]?
    let tunedTolerances: [Double]?
}
