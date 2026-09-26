import AppKit
import SwiftUI
import SwiftData
import ClaudeWatchCore

/// Compact awareness view. Deliberately not a copy of the main window.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ClaudeSession.updatedAt, order: .reverse) private var sessions: [ClaudeSession]
    @AppStorage(Preferences.Key.notificationsPausedUntil) private var pausedUntil = 0.0

    private var attention: [ClaudeSession] { Array(sessions.filter(\.requiresAttention).prefix(5)) }
    private var running: [ClaudeSession] { Array(sessions.filter { $0.isActive && !$0.requiresAttention }.prefix(5)) }
    private var recentlyFinished: [ClaudeSession] {
        Array(sessions.filter { $0.status == .finished }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ClaudeWatch").font(.headline)
                Spacer()
                if Preferences.isPaused(pausedUntil: pausedUntil) {
                    PausedLabel(pausedUntil: pausedUntil).font(.caption)
                }
            }
            if case .failed(_, let message) = appState.listener.state {
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            if sessions.isEmpty {
                Text("No Claude Code sessions yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            group("Needs Attention", attention)
            group("Running", running)
            group("Recently Finished", recentlyFinished)

            Divider()
            VStack(alignment: .leading, spacing: 2) {
                MenuButton(title: "Open ClaudeWatch", symbol: "macwindow") { openApp(sessionID: nil) }
                if Preferences.isPaused(pausedUntil: pausedUntil) {
                    MenuButton(title: "Resume Notifications", symbol: "bell") { appState.resumeNotifications() }
                } else {
                    MenuButton(title: "Pause Notifications for 1 Hour", symbol: "bell.slash") { appState.pauseNotifications(for: 3600) }
                }
                MenuButton(title: "Quit ClaudeWatch", symbol: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            let openWindow = openWindow
            appState.openMainWindowAction = { openWindow(id: AppState.mainWindowID) }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [ClaudeSession]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(items) { session in
                    Button { openApp(sessionID: session.id) } label: {
                        MenuBarSessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openApp(sessionID: String?) {
        dismiss()
        if let sessionID {
            appState.actionHandler.showSession(sessionID)
        } else {
            appState.openMainWindow()
        }
    }
}

private struct MenuBarSessionRow: View {
    let session: ClaudeSession

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: session.status == .finished ? "checkmark" : "circle.fill")
                .font(session.status == .finished ? .body : .system(size: 8))
                .foregroundStyle(session.status.tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: session.projectName).lineLimit(1)
                HStack(spacing: 4) {
                    Text(verbatim: session.displayAccount)
                    Text("·")
                    if session.status == .finished {
                        Text(session.finishedAt ?? session.updatedAt, style: .relative)
                        Text("ago")
                    } else {
                        Text(session.status.displayName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private struct MenuButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(hovering ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Menu bar icon. Static (never animated); changes shape when a session needs attention.
struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Preferences.Key.notificationsPausedUntil) private var pausedUntil = 0.0

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel(appState.attentionCount > 0 ? "ClaudeWatch: \(appState.attentionCount) sessions need attention" : "ClaudeWatch")
            .onAppear {
                let openWindow = openWindow
                appState.openMainWindowAction = { openWindow(id: AppState.mainWindowID) }
            }
    }

    private var symbol: String {
        if appState.attentionCount > 0 { return "exclamationmark.bubble.fill" }
        if Preferences.isPaused(pausedUntil: pausedUntil) { return "bell.slash" }
        return appState.activeCount > 0 ? "ellipsis.bubble" : "bubble.left"
    }
}
