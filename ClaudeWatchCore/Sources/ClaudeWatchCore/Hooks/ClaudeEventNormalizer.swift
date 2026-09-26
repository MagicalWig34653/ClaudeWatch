import Foundation

/// Converts Claude Code hook payloads into normalized `ClaudeEvent`s.
///
/// This is the only place that knows how Claude Code hook events map to ClaudeWatch
/// semantics. When hook schemas change, only this type (and `HookPayload`) should need updating.
public struct ClaudeEventNormalizer: Sendable {
    public enum Outcome: Sendable, Equatable {
        case event(ClaudeEvent)
        case ignored(reason: String)
    }

    /// Tool names Claude Code uses for user-facing interaction.
    public enum Tool {
        public static let askUserQuestion = "AskUserQuestion"
        public static let exitPlanMode = "ExitPlanMode"
    }

    public let source: SessionSource

    public init(source: SessionSource = .local) {
        self.source = source
    }

    public func normalize(_ payload: HookPayload, receivedAt: Date, accountAlias: String? = nil) -> Outcome {
        guard let (type, message, isSupplementary) = classify(payload) else {
            return .ignored(reason: "Unhandled hook event '\(TextSanitizer.truncate(payload.hookEventName, to: 64))'")
        }
        let cwd = payload.cwd.flatMap { $0.isEmpty ? nil : $0 }
        return .event(ClaudeEvent(
            type: type,
            sessionID: payload.sessionID,
            timestamp: receivedAt,
            workingDirectory: cwd,
            projectName: cwd.map(Self.projectName(forDirectory:)),
            accountAlias: accountAlias,
            source: source,
            message: TextSanitizer.preview(message, maxLength: 1000),
            toolName: payload.toolName,
            turnID: payload.promptID,
            isSupplementary: isSupplementary
        ))
    }

    public static func projectName(forDirectory path: String) -> String {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        let last = (trimmed as NSString).lastPathComponent
        return last.isEmpty ? trimmed : last
    }

    // MARK: - Classification

    private func classify(_ p: HookPayload) -> (ClaudeEventType, String?, Bool)? {
        switch p.hookEventName {
        case "SessionStart":
            // `clear` and `compact` restart context inside an existing session.
            if p.source == "clear" || p.source == "compact" { return (.activity, nil, false) }
            return (.sessionStarted, nil, false)

        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "PermissionDenied",
             "SubagentStart", "SubagentStop", "PreCompact":
            return (.activity, nil, false)

        case "PreToolUse":
            switch p.toolName {
            case Tool.askUserQuestion: return (.needsInput, Self.questionText(p.toolInput), false)
            case Tool.exitPlanMode: return (.planApprovalRequired, Self.planSummary(p.toolInput), false)
            default: return (.activity, nil, false)
            }

        case "PermissionRequest":
            switch p.toolName {
            case Tool.askUserQuestion: return (.needsInput, Self.questionText(p.toolInput), false)
            case Tool.exitPlanMode: return (.planApprovalRequired, Self.planSummary(p.toolInput), false)
            default: return (.permissionRequired, Self.permissionSummary(toolName: p.toolName, input: p.toolInput), false)
            }

        case "Elicitation":
            return (.needsInput, p.message, false)

        case "Notification":
            switch p.notificationType {
            case "permission_prompt", "worker_permission_prompt":
                return (.permissionRequired, p.message, true)
            case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                return (.needsInput, p.message, true)
            case "idle_prompt":
                return (.idle, p.message, true)
            default:
                return nil
            }

        case "Stop":
            return (.finished, p.lastAssistantMessage, false)

        case "StopFailure":
            let parts = [p.error.map(Self.describeStopFailure), p.errorDetails].compactMap { $0 }
            return (.failed, parts.isEmpty ? nil : parts.joined(separator: " — "), false)

        case "SessionEnd":
            return (.sessionEnded, p.reason, false)

        default:
            return nil
        }
    }

    static func questionText(_ input: JSONValue?) -> String? {
        guard let questions = input?["questions"]?.arrayValue, !questions.isEmpty else { return nil }
        let first = questions[0]["question"]?.stringValue ?? questions[0]["header"]?.stringValue
        guard let first else { return nil }
        return questions.count > 1 ? "\(first) (+\(questions.count - 1) more)" : first
    }

    static func planSummary(_ input: JSONValue?) -> String? {
        TextSanitizer.firstLine(input?["plan"]?.stringValue)
    }

    static func permissionSummary(toolName: String?, input: JSONValue?) -> String {
        guard let toolName else { return "Claude wants to use a tool." }
        let detail: String?
        switch toolName {
        case "Bash": detail = input?["command"]?.stringValue
        case "Edit", "Write", "Read", "NotebookEdit", "MultiEdit": detail = input?["file_path"]?.stringValue ?? input?["notebook_path"]?.stringValue
        case "WebFetch": detail = input?["url"]?.stringValue
        case "WebSearch": detail = input?["query"]?.stringValue
        default: detail = nil
        }
        if let detail = TextSanitizer.firstLine(detail, maxLength: 200) {
            return "\(toolName): \(detail)"
        }
        return "Claude wants to use \(toolName)."
    }

    static func describeStopFailure(_ code: String) -> String {
        switch code {
        case "rate_limit": return "Rate limit reached"
        case "authentication_failed": return "Authentication failed"
        case "billing_error": return "Billing error"
        case "overloaded": return "API overloaded"
        case "server_error": return "Server error"
        case "max_output_tokens": return "Maximum output tokens reached"
        case "invalid_request": return "Invalid request"
        case "model_not_found": return "Model not found"
        default: return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
