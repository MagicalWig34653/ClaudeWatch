import Foundation

/// The normalized event that flows through ClaudeWatch.
///
/// Claude Code hook payloads are converted into this type by `ClaudeEventNormalizer`;
/// nothing downstream sees raw hook JSON. A future relay can send this envelope as-is.
public struct ClaudeEvent: Codable, Sendable, Equatable {
    public let type: ClaudeEventType
    public let sessionID: String
    public let timestamp: Date

    public let workingDirectory: String?
    public let projectName: String?
    public let accountAlias: String?

    public let source: SessionSource

    public let remoteSessionID: String?
    public let remoteURL: URL?

    public let message: String?
    public let toolName: String?

    /// Identifier of the user turn the event belongs to (Claude Code `prompt_id`), if known.
    public let turnID: String?
    /// True when derived from a generic notification rather than a specific hook.
    /// Supplementary events never produce a second notification for a state that
    /// was just reported by a specific hook.
    public let isSupplementary: Bool

    public init(
        type: ClaudeEventType,
        sessionID: String,
        timestamp: Date,
        workingDirectory: String? = nil,
        projectName: String? = nil,
        accountAlias: String? = nil,
        source: SessionSource = .local,
        remoteSessionID: String? = nil,
        remoteURL: URL? = nil,
        message: String? = nil,
        toolName: String? = nil,
        turnID: String? = nil,
        isSupplementary: Bool = false
    ) {
        self.type = type
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.workingDirectory = workingDirectory
        self.projectName = projectName
        self.accountAlias = accountAlias
        self.source = source
        self.remoteSessionID = remoteSessionID
        self.remoteURL = remoteURL
        self.message = message
        self.toolName = toolName
        self.turnID = turnID
        self.isSupplementary = isSupplementary
    }
}
