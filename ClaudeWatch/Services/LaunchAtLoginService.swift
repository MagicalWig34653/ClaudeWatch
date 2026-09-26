import Foundation
import Observation
import ServiceManagement

/// Launch at login via `SMAppService.mainApp`. Never touches ~/Library/LaunchAgents.
@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?

    init() {
        refresh()
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    var statusDescription: String {
        switch status {
        case .enabled: return "ClaudeWatch opens automatically when you log in."
        case .requiresApproval: return "Waiting for approval in System Settings › General › Login Items."
        case .notRegistered: return "ClaudeWatch does not open at login."
        case .notFound: return "Launch at login is unavailable for this copy of ClaudeWatch."
        @unknown default: return "Unknown login item state."
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
