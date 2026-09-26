import XCTest
@testable import ClaudeWatchCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    let handler: @Sendable (URLRequest) throws -> (Int, String)

    init(handler: @escaping @Sendable (URLRequest) throws -> (Int, String)) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let (status, body) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

final class PushoverClientTests: XCTestCase {
    private let credentials = PushoverCredentials(userKey: "uQiRzpo4DXghDmr9QzzfQu27cmVRsG", appToken: "azGDORePK8gMaC0QOYAMyEEuzJnyUi")
    private let message = PushoverMessage(title: "Claude · work · backend", message: "❓ Claude needs input\nWhich strategy?", priority: 1, playSound: false,
                                          url: URL(string: "https://claude.ai/code/session_1"))

    private func form(_ request: URLRequest) -> [String: String] {
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        var result: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? "" }
            result[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return result
    }

    func testSuccessfulSend() async throws {
        let transport = MockTransport { _ in (200, #"{"status":1,"request":"647d2300-702c-4b38-8b2f-d56326ae460b"}"#) }
        let client = PushoverClient(transport: transport)
        let id = try await client.send(message, credentials: credentials)
        XCTAssertEqual(id, "647d2300-702c-4b38-8b2f-d56326ae460b")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, PushoverClient.defaultEndpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let fields = form(request)
        XCTAssertEqual(fields["token"], credentials.appToken)
        XCTAssertEqual(fields["user"], credentials.userKey)
        XCTAssertEqual(fields["title"], "Claude · work · backend")
        XCTAssertEqual(fields["message"], "❓ Claude needs input\nWhich strategy?")
        XCTAssertEqual(fields["priority"], "1")
        XCTAssertEqual(fields["sound"], "none")
        XCTAssertEqual(fields["url"], "https://claude.ai/code/session_1")
        XCTAssertEqual(fields["url_title"], "Open session")
    }

    func testAPIErrorIsReportedWithoutSecrets() async {
        let token = credentials.appToken
        let transport = MockTransport { _ in (400, #"{"status":0,"errors":["application token is invalid: \#(token)"],"token":"invalid"}"#) }
        do {
            try await PushoverClient(transport: transport).send(message, credentials: credentials)
            XCTFail("Expected failure")
        } catch let error as PushoverError {
            XCTAssertEqual(error, .http(status: 400, messages: ["application token is invalid: •••"]))
            XCTAssertFalse(error.localizedDescription.contains(token))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testStatusZeroWith200IsAPIError() async {
        let transport = MockTransport { _ in (200, #"{"status":0,"errors":["user identifier is invalid"]}"#) }
        do {
            try await PushoverClient(transport: transport).send(message, credentials: credentials)
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? PushoverError, .api(messages: ["user identifier is invalid"]))
        }
    }

    func testServerErrorWithoutJSON() async {
        let transport = MockTransport { _ in (503, "<html>unavailable</html>") }
        do {
            try await PushoverClient(transport: transport).send(message, credentials: credentials)
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? PushoverError, .http(status: 503, messages: []))
        }
    }

    func testNetworkFailure() async {
        let transport = MockTransport { _ in throw URLError(.notConnectedToInternet) }
        do {
            try await PushoverClient(transport: transport).send(message, credentials: credentials)
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? PushoverError, .network("You appear to be offline."))
        }
    }

    func testMalformedCredentialsAreRejectedWithoutARequest() async {
        let transport = MockTransport { _ in (200, #"{"status":1}"#) }
        let client = PushoverClient(transport: transport)
        do {
            try await client.send(message, credentials: PushoverCredentials(userKey: "short", appToken: credentials.appToken))
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? PushoverError, .malformedCredentials(field: "User Key"))
        }
        do {
            try await client.send(message, credentials: PushoverCredentials(userKey: "", appToken: ""))
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? PushoverError, .missingCredentials)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testPriorityIsClamped() {
        XCTAssertEqual(PushoverMessage(title: "", message: "", priority: 2).priority, 1)
        XCTAssertEqual(PushoverMessage(title: "", message: "", priority: -5).priority, -2)
    }

    func testFormEncodingEscapesReservedCharacters() {
        XCTAssertEqual(PushoverClient.formEncode([("m", "a&b=c +ü")]), "m=a%26b%3Dc%20%2B%C3%BC")
    }
}
