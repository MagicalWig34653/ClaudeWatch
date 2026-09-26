import XCTest
@testable import ClaudeWatch
import ClaudeWatchCore

private struct RecordingTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(#"{"status":1,"request":"r"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
final class PushoverServiceTests: XCTestCase {
    private let user = "uQiRzpo4DXghDmr9QzzfQu27cmVRsG"
    private let token = "azGDORePK8gMaC0QOYAMyEEuzJnyUi"

    func testCredentialsGoToSecretStoreOnly() throws {
        let store = InMemorySecretStore()
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        let service = PushoverService(secrets: store, client: PushoverClient(transport: RecordingTransport()))
        XCTAssertFalse(service.hasStoredCredentials)

        try service.saveCredentials(userKey: user, appToken: token)
        XCTAssertTrue(service.hasStoredCredentials)
        XCTAssertEqual(store.values[KeychainService.Account.pushoverUserKey], user)
        XCTAssertEqual(store.values[KeychainService.Account.pushoverAppToken], token)

        let after = UserDefaults.standard.dictionaryRepresentation()
        for (key, value) in after where defaults[key] == nil {
            XCTAssertFalse("\(value)".contains(token), "secret leaked into UserDefaults key \(key)")
        }
    }

    func testMalformedCredentialsAreRejected() {
        let service = PushoverService(secrets: InMemorySecretStore(), client: PushoverClient(transport: RecordingTransport()))
        XCTAssertThrowsError(try service.saveCredentials(userKey: "abc", appToken: token))
        XCTAssertFalse(service.hasStoredCredentials)
    }

    func testTestNotificationReportsDelivery() async throws {
        let service = PushoverService(secrets: InMemorySecretStore(), client: PushoverClient(transport: RecordingTransport()))
        await service.sendTestNotification()
        guard case .failed = service.testStatus else { return XCTFail("missing credentials must fail") }

        try service.saveCredentials(userKey: user, appToken: token)
        await service.sendTestNotification()
        guard case .delivered = service.testStatus else { return XCTFail("expected delivery, got \(service.testStatus)") }

        try service.removeCredentials()
        XCTAssertFalse(service.hasStoredCredentials)
    }
}
