import Foundation
import ClaudeWatchCore

/// Keys and defaults for lightweight preferences stored in UserDefaults / `@AppStorage`.
/// Secrets never go here — see `KeychainService`.
enum Preferences {
    enum Key {
        static let showMenuBarItem = "showMenuBarItem"
        static let nativeNotificationsEnabled = "nativeNotificationsEnabled"
        static let pushoverEnabled = "pushoverEnabled"
        static let notificationSoundEnabled = "notificationSoundEnabled"
        static let historyRetentionDays = "historyRetentionDays"
        static let listenerPort = "listenerPort"
        /// Seconds since 1970; 0 = not paused.
        static let notificationsPausedUntil = "notificationsPausedUntil"
        static let cswapPathOverride = "cswapPathOverride"
        /// Seconds notifications are collected before sending; 0 sends each immediately.
        static let notificationGroupingWindow = "notificationGroupingWindow"
    }

    static let defaultGroupingWindow: TimeInterval = 5

    static let defaultListenerPort = 17831
    static let defaultRetentionDays = 30
    /// Stored as `pausedUntil` when paused until manually resumed.
    static let pausedIndefinitely = Date.distantFuture.timeIntervalSince1970

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.showMenuBarItem: true,
            Key.nativeNotificationsEnabled: true,
            Key.pushoverEnabled: false,
            Key.notificationSoundEnabled: true,
            Key.historyRetentionDays: defaultRetentionDays,
            Key.listenerPort: defaultListenerPort,
            Key.notificationsPausedUntil: 0.0,
            Key.cswapPathOverride: "",
            Key.notificationGroupingWindow: defaultGroupingWindow,
        ])
    }

    static func isPaused(pausedUntil: Double, now: Date = Date()) -> Bool {
        pausedUntil > now.timeIntervalSince1970
    }

    static func notificationPreferences(from defaults: UserDefaults = .standard, now: Date = Date()) -> NotificationPreferences {
        NotificationPreferences(
            nativeNotificationsEnabled: defaults.bool(forKey: Key.nativeNotificationsEnabled),
            pushoverEnabled: defaults.bool(forKey: Key.pushoverEnabled),
            soundEnabled: defaults.bool(forKey: Key.notificationSoundEnabled),
            isPaused: isPaused(pausedUntil: defaults.double(forKey: Key.notificationsPausedUntil), now: now)
        )
    }

    static func notificationGroupingWindow(from defaults: UserDefaults = .standard) -> TimeInterval {
        min(max(defaults.double(forKey: Key.notificationGroupingWindow), 0), 300)
    }

    static func listenerPort(from defaults: UserDefaults = .standard) -> UInt16 {
        let value = defaults.integer(forKey: Key.listenerPort)
        return (1024...65535).contains(value) ? UInt16(value) : UInt16(defaultListenerPort)
    }
}
