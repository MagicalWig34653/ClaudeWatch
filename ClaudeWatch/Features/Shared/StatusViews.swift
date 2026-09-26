import SwiftUI
import ClaudeWatchCore

extension SessionStatus {
    var symbol: String {
        switch self {
        case .running: return "circle.dotted.circle"
        case .needsInput: return "questionmark.bubble.fill"
        case .waitingForPermission: return "lock.fill"
        case .waitingForPlanApproval: return "list.clipboard.fill"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .unknown: return "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .running: return .blue
        case .needsInput, .waitingForPermission, .waitingForPlanApproval: return .orange
        case .finished: return .green
        case .failed: return .red
        case .unknown: return .secondary
        }
    }
}

extension ClaudeEventType {
    var symbol: String {
        switch self {
        case .sessionStarted: return "play.circle"
        case .activity: return "bolt.horizontal.circle"
        case .needsInput: return "questionmark.bubble"
        case .permissionRequired: return "lock"
        case .planApprovalRequired: return "list.clipboard"
        case .finished: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        case .sessionEnded: return "stop.circle"
        case .idle: return "moon.zzz"
        }
    }
}

struct StatusLabel: View {
    let status: SessionStatus

    var body: some View {
        Label(status.displayName, systemImage: status.symbol)
            .foregroundStyle(status.tint)
    }
}

struct SessionRow: View {
    let session: ClaudeSession

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: session.status.symbol)
                .foregroundStyle(session.status.tint)
                .frame(width: 16)
                .accessibilityLabel(session.status.displayName)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: session.projectName)
                        .fontWeight(session.requiresAttention ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    Text(session.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 4) {
                    Text(verbatim: session.displayAccount)
                    Text("·")
                    Text(session.status.displayName)
                        .foregroundStyle(session.status.tint)
                    if session.source != .local {
                        Text("·")
                        Text(session.source.displayName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Listener and pause status shown at the bottom of the sidebar.
struct StatusFooter: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Preferences.Key.notificationsPausedUntil) private var pausedUntil = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ListenerStatusLabel(state: appState.listener.state)
            if Preferences.isPaused(pausedUntil: pausedUntil) {
                PausedLabel(pausedUntil: pausedUntil)
            }
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PausedLabel: View {
    let pausedUntil: Double

    var body: some View {
        if pausedUntil >= Preferences.pausedIndefinitely {
            Label("Notifications paused", systemImage: "bell.slash.fill")
                .foregroundStyle(.orange)
        } else {
            Label {
                Text("Paused until \(Date(timeIntervalSince1970: pausedUntil), style: .time)")
            } icon: {
                Image(systemName: "bell.slash.fill")
            }
            .foregroundStyle(.orange)
        }
    }
}

struct ListenerStatusLabel: View {
    let state: ClaudeEventListener.State

    var body: some View {
        switch state {
        case .running(let port):
            Label {
                Text(verbatim: "Running on 127.0.0.1:\(port)")
            } icon: {
                Image(systemName: "circle.fill").foregroundStyle(.green)
            }
        case .starting(let port):
            Label {
                Text(verbatim: "Starting on port \(port)…")
            } icon: {
                Image(systemName: "circle.fill").foregroundStyle(.yellow)
            }
        case .stopped:
            Label {
                Text("Listener stopped")
            } icon: {
                Image(systemName: "circle.fill").foregroundStyle(.secondary)
            }
        case .failed(_, let message):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }
}
