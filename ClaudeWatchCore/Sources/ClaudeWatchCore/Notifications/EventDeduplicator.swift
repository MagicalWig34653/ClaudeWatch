import Foundation

/// Deterministic fingerprint of the logical state an event represents.
public enum EventFingerprint {
    public static func make(for event: ClaudeEvent) -> String {
        let normalizedMessage = (event.message ?? "")
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let components = [
            event.sessionID,
            event.type.rawValue,
            event.turnID ?? "",
            event.toolName ?? "",
            normalizedMessage,
        ]
        return fnv1a64(components.joined(separator: "\u{1F}"))
    }

    /// FNV-1a (64-bit). Stable across launches and platforms, unlike `Hasher`.
    static func fnv1a64(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

/// Decides whether an event is a repeat of one that was already accepted.
public struct EventDeduplicator: Sendable {
    /// A previously recorded, non-duplicate event of the same session.
    public struct PriorEvent: Sendable, Equatable {
        public let fingerprint: String
        public let type: ClaudeEventType
        public let receivedAt: Date
        public let isSupplementary: Bool

        public init(fingerprint: String, type: ClaudeEventType, receivedAt: Date, isSupplementary: Bool) {
            self.fingerprint = fingerprint
            self.type = type
            self.receivedAt = receivedAt
            self.isSupplementary = isSupplementary
        }
    }

    /// Window in which an identical fingerprint is considered the same logical event.
    public var identicalWindow: TimeInterval
    /// Window in which a notification-hook event and a specific hook event of the
    /// same type are considered two reports of the same state.
    public var crossSourceWindow: TimeInterval

    public init(identicalWindow: TimeInterval = 300, crossSourceWindow: TimeInterval = 30) {
        self.identicalWindow = identicalWindow
        self.crossSourceWindow = crossSourceWindow
    }

    public func isDuplicate(_ event: ClaudeEvent, fingerprint: String, priorEvents: [PriorEvent]) -> Bool {
        for prior in priorEvents {
            let age = event.timestamp.timeIntervalSince(prior.receivedAt)
            guard age >= -5 else { continue } // tolerate small clock skew; ignore events from the future
            if prior.fingerprint == fingerprint, age <= identicalWindow {
                return true
            }
            if prior.type == event.type,
               event.isSupplementary || prior.isSupplementary,
               age <= crossSourceWindow {
                return true
            }
        }
        return false
    }
}
