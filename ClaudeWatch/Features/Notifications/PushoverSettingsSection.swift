import SwiftUI
import ClaudeWatchCore

struct PushoverSettingsSection: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Preferences.Key.pushoverEnabled) private var pushoverEnabled = false
    @State private var userKey = ""
    @State private var appToken = ""
    @State private var saveError: String?

    private var pushover: PushoverService { appState.pushover }

    var body: some View {
        Section {
            SecureField("User Key", text: $userKey, prompt: Text(pushover.hasStoredCredentials ? "Saved in Keychain" : "30-character user key"))
            SecureField("Application Token", text: $appToken, prompt: Text(pushover.hasStoredCredentials ? "Saved in Keychain" : "30-character API token"))
            HStack {
                Button("Save") { save() }
                    .disabled(userKey.isEmpty && appToken.isEmpty)
                Button("Send Test Notification") {
                    Task { await pushover.sendTestNotification() }
                }
                .disabled(!pushover.hasStoredCredentials || pushover.testStatus == .sending)
                Spacer()
                if pushover.hasStoredCredentials {
                    Button("Remove Credentials", role: .destructive) { remove() }
                }
            }
            status
        } header: {
            Text("Pushover")
        } footer: {
            Text("Credentials are stored only in your macOS Keychain. Create an application at pushover.net to get a token.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let saveError {
            Label(saveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        } else if let error = pushover.credentialError {
            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        switch pushover.testStatus {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Sending…")
            }
        case .delivered:
            Label("Test notification delivered", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "xmark.octagon.fill")
            }
            .foregroundStyle(.red)
        }
    }

    private func save() {
        let hadCredentials = pushover.hasStoredCredentials
        do {
            try pushover.saveCredentials(userKey: userKey, appToken: appToken)
            userKey = ""
            appToken = ""
            saveError = nil
            if !hadCredentials && pushover.hasStoredCredentials { pushoverEnabled = true }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try pushover.removeCredentials()
            pushoverEnabled = false
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
