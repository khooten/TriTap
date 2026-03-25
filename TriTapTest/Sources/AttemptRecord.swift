import Foundation
import SwiftData
import TypingAuthSDK

// MARK: - Training Sample Storage

/// Persistent record of one training sample (enrollment data), stored via SwiftData.
/// The raw AuthenticationSample is serialized as JSON data so we preserve all
/// touch events and motion snapshots exactly as captured.
@Model
final class TrainingSampleRecord {
    var timestamp: Date
    var sessionID: String        // UUID string for dedup
    var sampleData: Data         // JSON-encoded AuthenticationSample
    var touchCount: Int          // Quick access without deserializing
    var motionCount: Int

    init(timestamp: Date = Date(),
         sessionID: String,
         sampleData: Data,
         touchCount: Int,
         motionCount: Int) {
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.sampleData = sampleData
        self.touchCount = touchCount
        self.motionCount = motionCount
    }

    /// Convenience: decode back to AuthenticationSample
    func toSample() -> AuthenticationSample? {
        try? JSONDecoder().decode(AuthenticationSample.self, from: sampleData)
    }

    /// Convenience: create from an AuthenticationSample
    static func from(_ sample: AuthenticationSample) -> TrainingSampleRecord? {
        guard let data = try? JSONEncoder().encode(sample) else { return nil }
        return TrainingSampleRecord(
            timestamp: sample.timestamp,
            sessionID: sample.sessionID.uuidString,
            sampleData: data,
            touchCount: sample.touchEvents.count,
            motionCount: sample.motionSamples.count
        )
    }
}

// MARK: - Attempt Records

/// Persistent record of one authentication attempt, stored via SwiftData.
@Model
final class AttemptRecord {
    var timestamp: Date
    var overallPassed: Bool
    var overallScore: Double
    var isImpostor: Bool?  // User-labeled: true=impostor, false=genuine, nil=unknown

    @Relationship(deleteRule: .cascade)
    var featureRecords: [FeatureRecord]

    init(timestamp: Date = Date(),
         overallPassed: Bool,
         overallScore: Double,
         isImpostor: Bool? = nil,
         featureRecords: [FeatureRecord] = []) {
        self.timestamp = timestamp
        self.overallPassed = overallPassed
        self.overallScore = overallScore
        self.isImpostor = isImpostor
        self.featureRecords = featureRecords
    }
}

/// Per-feature measurement for one authentication attempt.
@Model
final class FeatureRecord {
    var featureName: String  // FeatureName.rawValue for stable storage
    var wasBlocker: Bool     // true = this feature caused a block or floor failure
    var bestZScore: Double   // Lowest z-score seen across all digits for this feature

    @Relationship(inverse: \AttemptRecord.featureRecords)
    var attempt: AttemptRecord?

    init(featureName: String,
         wasBlocker: Bool,
         bestZScore: Double) {
        self.featureName = featureName
        self.wasBlocker = wasBlocker
        self.bestZScore = bestZScore
    }
}
