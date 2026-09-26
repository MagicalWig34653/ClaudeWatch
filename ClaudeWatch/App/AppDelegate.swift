import AppKit

/// Keeps ClaudeWatch running in the menu bar after its window is closed and brings the
/// window back when the app is reopened (Dock icon, Finder, Spotlight).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let url = URL(string: "\(NotificationActionHandler.urlScheme)://open") {
            // The main Window scene handles claudewatch:// URLs and reopens itself.
            NSApp.setActivationPolicy(.regular)
            NSWorkspace.shared.open(url)
        }
        return true
    }
}
