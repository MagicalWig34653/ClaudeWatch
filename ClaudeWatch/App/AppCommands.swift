import SwiftUI

struct AppCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(SidebarSection.allCases) { section in
                Button(section.title) {
                    appState.selectedSection = section
                    appState.openMainWindow()
                }
                .keyboardShortcut(section.shortcut, modifiers: .command)
            }
            Divider()
        }
        CommandMenu("Monitoring") {
            Button("Send Test Event") {
                Task { await appState.sendTestEvent() }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("Pause Notifications for 1 Hour") { appState.pauseNotifications(for: 3600) }
            Button("Pause Notifications") { appState.pauseNotifications(for: nil) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Resume Notifications") { appState.resumeNotifications() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
