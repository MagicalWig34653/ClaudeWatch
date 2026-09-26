import OSLog

/// Unified logging categories. Never log secrets; message content only at debug level.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.claudewatch.ClaudeWatch"

    static let listener = Logger(subsystem: subsystem, category: "listener")
    static let events = Logger(subsystem: subsystem, category: "events")
    static let sessions = Logger(subsystem: subsystem, category: "sessions")
    static let pushover = Logger(subsystem: subsystem, category: "pushover")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let cswap = Logger(subsystem: subsystem, category: "cswap")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
