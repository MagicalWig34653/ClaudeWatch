import Foundation
import SwiftData

/// Deletes history older than the configured retention period. Active sessions are never deleted.
@MainActor
enum RetentionService {
    @discardableResult
    static func cleanUp(context: ModelContext, retentionDays: Int, now: Date = Date()) -> (events: Int, sessions: Int) {
        guard retentionDays > 0 else { return (0, 0) }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        var deletedEvents = 0
        var deletedSessions = 0
        do {
            let oldEvents = try context.fetch(FetchDescriptor<ClaudeEventRecord>(predicate: #Predicate { $0.receivedAt < cutoff }))
            for event in oldEvents { context.delete(event) }
            deletedEvents = oldEvents.count

            let oldSessions = try context.fetch(FetchDescriptor<ClaudeSession>(predicate: #Predicate { $0.updatedAt < cutoff }))
            for session in oldSessions where !session.isActive {
                try deleteEvents(of: session.id, context: context)
                context.delete(session)
                deletedSessions += 1
            }
            try context.save()
            if deletedEvents + deletedSessions > 0 {
                Log.persistence.info("Retention removed \(deletedEvents, privacy: .public) events and \(deletedSessions, privacy: .public) sessions")
            }
        } catch {
            Log.persistence.error("Retention cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
        return (deletedEvents, deletedSessions)
    }

    /// Deletes a historical session and its events. Refuses active sessions.
    @discardableResult
    static func delete(_ session: ClaudeSession, context: ModelContext) -> Bool {
        guard !session.isActive else { return false }
        do {
            try deleteEvents(of: session.id, context: context)
            context.delete(session)
            try context.save()
            return true
        } catch {
            Log.persistence.error("Could not delete session: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func deleteEvents(of sessionID: String, context: ModelContext) throws {
        let events = try context.fetch(FetchDescriptor<ClaudeEventRecord>(predicate: #Predicate { $0.sessionID == sessionID }))
        for event in events { context.delete(event) }
    }
}
