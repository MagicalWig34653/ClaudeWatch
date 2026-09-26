import Foundation

/// Normalized, Claude-Code-independent event kinds.
///
/// Raw values are persisted (SwiftData, notification rules) and must stay stable.
public enum ClaudeEventType: String, Codable, CaseIterable, Sendable, Hashable {
    case sessionStarted = "session_started"
    /// Generic activity: prompt submitted, tool finished, subagent work, …
    case activity = "activity"
    case needsInput = "needs_input"
    case permissionRequired = "permission_required"
    case planApprovalRequired = "plan_approval_required"
    case finished = "finished"
    case failed = "failed"
    case sessionEnded = "session_ended"
    /// Claude Code has been idle, waiting for a new prompt (`idle_prompt`).
    case idle = "idle"

    /// Event types that can be configured in the notification rule editor, in display order.
    public static let notifiable: [ClaudeEventType] = [
        .needsInput, .permissionRequired, .planApprovalRequired,
        .finished, .failed, .sessionStarted, .sessionEnded, .idle,
    ]

    /// Event types whose rules are enabled on first launch.
    public var isEnabledByDefault: Bool {
        switch self {
        case .needsInput, .permissionRequired, .planApprovalRequired, .finished, .failed:
            return true
        case .sessionStarted, .activity, .sessionEnded, .idle:
            return false
        }
    }

    /// Suggested Pushover priority on first launch (-2 … 1).
    public var defaultPushoverPriority: Int {
        switch self {
        case .needsInput, .permissionRequired, .planApprovalRequired, .failed:
            return 1
        default:
            return 0
        }
    }

    public var displayName: String {
        switch self {
        case .sessionStarted: return "Started"
        case .activity: return "Activity"
        case .needsInput: return "Needs Input"
        case .permissionRequired: return "Permission Required"
        case .planApprovalRequired: return "Plan Approval"
        case .finished: return "Finished"
        case .failed: return "Failed"
        case .sessionEnded: return "Session Ended"
        case .idle: return "Idle Reminder"
        }
    }
}
