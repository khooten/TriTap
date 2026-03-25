import SwiftUI
import SwiftData
import TypingAuthSDK

@main
struct TriTapApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: AttemptRecord.self, FeatureRecord.self, TrainingSampleRecord.self)
            // Inject SwiftData-backed sample store into SDK
            let context = ModelContext(container)
            let store = SwiftDataSampleStore(modelContext: context)
            TypingAuthSDK.shared.setSampleStore(store)

            // Wire reset to also clear attempt history
            TypingAuthSDK.shared.onReset = { [context] in
                do {
                    try context.delete(model: AttemptRecord.self)
                    try context.save()
                } catch {
                    print("[NotaryApp] Failed to clear attempt history on reset: \(error)")
                }
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
