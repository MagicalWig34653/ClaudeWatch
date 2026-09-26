import AppKit
import SwiftUI
import SwiftData
import ClaudeWatchCore

struct SessionsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \ClaudeSession.updatedAt, order: .reverse) private var sessions: [ClaudeSession]
    @State private var searchText = ""
    @State private var sessionPendingDeletion: ClaudeSession?

    private var filtered: [ClaudeSession] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return sessions.filter { session in
            guard appState.sessionFilter.matches(session) else { return false }
            guard !query.isEmpty else { return true }
            return [session.projectName, session.accountAlias, session.lastMessage, session.id, session.workingDirectory]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        @Bindable var appState = appState
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Segmented when it fits the column; a pop-up menu otherwise, so wider
                // control metrics on newer macOS versions never overflow into the detail pane.
                ViewThatFits(in: .horizontal) {
                    filterPicker.pickerStyle(.segmented)
                    filterPicker.pickerStyle(.menu).fixedSize()
                }
                .frame(maxWidth: .infinity)
                .padding(8)

                List(selection: $appState.selectedSessionID) {
                    ForEach(filtered) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .contextMenu { contextMenu(for: session) }
                    }
                }
                .overlay {
                    if filtered.isEmpty {
                        emptyState
                    }
                }
            }
            .frame(width: 320)

            Divider()

            Group {
                if let id = appState.selectedSessionID, let session = sessions.first(where: { $0.id == id }) {
                    SessionDetailView(session: session)
                        .id(session.id)
                } else {
                    ContentUnavailableView("No Session Selected", systemImage: "sidebar.left", description: Text("Select a session to see its details and event history."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search sessions")
        .navigationTitle("Sessions")
        .onDeleteCommand {
            if let id = appState.selectedSessionID, let session = sessions.first(where: { $0.id == id }), !session.isActive {
                sessionPendingDeletion = session
            }
        }
        .confirmationDialog(
            "Delete this session and its event history?",
            isPresented: Binding(get: { sessionPendingDeletion != nil }, set: { if !$0 { sessionPendingDeletion = nil } }),
            presenting: sessionPendingDeletion
        ) { session in
            Button("Delete", role: .destructive) { appState.deleteSession(session) }
        } message: { session in
            Text(verbatim: "\(session.projectName) · \(session.displayAccount)")
        }
    }

    private var filterPicker: some View {
        @Bindable var appState = appState
        return Picker("Filter", selection: $appState.sessionFilter) {
            ForEach(SessionFilter.allCases) { filter in
                Text(filter.segmentTitle)
                    .help(filter.title)
                    .tag(filter)
            }
        }
        .labelsHidden()
    }

    @ViewBuilder
    private func contextMenu(for session: ClaudeSession) -> some View {
        if let url = session.remoteURL {
            Link("Open in Claude", destination: url)
        }
        Button("Copy Session ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.id, forType: .string)
        }
        Divider()
        if session.isActive {
            Button("Mark as Finished") { appState.markFinished(session) }
        } else {
            Button("Delete…", role: .destructive) { sessionPendingDeletion = session }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if sessions.isEmpty {
            ContentUnavailableView("No Sessions", systemImage: "terminal", description: Text("Sessions appear here when Claude Code hooks report events."))
        } else {
            ContentUnavailableView("Nothing \(appState.sessionFilter.title)", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try a different filter."))
        }
    }
}
