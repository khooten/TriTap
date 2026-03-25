import Foundation

public final class EnrollmentStore {
    private let fileURL: URL

    public init(appGroupID: String? = nil) {
        let container: URL
        if let appGroupID, let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            container = groupURL
        } else {
            container = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }

        let dir = container.appendingPathComponent("TypingAuthSDK", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("enrollment_samples.json")
    }

    public func saveSample(_ sample: AuthenticationSample) throws {
        var samples = loadSamples()
        samples.append(sample)
        let data = try JSONEncoder().encode(samples)
        try data.write(to: fileURL, options: .completeFileProtection)
    }

    public func loadSamples() -> [AuthenticationSample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([AuthenticationSample].self, from: data)) ?? []
    }

    public func sampleCount() -> Int {
        loadSamples().count
    }

    public func removeSamples(withIDs ids: Set<UUID>) {
        var samples = loadSamples()
        samples.removeAll { ids.contains($0.sessionID) }
        if let data = try? JSONEncoder().encode(samples) {
            try? data.write(to: fileURL, options: .completeFileProtection)
        }
    }

    public func clearSamples() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
