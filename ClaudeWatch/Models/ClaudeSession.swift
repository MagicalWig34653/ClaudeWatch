import Foundation
import SwiftData
import ClaudeWatchCore

/// Current state of one Claude Code session. Updated only by `ClaudeEventProcessor`.
@Model
final class ClaudeSession {
    @Attribute(.unique) var id: String
    var projectName: String
    var workingDirectory: String?
    var accountAlias: String?

    var sourceRaw: String
    var statusRaw: String

    var remoteSessionID: String?
    var remoteURL: URL?

    var startedAt: Date
    var updatedAt: Date
    var finishedAt: Date?

    var lastMessage: String?
    var lastEventTypeRaw: String?

    var requiresAttention: Bool

    init(id: String, projectName: String, source: SessionSource, status: SessionStatus, startedAt: Date) {
        self.id = id
        self.projectName = projectName
        self.sourceRaw = source.rawValue
        self.statusRaw = status.rawValue
        self.startedAt = startedAt
        self.updatedAt = startedAt
        self.requiresAttention = SessionStateMachine.requiresAttention(status)
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .unknown }
        set {
            statusRaw = newValue.rawValue
            requiresAttention = SessionStateMachine.requiresAttention(newValue)
        }
    }

    var source: SessionSource {
        get { SessionSource(rawValue: sourceRaw) ?? .unknown }
        set { sourceRaw = newValue.rawValue }
    }

    /// `nil` for event types written by a newer/older version that this build does not know.
    var lastEventType: ClaudeEventType? {
        lastEventTypeRaw.flatMap(ClaudeEventType.init(rawValue:))
    }

    var displayAccount: String {
        accountAlias ?? AccountResolver.unknownAccountName
    }

    var isActive: Bool { status.isActive }
}
