import Foundation
import SwiftData
import ClaudeWatchCore

/// Filter in the store, before SwiftUI tracks properties of the returned models.
/// In particular, a compact menu must not observe every historical session just
/// to discard nearly all of them after an in-memory filter/prefix.
enum SessionQueries {
    private static let active = SessionStatus.allCases.filter(\.isActive).map(\.rawValue)

    static var overviewAttention: FetchDescriptor<ClaudeSession> {
        sorted(#Predicate { $0.requiresAttention == true })
    }

    static var menuAttention: FetchDescriptor<ClaudeSession> {
        var descriptor = overviewAttention
        descriptor.fetchLimit = 5
        return descriptor
    }

    static var menuRunning: FetchDescriptor<ClaudeSession> {
        let active = active
        var descriptor = sorted(#Predicate { active.contains($0.statusRaw) && $0.requiresAttention == false })
        descriptor.fetchLimit = 5
        return descriptor
    }

    static var menuFinished: FetchDescriptor<ClaudeSession> {
        let finished = SessionStatus.finished.rawValue
        var descriptor = sorted(#Predicate { $0.statusRaw == finished })
        descriptor.fetchLimit = 3
        return descriptor
    }

    static var overviewRecent: FetchDescriptor<ClaudeSession> {
        let active = active
        var descriptor = sorted(#Predicate { !active.contains($0.statusRaw) })
        descriptor.fetchLimit = 5
        return descriptor
    }

    static func finishedToday(now: Date = Date()) -> FetchDescriptor<ClaudeSession> {
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let finished = SessionStatus.finished.rawValue
        return sorted(#Predicate {
            $0.statusRaw == finished && ($0.finishedAt ?? $0.updatedAt) >= start
                && ($0.finishedAt ?? $0.updatedAt) < end
        })
    }

    static func list(filter: SessionFilter) -> FetchDescriptor<ClaudeSession> {
        let all = filter == .all
        let attention = filter == .attention
        let activeOnly = filter == .active
        let finishedOnly = filter == .finished
        let active = active
        let finished = SessionStatus.finished.rawValue
        let failed = SessionStatus.failed.rawValue
        return sorted(#Predicate {
            (all || (attention && $0.requiresAttention)
                || (activeOnly && active.contains($0.statusRaw))
                || (finishedOnly && ($0.statusRaw == finished || $0.statusRaw == failed)))
        })
    }

    static func matchesSearch(_ session: ClaudeSession, search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [session.projectName, session.accountAlias, session.lastMessage, session.id, session.workingDirectory]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func selected(_ id: String?) -> FetchDescriptor<ClaudeSession> {
        guard let id else { return sorted(#Predicate { _ in false }) }
        var descriptor = sorted(#Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    private static func sorted(_ predicate: Predicate<ClaudeSession>) -> FetchDescriptor<ClaudeSession> {
        FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
    }
}

enum EventHistoryQuery {
    static let pageSize = 100

    static func records(sessionID: String) -> FetchDescriptor<ClaudeEventRecord> {
        FetchDescriptor<ClaudeEventRecord>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
    }

    static func page(sessionID: String, index: Int) -> FetchDescriptor<ClaudeEventRecord> {
        var descriptor = records(sessionID: sessionID)
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = max(0, index) * pageSize
        return descriptor
    }
}
