import Foundation
import SwiftData
import ClaudeWatchCore

/// Per-event-type notification configuration.
@Model
final class NotificationRule {
    @Attribute(.unique) var eventTypeRaw: String
    var enabled: Bool
    var sendNativeNotification: Bool
    var sendPushover: Bool
    var pushoverPriority: Int
    var playNativeSound: Bool
    var includeProjectName: Bool
    var includeAccountAlias: Bool
    var includeMessagePreview: Bool

    init(snapshot: NotificationRuleSnapshot) {
        self.eventTypeRaw = snapshot.eventType.rawValue
        self.enabled = snapshot.enabled
        self.sendNativeNotification = snapshot.sendNativeNotification
        self.sendPushover = snapshot.sendPushover
        self.pushoverPriority = snapshot.pushoverPriority
        self.playNativeSound = snapshot.playNativeSound
        self.includeProjectName = snapshot.includeProjectName
        self.includeAccountAlias = snapshot.includeAccountAlias
        self.includeMessagePreview = snapshot.includeMessagePreview
    }

    var eventType: ClaudeEventType? { ClaudeEventType(rawValue: eventTypeRaw) }

    var snapshot: NotificationRuleSnapshot? {
        guard let eventType else { return nil }
        return NotificationRuleSnapshot(
            eventType: eventType,
            enabled: enabled,
            sendNativeNotification: sendNativeNotification,
            sendPushover: sendPushover,
            pushoverPriority: pushoverPriority,
            playNativeSound: playNativeSound,
            includeProjectName: includeProjectName,
            includeAccountAlias: includeAccountAlias,
            includeMessagePreview: includeMessagePreview
        )
    }

    /// Keeps `enabled` consistent with the channel checkboxes in the rule editor.
    func updateEnabledFromChannels() {
        enabled = sendNativeNotification || sendPushover
    }
}
