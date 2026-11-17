import SwiftUI
import SwiftData
import ClaudeWatchCore

struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @Query(SessionQueries.overviewAttention) private var attention: [ClaudeSession]
    @Query(SessionQueries.overviewRecent) private var recentlyFinished: [ClaudeSession]
    @Query(OverviewView.recentEventsDescriptor) private var recentEvents: [ClaudeEventRecord]

    static var recentEventsDescriptor: FetchDescriptor<ClaudeEventRecord> {
        var descriptor = FetchDescriptor<ClaudeEventRecord>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        descriptor.fetchLimit = 12
        return descriptor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = appState.storeError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                if case .failed(_, let message) = appState.listener.state {
                    Label {
                        Text(verbatim: message + " Change the port in Settings.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.red)
                }

                HStack(spacing: 32) {
                    Metric(value: appState.activeCount, title: "Active")
                    Metric(value: appState.attentionCount, title: "Needs Attention", highlight: !attention.isEmpty)
                    Metric(value: appState.finishedTodayCount, title: "Finished Today")
                }

                if appState.sessionCount == 0 {
                    ContentUnavailableView {
                        Label("No Sessions Yet", systemImage: "terminal")
                    } description: {
                        Text("Connect Claude Code hooks to ClaudeWatch (see Settings), or send a test event.")
                    } actions: {
                        Button("Send Test Event") { Task { await appState.sendTestEvent() } }
                    }
                    .frame(maxWidth: .infinity)
                }

                if !attention.isEmpty {
                    Section {
                        ForEach(attention) { session in
                            AttentionCard(session: session)
                        }
                    } header: {
                        SectionHeader("Needs Attention")
                    }
                }

                if !recentlyFinished.isEmpty {
                    Section {
                        ForEach(Array(recentlyFinished)) { session in
                            Button { open(session) } label: { SessionRow(session: session) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        SectionHeader("Recently Finished")
                    }
                }

                if !recentEvents.isEmpty {
                    Section {
                        ForEach(recentEvents) { event in
                            EventRow(event: event, showProject: true)
                        }
                    } header: {
                        SectionHeader("Recent Events")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Overview")
    }

    private func open(_ session: ClaudeSession) {
        appState.sessionFilter = .all
        appState.selectedSessionID = session.id
        appState.selectedSection = .sessions
    }
}

private struct Metric: View {
    let value: Int
    let title: String
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(highlight ? Color.orange : Color.primary)
                .monospacedDigit()
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

private struct AttentionCard: View {
    @Environment(AppState.self) private var appState
    let session: ClaudeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.projectName).font(.title3.weight(.semibold))
                    Text(verbatim: session.displayAccount).foregroundStyle(.secondary)
                }
                Spacer()
                StatusLabel(status: session.status)
            }
            if let message = session.lastMessage {
                Text(verbatim: "“\(message)”")
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Open Session") {
                    appState.sessionFilter = .all
                    appState.selectedSessionID = session.id
                    appState.selectedSection = .sessions
                }
                if let url = session.remoteURL {
                    Link("Open in Claude", destination: url)
                }
                Spacer()
                Text(session.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.25)))
    }
}

struct EventRow: View {
    let event: ClaudeEventRecord
    var showProject = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: event.eventType?.symbol ?? "questionmark.circle")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.displayName).fontWeight(.medium)
                    if showProject, let project = event.projectName {
                        Text(verbatim: project).foregroundStyle(.secondary)
                    }
                    if event.isDuplicate {
                        Text("Duplicate").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(event.receivedAt, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let message = event.message {
                    Text(verbatim: message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                DeliveryBadges(event: event)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DeliveryBadges: View {
    let event: ClaudeEventRecord

    var body: some View {
        let showNative = event.wasNativeNotificationSent || event.nativeNotificationError != nil
        let showPushover = event.wasPushoverSent || event.pushoverError != nil
        if showNative || showPushover {
            HStack(spacing: 10) {
                if showNative {
                    badge("macOS", sent: event.wasNativeNotificationSent, error: event.nativeNotificationError)
                }
                if showPushover {
                    badge("Pushover", sent: event.wasPushoverSent, error: event.pushoverError)
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func badge(_ title: String, sent: Bool, error: String?) -> some View {
        if sent {
            Label(title, systemImage: "checkmark").foregroundStyle(.green)
        } else {
            Label(title, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .help(error ?? "Not delivered")
        }
    }
}
