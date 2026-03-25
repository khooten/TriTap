import Foundation

/// Canonical set of per-keystroke features measured by the RawMatch engine.
/// Using an enum guarantees consistent naming across storage, scoring, and UI.
public enum FeatureName: String, Codable, CaseIterable, Hashable {
    // Relative features (normalized within each attempt — grip-position invariant)
    case relDwellTime = "rel_dwell_time"       // Fraction of total duration
    case relFlightTime = "rel_flight_time"     // Fraction of total duration
    case relPitch = "rel_pitch"                // 0-1 fraction of per-attempt pitch range
    case relRoll = "rel_roll"                  // 0-1 fraction of per-attempt roll range
    case relTremorDwell = "rel_tremor_dwell"   // 0-1 fraction of per-attempt tremor range
    case relTremorFlight = "rel_tremor_flight"
    case relMotionDwell = "rel_motion_dwell"   // 0-1 fraction of per-attempt motion range
    case relMotionFlight = "rel_motion_flight"

    // Absolute features (actual value matters)
    case offsetX = "offset_x"                  // Where on the key you land
    case offsetY = "offset_y"
    case driftX = "drift_x"                    // Finger slide direction during press
    case driftY = "drift_y"
    case peakRadius = "peak_radius"            // Physical finger contact size
    case pitchChange = "pitch_change"          // Tilt change between keys (already relative)

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .relDwellTime: return "Key Hold Rhythm"
        case .relFlightTime: return "Travel Time Rhythm"
        case .relPitch: return "Tilt Pattern (fwd/back)"
        case .relRoll: return "Tilt Pattern (left/right)"
        case .relTremorDwell: return "Tremor Pattern (press)"
        case .relTremorFlight: return "Tremor Pattern (flight)"
        case .relMotionDwell: return "Motion Pattern (press)"
        case .relMotionFlight: return "Motion Pattern (flight)"
        case .offsetX: return "Touch Position X"
        case .offsetY: return "Touch Position Y"
        case .driftX: return "Finger Drift X"
        case .driftY: return "Finger Drift Y"
        case .peakRadius: return "Peak Contact Size"
        case .pitchChange: return "Tilt Change"
        }
    }

    /// Whether this is a timing-related feature
    public var isTiming: Bool {
        switch self {
        case .relDwellTime, .relFlightTime: return true
        default: return false
        }
    }

    /// Ordered list matching the feature array index used in RawMatchEngine
    public static var ordered: [FeatureName] {
        [.relDwellTime, .relFlightTime, .peakRadius,
         .offsetX, .offsetY,
         .relMotionDwell, .relMotionFlight,
         .relTremorDwell, .relTremorFlight,
         .relPitch, .relRoll, .pitchChange,
         .driftX, .driftY]
    }
}
