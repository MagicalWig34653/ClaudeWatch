import Foundation
import SwiftData
import ClaudeWatchCore

/// A received event: history, debugging aid and deduplication source.
@Model
final class ClaudeEventRecord {
    @Attribute(.unique) var id: UUID
    var sessionID: String
    var eventTypeRaw: String
    var receivedAt: Date
    var sourceTimestamp: Date?

    var message: String?
    var toolName: String?
    var projectName: String?
    var accountAlias: String?

    /// Deterministic fingerprint of the logical event (see `EventFingerprint`).
    var fingerprint: String
    var isDuplicate: Bool
    var isSupplementary: Bool

    var wasPushoverSent: Bool
    var wasNativeNotificationSent: Bool

    var pushoverError: String?
    var nativeNotificationError: String?

    init(event: ClaudeEvent, fingerprint: String, isDuplicate: Bool, receivedAt: Date) {
        self.id = UUID()
        self.sessionID = event.sessionID
        self.eventTypeRaw = event.type.rawValue
        self.receivedAt = receivedAt
        self.sourceTimestamp = event.timestamp
        self.message = event.message
        self.toolName = event.toolName
        self.projectName = event.projectName
        self.accountAlias = event.accountAlias
        self.fingerprint = fingerprint
        self.isDuplicate = isDuplicate
        self.isSupplementary = event.isSupplementary
        self.wasPushoverSent = false
        self.wasNativeNotificationSent = false
    }

    /// `nil` for event types this build does not know (e.g. written by a newer version).
    var eventType: ClaudeEventType? { ClaudeEventType(rawValue: eventTypeRaw) }

    var displayName: String { eventType?.displayName ?? eventTypeRaw }
}
