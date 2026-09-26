import AppKit
import Foundation
import ClaudeWatchCore

/// Central routing for "open this session" requests from notifications, the menu bar and URLs.
@MainActor
final class NotificationActionHandler {
    static let urlScheme = "claudewatch"

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Opens a remote session URL when present, otherwise the session inside ClaudeWatch.
    func activate(sessionID: String?, remoteURL: URL?) {
        if let remoteURL, remoteURL.scheme?.lowercased() == "https" {
            NSWorkspace.shared.open(remoteURL)
            return
        }
        showSession(sessionID)
    }

    func showSession(_ sessionID: String?) {
        guard let appState else { return }
        if let sessionID, HookPayloadDecoder.isValidSessionID(sessionID) {
            appState.selectedSection = .sessions
            appState.selectedSessionID = sessionID
            appState.sessionFilter = .all
        }
        openMainWindow()
    }

    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let open = appState?.openMainWindowAction {
            open()
        } else if let url = URL(string: "\(Self.urlScheme)://open") {
            // Fallback: the main Window scene handles claudewatch:// URLs and reopens itself.
            NSWorkspace.shared.open(url)
        }
    }

    /// Handles `claudewatch://session/<id>`, `claudewatch://section/<name>` and `claudewatch://open`.
    func handle(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme, let appState else { return }
        let argument = url.pathComponents.dropFirst().first
        switch url.host {
        case "session":
            if let id = argument, HookPayloadDecoder.isValidSessionID(id) {
                appState.selectedSection = .sessions
                appState.selectedSessionID = id
                appState.sessionFilter = .all
            }
        case "section":
            if let name = argument, let section = SidebarSection(rawValue: name) {
                appState.selectedSection = section
            }
        default:
            break
        }
    }

    static func sessionURL(for sessionID: String) -> URL? {
        URL(string: "\(urlScheme)://session/\(sessionID)")
    }
}
