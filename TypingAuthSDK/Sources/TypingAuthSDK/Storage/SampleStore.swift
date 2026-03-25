import Foundation

/// Protocol for sample storage. The SDK uses this to save/load training samples.
/// The app provides the concrete implementation (SwiftData, file-based, etc.)
public protocol SampleStore {
    func saveSample(_ sample: AuthenticationSample) throws
    func loadSamples() -> [AuthenticationSample]
    func sampleCount() -> Int
    func clearSamples()
}

/// Default file-based implementation (fallback if no external store is provided)
extension EnrollmentStore: SampleStore {}
