import Foundation

/// The subset of a Claude Code hook payload that ClaudeWatch uses.
///
/// Field names follow the JSON Claude Code writes to a hook's stdin (verified against
/// Claude Code 2.1.x). Unknown fields are ignored; every field except
/// `hook_event_name` and `session_id` is optional, and a field with an unexpected
/// type is treated as absent rather than failing the whole payload.
/// Prompt text (`prompt`) and tool results (`tool_response`) are deliberately not decoded.
public struct HookPayload: Sendable, Equatable, Decodable {
    public let hookEventName: String
    public let sessionID: String

    public let cwd: String?
    public let transcriptPath: String?
    public let promptID: String?
    public let permissionMode: String?

    // Tool events (PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, PermissionDenied)
    public let toolName: String?
    public let toolInput: JSONValue?

    // Notification / Elicitation
    public let message: String?
    public let title: String?
    public let notificationType: String?
    public let mcpServerName: String?

    // Stop / StopFailure / SubagentStop
    public let lastAssistantMessage: String?
    public let error: String?
    public let errorDetails: String?

    // SessionStart (`source`) / SessionEnd (`reason`)
    public let source: String?
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case transcriptPath = "transcript_path"
        case promptID = "prompt_id"
        case permissionMode = "permission_mode"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case message
        case title
        case notificationType = "notification_type"
        case mcpServerName = "mcp_server_name"
        case lastAssistantMessage = "last_assistant_message"
        case error
        case errorDetails = "error_details"
        case source
        case reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try c.decode(String.self, forKey: .hookEventName)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        func string(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        cwd = string(.cwd)
        transcriptPath = string(.transcriptPath)
        promptID = string(.promptID)
        permissionMode = string(.permissionMode)
        toolName = string(.toolName)
        toolInput = (try? c.decodeIfPresent(JSONValue.self, forKey: .toolInput)) ?? nil
        message = string(.message)
        title = string(.title)
        notificationType = string(.notificationType)
        mcpServerName = string(.mcpServerName)
        lastAssistantMessage = string(.lastAssistantMessage)
        error = string(.error)
        errorDetails = string(.errorDetails)
        source = string(.source)
        reason = string(.reason)
    }

    public init(
        hookEventName: String, sessionID: String, cwd: String? = nil, transcriptPath: String? = nil,
        promptID: String? = nil, permissionMode: String? = nil, toolName: String? = nil,
        toolInput: JSONValue? = nil, message: String? = nil, title: String? = nil,
        notificationType: String? = nil, mcpServerName: String? = nil,
        lastAssistantMessage: String? = nil, error: String? = nil, errorDetails: String? = nil,
        source: String? = nil, reason: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.promptID = promptID
        self.permissionMode = permissionMode
        self.toolName = toolName
        self.toolInput = toolInput
        self.message = message
        self.title = title
        self.notificationType = notificationType
        self.mcpServerName = mcpServerName
        self.lastAssistantMessage = lastAssistantMessage
        self.error = error
        self.errorDetails = errorDetails
        self.source = source
        self.reason = reason
    }
}
