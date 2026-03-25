import Foundation

// MARK: - Sample Label

public enum SampleLabel: String, Codable {
    case authorized
    case impostor
    case unknown
}

// MARK: - Touch Event

public struct TouchEvent: Codable {
    public let sequencePosition: Int
    public let touchBegan: TimeInterval
    public let touchEnded: TimeInterval
    public let locationX: CGFloat
    public let locationY: CGFloat
    public let normalizedKeyX: CGFloat
    public let normalizedKeyY: CGFloat
    public let majorRadius: CGFloat
    public let majorRadiusTolerance: CGFloat

    // End-of-press position (for drift vector)
    public let endLocationX: CGFloat
    public let endLocationY: CGFloat
    public let endNormalizedKeyX: CGFloat
    public let endNormalizedKeyY: CGFloat

    // Radius profile during dwell (min/max/mean of intermediate samples)
    public let radiusMin: CGFloat
    public let radiusMax: CGFloat
    public let radiusMean: CGFloat
    public let radiusSampleCount: Int  // How many intermediate samples were captured

    public init(
        sequencePosition: Int,
        touchBegan: TimeInterval,
        touchEnded: TimeInterval,
        locationX: CGFloat,
        locationY: CGFloat,
        normalizedKeyX: CGFloat,
        normalizedKeyY: CGFloat,
        majorRadius: CGFloat,
        majorRadiusTolerance: CGFloat,
        endLocationX: CGFloat = 0,
        endLocationY: CGFloat = 0,
        endNormalizedKeyX: CGFloat = 0,
        endNormalizedKeyY: CGFloat = 0,
        radiusMin: CGFloat = 0,
        radiusMax: CGFloat = 0,
        radiusMean: CGFloat = 0,
        radiusSampleCount: Int = 0
    ) {
        self.sequencePosition = sequencePosition
        self.touchBegan = touchBegan
        self.touchEnded = touchEnded
        self.locationX = locationX
        self.locationY = locationY
        self.normalizedKeyX = normalizedKeyX
        self.normalizedKeyY = normalizedKeyY
        self.majorRadius = majorRadius
        self.majorRadiusTolerance = majorRadiusTolerance
        self.endLocationX = endLocationX
        self.endLocationY = endLocationY
        self.endNormalizedKeyX = endNormalizedKeyX
        self.endNormalizedKeyY = endNormalizedKeyY
        self.radiusMin = radiusMin
        self.radiusMax = radiusMax
        self.radiusMean = radiusMean
        self.radiusSampleCount = radiusSampleCount
    }
}

// MARK: - Motion Snapshot

public struct MotionSnapshot: Codable {
    public let timestamp: TimeInterval
    public let accelerometerX: Double
    public let accelerometerY: Double
    public let accelerometerZ: Double
    public let gyroX: Double
    public let gyroY: Double
    public let gyroZ: Double
    public let gravityX: Double
    public let gravityY: Double
    public let gravityZ: Double
    public let userAccelX: Double
    public let userAccelY: Double
    public let userAccelZ: Double
    public let attitudePitch: Double
    public let attitudeRoll: Double
    public let attitudeYaw: Double

    public init(
        timestamp: TimeInterval,
        accelerometerX: Double,
        accelerometerY: Double,
        accelerometerZ: Double,
        gyroX: Double,
        gyroY: Double,
        gyroZ: Double,
        gravityX: Double,
        gravityY: Double,
        gravityZ: Double,
        userAccelX: Double,
        userAccelY: Double,
        userAccelZ: Double,
        attitudePitch: Double,
        attitudeRoll: Double,
        attitudeYaw: Double
    ) {
        self.timestamp = timestamp
        self.accelerometerX = accelerometerX
        self.accelerometerY = accelerometerY
        self.accelerometerZ = accelerometerZ
        self.gyroX = gyroX
        self.gyroY = gyroY
        self.gyroZ = gyroZ
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.gravityZ = gravityZ
        self.userAccelX = userAccelX
        self.userAccelY = userAccelY
        self.userAccelZ = userAccelZ
        self.attitudePitch = attitudePitch
        self.attitudeRoll = attitudeRoll
        self.attitudeYaw = attitudeYaw
    }
}

// MARK: - Authentication Sample

public struct AuthenticationSample: Codable {
    public let sessionID: UUID
    public let label: SampleLabel
    public let timestamp: Date
    public let touchEvents: [TouchEvent]
    public let motionSamples: [MotionSnapshot]
    public let reactionTime: TimeInterval
    public let totalDuration: TimeInterval

    public init(
        sessionID: UUID = UUID(),
        label: SampleLabel,
        timestamp: Date = Date(),
        touchEvents: [TouchEvent],
        motionSamples: [MotionSnapshot],
        reactionTime: TimeInterval,
        totalDuration: TimeInterval
    ) {
        self.sessionID = sessionID
        self.label = label
        self.timestamp = timestamp
        self.touchEvents = touchEvents
        self.motionSamples = motionSamples
        self.reactionTime = reactionTime
        self.totalDuration = totalDuration
    }
}
