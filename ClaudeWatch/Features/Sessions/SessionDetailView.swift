import SwiftUI
import SwiftData
import ClaudeWatchCore

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    let session: ClaudeSession
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: session.projectName).font(.title2.weight(.semibold))
                        StatusLabel(status: session.status)
                    }
                    Spacer()
                    if let url = session.remoteURL {
                        Link(destination: url) { Label("Open in Claude", systemImage: "arrow.up.forward.app") }
                    }
                }
                if let message = session.lastMessage {
                    Text(verbatim: message)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section("Details") {
                LabeledContent("Account") { Text(verbatim: session.displayAccount) }
                LabeledContent("Source") { Text(session.source.displayName) }
                LabeledContent("Working Directory") {
                    Text(verbatim: session.workingDirectory ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(session.workingDirectory ?? "")
                }
                LabeledContent("Session ID") {
                    Text(verbatim: session.id)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let remoteID = session.remoteSessionID {
                    LabeledContent("Remote Session ID") {
                        Text(verbatim: remoteID).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                }
                LabeledContent("Started") { Text(session.startedAt, format: .dateTime) }
                LabeledContent("Last Update") { Text(session.updatedAt, format: .dateTime) }
                if let finishedAt = session.finishedAt {
                    LabeledContent("Finished") { Text(finishedAt, format: .dateTime) }
                }
            }

            Section("Event History") {
                EventHistoryView(sessionID: session.id)
            }

            Section {
                HStack {
                    if session.isActive {
                        Button("Mark as Finished") { appState.markFinished(session) }
                            .help("Use this if the Claude Code session ended without reporting it.")
                    } else {
                        Button("Delete Session…", role: .destructive) { confirmDelete = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete this session and its event history?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { appState.deleteSession(session) }
        }
    }
}

private struct EventHistoryView: View {
    let sessionID: String
    @State private var page = 0

    var body: some View {
        EventHistoryPage(sessionID: sessionID, page: $page)
            .id(page)
    }
}

/// Only the visible page participates in Observation; older pages stay in SwiftData.
private struct EventHistoryPage: View {
    @Environment(\.modelContext) private var context
    @Query private var events: [ClaudeEventRecord]
    @Binding var page: Int
    let sessionID: String

    init(sessionID: String, page: Binding<Int>) {
        self.sessionID = sessionID
        _page = page
        _events = Query(EventHistoryQuery.page(sessionID: sessionID, index: page.wrappedValue))
    }

    var body: some View {
        // Count in the store instead of materializing the complete event history.
        let total = (try? context.fetchCount(EventHistoryQuery.records(sessionID: sessionID))) ?? 0
        if events.isEmpty {
            Text("No recorded events.").foregroundStyle(.secondary)
        } else {
            ForEach(events) { event in
                EventRow(event: event)
            }
        }
        if page > 0 || total > EventHistoryQuery.pageSize {
            HStack {
                Button("Newer Events") { page -= 1 }
                    .disabled(page == 0)
                Spacer()
                Text("Page \(page + 1)").foregroundStyle(.secondary)
                Spacer()
                Button("Older Events") { page += 1 }
                    .disabled((page + 1) * EventHistoryQuery.pageSize >= total)
            }
        }
    }
}
