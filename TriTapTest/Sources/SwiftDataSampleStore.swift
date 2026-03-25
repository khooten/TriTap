import Foundation
import SwiftData
import TypingAuthSDK

/// SwiftData-backed implementation of SampleStore.
/// Replaces the file-based EnrollmentStore for training sample persistence.
final class SwiftDataSampleStore: SampleStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveSample(_ sample: AuthenticationSample) throws {
        guard let record = TrainingSampleRecord.from(sample) else {
            throw NSError(domain: "SwiftDataSampleStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode sample"])
        }
        modelContext.insert(record)
        try modelContext.save()
    }

    func loadSamples() -> [AuthenticationSample] {
        let descriptor = FetchDescriptor<TrainingSampleRecord>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        guard let records = try? modelContext.fetch(descriptor) else { return [] }
        return records.compactMap { $0.toSample() }
    }

    func sampleCount() -> Int {
        let descriptor = FetchDescriptor<TrainingSampleRecord>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func clearSamples() {
        do {
            try modelContext.delete(model: TrainingSampleRecord.self)
            try modelContext.save()
        } catch {
            print("[SwiftDataSampleStore] Failed to clear samples: \(error)")
        }
    }
}
