import Foundation

/// One notification waiting in the grouping window.
public struct NotificationBatchItem: Sendable, Equatable {
    public let event: ClaudeEvent
    public let rule: NotificationRuleSnapshot

    public init(event: ClaudeEvent, rule: NotificationRuleSnapshot) {
        self.event = event
        self.rule = rule
    }
}

/// Combines several notifications that arrived within the grouping window into one.
public enum NotificationSummaryBuilder {
    /// Session lines listed before collapsing the rest into "+N more".
    public static let maxListedItems = 6

    /// Content for a group. A single item renders exactly like an individual notification.
    public static func build(_ items: [NotificationBatchItem]) -> NotificationContent {
        guard items.count > 1 else {
            precondition(!items.isEmpty, "A notification group needs at least one item")
            return NotificationContentBuilder.build(event: items[0].event, rule: items[0].rule)
        }

        let ordered = items.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (urgency(lhs.element.event.type), urgency(rhs.element.event.type))
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
        let types = Set(items.map(\.event.type))
        let sessionCount = Set(items.map(\.event.sessionID)).count
        let headline = types.count == 1 ? groupHeadline(for: items[0].event.type, count: items.count) : "\(items.count) session updates"
        let emoji = types.count == 1 ? NotificationContentBuilder.headline(for: items[0].event.type).emoji : "🔔"

        let lines = ordered.prefix(maxListedItems).map { item -> String in
            let name = item.rule.includeProjectName ? (item.event.projectName ?? "Session") : "Session"
            let prefix = NotificationContentBuilder.headline(for: item.event.type).emoji
            return types.count == 1 ? "\(prefix) \(name)" : "\(prefix) \(name) — \(shortStatus(item.event.type))"
        }
        var body = lines
        if ordered.count > maxListedItems {
            body.append("+\(ordered.count - maxListedItems) more")
        }

        // Only name the account when every grouped event belongs to the same one.
        let aliases = Set(items.map { $0.rule.includeAccountAlias ? $0.event.accountAlias : nil })
        let account = aliases.count == 1 ? aliases.first ?? nil : nil
        let sessions = sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"

        return NotificationContent(
            sessionID: sessionCount == 1 ? items[0].event.sessionID : "",
            nativeTitle: "Claude · \(sessions)",
            nativeSubtitle: headline,
            nativeBody: body.joined(separator: "\n"),
            pushoverTitle: (["Claude", account, sessions].compactMap { $0 }).joined(separator: " · "),
            pushoverMessage: TextSanitizer.truncate((["\(emoji) \(headline)"] + body).joined(separator: "\n"), to: 1024),
            url: nil
        )
    }

    /// Highest Pushover priority of the group, so one urgent event keeps its urgency.
    public static func pushoverPriority(_ items: [NotificationBatchItem]) -> Int {
        items.map(\.rule.pushoverPriority).max() ?? 0
    }

    static func groupHeadline(for type: ClaudeEventType, count: Int) -> String {
        switch type {
        case .needsInput: return "\(count) sessions need input"
        case .permissionRequired: return "\(count) sessions need permission"
        case .planApprovalRequired: return "\(count) plans ready for approval"
        case .finished: return "\(count) sessions finished"
        case .failed: return "\(count) sessions failed"
        case .sessionStarted: return "\(count) sessions started"
        case .sessionEnded: return "\(count) sessions ended"
        case .idle: return "\(count) sessions are waiting"
        case .activity: return "\(count) sessions are working"
        }
    }

    static func shortStatus(_ type: ClaudeEventType) -> String {
        switch type {
        case .needsInput: return "needs input"
        case .permissionRequired: return "needs permission"
        case .planApprovalRequired: return "plan ready"
        case .finished: return "finished"
        case .failed: return "failed"
        case .sessionStarted: return "started"
        case .sessionEnded: return "ended"
        case .idle: return "waiting"
        case .activity: return "working"
        }
    }

    /// Attention-worthy events are listed first.
    static func urgency(_ type: ClaudeEventType) -> Int {
        switch type {
        case .needsInput: return 0
        case .permissionRequired: return 1
        case .planApprovalRequired: return 2
        case .failed: return 3
        case .finished: return 4
        case .idle: return 5
        case .sessionEnded: return 6
        case .sessionStarted: return 7
        case .activity: return 8
        }
    }
}
