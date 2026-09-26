import Foundation

/// Value snapshot of a persisted notification rule.
public struct NotificationRuleSnapshot: Sendable, Equatable {
    public var eventType: ClaudeEventType
    public var enabled: Bool
    public var sendNativeNotification: Bool
    public var sendPushover: Bool
    public var pushoverPriority: Int
    public var playNativeSound: Bool
    public var includeProjectName: Bool
    public var includeAccountAlias: Bool
    public var includeMessagePreview: Bool

    public init(
        eventType: ClaudeEventType,
        enabled: Bool,
        sendNativeNotification: Bool,
        sendPushover: Bool,
        pushoverPriority: Int = 0,
        playNativeSound: Bool = true,
        includeProjectName: Bool = true,
        includeAccountAlias: Bool = true,
        includeMessagePreview: Bool = true
    ) {
        self.eventType = eventType
        self.enabled = enabled
        self.sendNativeNotification = sendNativeNotification
        self.sendPushover = sendPushover
        self.pushoverPriority = pushoverPriority
        self.playNativeSound = playNativeSound
        self.includeProjectName = includeProjectName
        self.includeAccountAlias = includeAccountAlias
        self.includeMessagePreview = includeMessagePreview
    }

    /// The rule created on first launch for `type`.
    public static func defaultRule(for type: ClaudeEventType) -> NotificationRuleSnapshot {
        let enabled = type.isEnabledByDefault
        return NotificationRuleSnapshot(
            eventType: type,
            enabled: enabled,
            sendNativeNotification: enabled,
            sendPushover: enabled,
            pushoverPriority: type.defaultPushoverPriority
        )
    }
}

/// Global notification preferences (UserDefaults-backed in the app).
public struct NotificationPreferences: Sendable, Equatable {
    public var nativeNotificationsEnabled: Bool
    public var pushoverEnabled: Bool
    public var soundEnabled: Bool
    public var isPaused: Bool

    public init(nativeNotificationsEnabled: Bool, pushoverEnabled: Bool, soundEnabled: Bool, isPaused: Bool) {
        self.nativeNotificationsEnabled = nativeNotificationsEnabled
        self.pushoverEnabled = pushoverEnabled
        self.soundEnabled = soundEnabled
        self.isPaused = isPaused
    }
}

public struct NotificationDecision: Sendable, Equatable {
    public var sendNative: Bool
    public var sendPushover: Bool
    public var playSound: Bool

    public static let none = NotificationDecision(sendNative: false, sendPushover: false, playSound: false)

    public init(sendNative: Bool, sendPushover: Bool, playSound: Bool) {
        self.sendNative = sendNative
        self.sendPushover = sendPushover
        self.playSound = playSound
    }

    public var sendsAnything: Bool { sendNative || sendPushover }
}

/// Pure notification policy. Each channel is evaluated independently.
public enum NotificationPolicy {
    public static func decide(
        rule: NotificationRuleSnapshot?,
        preferences: NotificationPreferences,
        accountNotificationsEnabled: Bool,
        isDuplicate: Bool
    ) -> NotificationDecision {
        guard let rule, rule.enabled, !isDuplicate, !preferences.isPaused, accountNotificationsEnabled else {
            return .none
        }
        let native = preferences.nativeNotificationsEnabled && rule.sendNativeNotification
        return NotificationDecision(
            sendNative: native,
            sendPushover: preferences.pushoverEnabled && rule.sendPushover,
            playSound: native && preferences.soundEnabled && rule.playNativeSound
        )
    }
}
