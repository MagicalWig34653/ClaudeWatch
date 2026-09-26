import Foundation

/// Rendered notification text for both channels.
public struct NotificationContent: Sendable, Equatable {
    public var sessionID: String
    /// Native: "Claude · backend-api"
    public var nativeTitle: String
    /// Native: "Needs your input"
    public var nativeSubtitle: String
    /// Native body: message preview (may be empty).
    public var nativeBody: String
    /// Pushover: "Claude · work · backend"
    public var pushoverTitle: String
    /// Pushover: "❓ Claude needs input\nWhich migration strategy should be used?"
    public var pushoverMessage: String
    public var url: URL?
}

public enum NotificationContentBuilder {
    public static func build(event: ClaudeEvent, rule: NotificationRuleSnapshot) -> NotificationContent {
        let project = rule.includeProjectName ? event.projectName : nil
        let account = rule.includeAccountAlias ? event.accountAlias : nil
        let preview = rule.includeMessagePreview ? TextSanitizer.preview(event.message, maxLength: 240) : nil

        let nativeTitle = (["Claude", project].compactMap { $0 }).joined(separator: " · ")
        let pushoverTitle = (["Claude", account, project].compactMap { $0 }).joined(separator: " · ")

        let headline = headline(for: event.type)
        var pushoverLines = ["\(headline.emoji) \(headline.pushover)"]
        if let preview {
            pushoverLines.append(preview)
        } else if event.type == .finished, let project {
            pushoverLines.append(project)
        }

        return NotificationContent(
            sessionID: event.sessionID,
            nativeTitle: nativeTitle,
            nativeSubtitle: headline.native,
            nativeBody: preview ?? "",
            pushoverTitle: TextSanitizer.truncate(pushoverTitle, to: 250),
            pushoverMessage: TextSanitizer.truncate(pushoverLines.joined(separator: "\n"), to: 1024),
            url: event.remoteURL
        )
    }

    static func headline(for type: ClaudeEventType) -> (emoji: String, pushover: String, native: String) {
        switch type {
        case .needsInput: return ("❓", "Claude needs input", "Needs your input")
        case .permissionRequired: return ("🔐", "Permission required", "Permission required")
        case .planApprovalRequired: return ("📋", "Plan approval required", "Plan ready for approval")
        case .finished: return ("✅", "Claude finished", "Session finished")
        case .failed: return ("❌", "Claude failed", "Session failed")
        case .sessionStarted: return ("▶️", "Session started", "Session started")
        case .sessionEnded: return ("⏹", "Session ended", "Session ended")
        case .idle: return ("💤", "Claude is waiting", "Waiting for your next prompt")
        case .activity: return ("•", "Claude is working", "Working")
        }
    }
}
