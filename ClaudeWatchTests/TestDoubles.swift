import Foundation
@testable import ClaudeWatch
import ClaudeWatchCore

@MainActor
final class FakeNativeNotifier: NativeNotifying {
    var delivered: [NotificationContent] = []
    var error: Error?

    func deliver(_ content: NotificationContent, playSound: Bool) async throws {
        if let error { throw error }
        delivered.append(content)
    }
}

@MainActor
final class FakePushover: PushoverSending {
    var sent: [(content: NotificationContent, priority: Int)] = []
    var error: Error?

    func send(_ content: NotificationContent, priority: Int, playSound: Bool) async throws {
        if let error { throw error }
        sent.append((content, priority))
    }
}

final class InMemorySecretStore: SecretStore {
    var values: [String: String] = [:]
    func read(_ account: String) throws -> String? { values[account] }
    func write(_ value: String, account: String) throws { values[account] = value }
    func delete(_ account: String) throws { values[account] = nil }
}
