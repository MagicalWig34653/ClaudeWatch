import SwiftUI
import SwiftData
import ClaudeWatchCore

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    let session: ClaudeSession
    @Query private var events: [ClaudeEventRecord]
    @State private var confirmDelete = false

    init(session: ClaudeSession) {
        self.session = session
        let id = session.id
        _events = Query(
            filter: #Predicate<ClaudeEventRecord> { $0.sessionID == id },
            sort: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
    }

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
                    Text(verbatim: session.workingDirectory ?? "—").textSelection(.enabled).lineLimit(2)
                }
                LabeledContent("Session ID") {
                    Text(verbatim: session.id).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                if let remoteID = session.remoteSessionID {
                    LabeledContent("Remote Session ID") { Text(verbatim: remoteID).textSelection(.enabled) }
                }
                LabeledContent("Started") { Text(session.startedAt, format: .dateTime) }
                LabeledContent("Last Update") { Text(session.updatedAt, format: .dateTime) }
                if let finishedAt = session.finishedAt {
                    LabeledContent("Finished") { Text(finishedAt, format: .dateTime) }
                }
            }

            Section("Event History") {
                if events.isEmpty {
                    Text("No recorded events.").foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        EventRow(event: event)
                    }
                }
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
