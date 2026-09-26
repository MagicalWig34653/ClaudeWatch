import Foundation
import Observation
import ClaudeWatchCore

/// Sends notifications through `PushoverClient`, loading credentials from the Keychain
/// only at the moment they are needed.
@MainActor
protocol PushoverSending {
    func send(_ content: NotificationContent, priority: Int, playSound: Bool) async throws
}

@MainActor
@Observable
final class PushoverService: PushoverSending {
    enum TestStatus: Equatable {
        case idle
        case sending
        case delivered(Date)
        case failed(String)
    }

    private(set) var hasStoredCredentials = false
    private(set) var testStatus: TestStatus = .idle
    private(set) var credentialError: String?

    @ObservationIgnored private let secrets: SecretStore
    @ObservationIgnored private let client: PushoverClient

    init(secrets: SecretStore = KeychainService(), client: PushoverClient = PushoverClient()) {
        self.secrets = secrets
        self.client = client
        refreshCredentialState()
    }

    func refreshCredentialState() {
        do {
            let user = try secrets.read(KeychainService.Account.pushoverUserKey)
            let token = try secrets.read(KeychainService.Account.pushoverAppToken)
            hasStoredCredentials = !(user ?? "").isEmpty && !(token ?? "").isEmpty
            credentialError = nil
        } catch {
            hasStoredCredentials = false
            credentialError = error.localizedDescription
        }
    }

    /// Validates and stores credentials. Empty fields keep the stored value.
    func saveCredentials(userKey: String, appToken: String) throws {
        let user = userKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty, !PushoverCredentials.isWellFormed(user) {
            throw PushoverError.malformedCredentials(field: "User Key")
        }
        if !token.isEmpty, !PushoverCredentials.isWellFormed(token) {
            throw PushoverError.malformedCredentials(field: "Application Token")
        }
        if !user.isEmpty { try secrets.write(user, account: KeychainService.Account.pushoverUserKey) }
        if !token.isEmpty { try secrets.write(token, account: KeychainService.Account.pushoverAppToken) }
        Log.pushover.info("Pushover credentials updated")
        testStatus = .idle
        refreshCredentialState()
    }

    func removeCredentials() throws {
        try secrets.delete(KeychainService.Account.pushoverUserKey)
        try secrets.delete(KeychainService.Account.pushoverAppToken)
        Log.pushover.info("Pushover credentials removed")
        testStatus = .idle
        refreshCredentialState()
    }

    func send(_ content: NotificationContent, priority: Int, playSound: Bool) async throws {
        let message = PushoverMessage(
            title: content.pushoverTitle,
            message: content.pushoverMessage,
            priority: priority,
            playSound: playSound,
            url: content.url,
            urlTitle: content.url == nil ? nil : "Open Claude session"
        )
        try await send(message)
    }

    func sendTestNotification() async {
        testStatus = .sending
        do {
            try await send(PushoverMessage(title: "Claude · ClaudeWatch", message: "✅ Test notification from ClaudeWatch"))
            testStatus = .delivered(Date())
        } catch {
            testStatus = .failed(error.localizedDescription)
        }
    }

    private func send(_ message: PushoverMessage) async throws {
        let credentials = try loadCredentials()
        do {
            try await client.send(message, credentials: credentials)
            Log.pushover.info("Pushover message accepted")
        } catch {
            Log.pushover.error("Pushover delivery failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func loadCredentials() throws -> PushoverCredentials {
        guard let user = try secrets.read(KeychainService.Account.pushoverUserKey),
              let token = try secrets.read(KeychainService.Account.pushoverAppToken) else {
            throw PushoverError.missingCredentials
        }
        return PushoverCredentials(userKey: user, appToken: token)
    }
}
