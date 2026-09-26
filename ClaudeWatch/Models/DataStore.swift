import Foundation
import OSLog
import SwiftData
import ClaudeWatchCore

/// Creates the shared `ModelContainer` and seeds first-launch data.
enum DataStore {
    static let schema = Schema([
        ClaudeSession.self,
        ClaudeEventRecord.self,
        ClaudeAccount.self,
        NotificationRule.self,
    ])

    /// Result of opening the persistent store. Never crashes: if the on-disk store cannot be
    /// opened, an in-memory store is used and the error is surfaced in the UI.
    struct OpenResult {
        let container: ModelContainer
        let error: String?
    }

    @MainActor
    static func open(inMemory: Bool = false) -> OpenResult {
        if inMemory {
            return OpenResult(container: makeInMemory(), error: nil)
        }
        do {
            let directory = try storeDirectory()
            let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("ClaudeWatch.store"))
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return OpenResult(container: container, error: nil)
        } catch {
            Log.persistence.error("Could not open the persistent store: \(error.localizedDescription, privacy: .public)")
            return OpenResult(
                container: makeInMemory(),
                error: "History could not be loaded (\(error.localizedDescription)). ClaudeWatch is running with temporary storage."
            )
        }
    }

    @MainActor
    static func makeInMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create an in-memory SwiftData store: \(error)")
        }
    }

    static func storeDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("ClaudeWatch", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Inserts default notification rules for event types that have none yet.
    @MainActor
    static func seedNotificationRules(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<NotificationRule>())) ?? []
        let existingTypes = Set(existing.map(\.eventTypeRaw))
        var inserted = false
        for type in ClaudeEventType.notifiable where !existingTypes.contains(type.rawValue) {
            context.insert(NotificationRule(snapshot: .defaultRule(for: type)))
            inserted = true
        }
        if inserted {
            do { try context.save() } catch {
                Log.persistence.error("Could not seed notification rules: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
