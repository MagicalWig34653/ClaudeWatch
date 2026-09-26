import SwiftUI
import SwiftData
import ClaudeWatchCore

struct AccountsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClaudeAccount.alias) private var accounts: [ClaudeAccount]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            if accounts.isEmpty {
                ContentUnavailableView {
                    Label("No Accounts", systemImage: "person.2")
                } description: {
                    Text("Accounts are discovered through cswap and from incoming events. Events without an identifiable account are shown as “\(AccountResolver.unknownAccountName)”.")
                }
            } else {
                Table(accounts) {
                    TableColumn("Alias") { account in
                        Text(verbatim: account.alias)
                    }
                    TableColumn("Account") { account in
                        Text(verbatim: account.displayName ?? "—").foregroundStyle(.secondary)
                    }
                    TableColumn("cswap") { account in
                        if let number = account.providerNumber, account.isKnownToProvider {
                            Text(verbatim: "Slot \(number)")
                        } else {
                            Text("Not in cswap").foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("Notifications") { account in
                        Toggle("Notifications", isOn: Binding(
                            get: { account.notificationsEnabled },
                            set: { newValue in
                                account.notificationsEnabled = newValue
                                try? modelContext.save()
                            }
                        ))
                        .labelsHidden()
                    }
                    .width(min: 90, ideal: 100)
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await appState.accounts.refresh() }
                } label: {
                    Label("Refresh Accounts", systemImage: "arrow.clockwise")
                }
                .disabled(appState.accounts.state == .refreshing)
                .help("Refresh Accounts")
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        switch appState.accounts.state {
        case .idle:
            Text("Accounts have not been refreshed yet.").foregroundStyle(.secondary)
        case .refreshing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading accounts from cswap…")
            }
        case .loaded(let date):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Loaded from cswap")
                if let path = appState.accounts.executablePath {
                    Text(verbatim: "(\(path))").foregroundStyle(.secondary)
                }
                Text("·")
                Text(date, style: .relative).foregroundStyle(.secondary)
                Text("ago").foregroundStyle(.secondary)
            }
        case .cswapMissing:
            VStack(alignment: .leading, spacing: 4) {
                Label("cswap was not found", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)
                Text("ClaudeWatch works without cswap; sessions are then attributed to “\(AccountResolver.unknownAccountName)”. Install claude-swap (for example `uv tool install claude-swap`) or set its path in Settings, then refresh.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }
}
