import AppKit
import Foundation
import Observation
import UserNotifications
import ClaudeWatchCore

@MainActor
protocol NativeNotifying {
    func deliver(_ content: NotificationContent, playSound: Bool) async throws
}

enum NativeNotificationError: LocalizedError, Equatable {
    case notAuthorized
    case deliveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "macOS notifications are not allowed for ClaudeWatch. Enable them in System Settings › Notifications."
        case .deliveryFailed(let reason):
            return "macOS notification could not be shown: \(reason)"
        }
    }
}

/// Wraps `UNUserNotificationCenter`: authorization, delivery, foreground presentation and click routing.
@MainActor
@Observable
final class NativeNotificationService: NSObject, NativeNotifying {
    enum Authorization: Equatable {
        case notDetermined, denied, authorized, provisional, unknown

        var displayName: String {
            switch self {
            case .notDetermined: return "Not requested yet"
            case .denied: return "Denied"
            case .authorized: return "Allowed"
            case .provisional: return "Allowed (quietly)"
            case .unknown: return "Unknown"
            }
        }
    }

    nonisolated static let sessionIDKey = "sessionID"
    nonisolated static let remoteURLKey = "remoteURL"

    private(set) var authorization: Authorization = .unknown

    /// Called on the main actor when the user clicks a notification.
    @ObservationIgnored var onActivate: ((_ sessionID: String?, _ remoteURL: URL?) -> Void)?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = Self.map(settings.authorizationStatus)
    }

    /// Requests authorization only if the user has not decided yet. Never re-prompts after denial.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorization()
        switch authorization {
        case .authorized, .provisional:
            return true
        case .denied, .unknown:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                Log.notifications.info("Notification authorization granted: \(granted, privacy: .public)")
            } catch {
                Log.notifications.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
            await refreshAuthorization()
            return authorization == .authorized || authorization == .provisional
        }
    }

    func deliver(_ content: NotificationContent, playSound: Bool) async throws {
        guard await requestAuthorizationIfNeeded() else { throw NativeNotificationError.notAuthorized }

        let notification = UNMutableNotificationContent()
        notification.title = content.nativeTitle
        notification.subtitle = content.nativeSubtitle
        notification.body = content.nativeBody
        notification.threadIdentifier = content.sessionID
        notification.sound = playSound ? .default : nil
        var userInfo: [String: String] = [Self.sessionIDKey: content.sessionID]
        if let url = content.url { userInfo[Self.remoteURLKey] = url.absoluteString }
        notification.userInfo = userInfo

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: notification, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            throw NativeNotificationError.deliveryFailed(error.localizedDescription)
        }
    }

    func sendTestNotification() async throws {
        let content = NotificationContent(
            sessionID: "claudewatch-test",
            nativeTitle: "Claude · ClaudeWatch",
            nativeSubtitle: "Test notification",
            nativeBody: "macOS notifications are working.",
            pushoverTitle: "",
            pushoverMessage: "",
            url: nil
        )
        try await deliver(content, playSound: UserDefaults.standard.bool(forKey: Preferences.Key.notificationSoundEnabled))
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> Authorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        @unknown default: return .unknown
        }
    }
}

extension NativeNotificationService: UNUserNotificationCenterDelegate {
    /// Show notifications even while ClaudeWatch is frontmost; the user's rules decide, not app focus.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let sessionID = userInfo[Self.sessionIDKey] as? String
        let remoteURL = (userInfo[Self.remoteURLKey] as? String).flatMap(URL.init(string:))
        let isDefaultAction = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        Task { @MainActor in
            if isDefaultAction {
                self.onActivate?(sessionID, remoteURL)
            }
            completionHandler()
        }
    }
}
