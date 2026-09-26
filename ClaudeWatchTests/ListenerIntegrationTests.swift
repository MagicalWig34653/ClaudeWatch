import XCTest
@testable import ClaudeWatch
import ClaudeWatchCore

/// Real loopback HTTP round trips against `ClaudeEventListener`.
@MainActor
final class ListenerIntegrationTests: XCTestCase {
    private var listener: ClaudeEventListener!
    private var port: UInt16 = 0

    override func setUp() async throws {
        listener = ClaudeEventListener()
        port = UInt16.random(in: 40_000...49_000)
        listener.start(port: port)
        for _ in 0..<50 where !listener.isRunning {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(listener.isRunning, "listener did not start: \(listener.state)")
    }

    override func tearDown() async throws {
        listener.stop()
    }

    private func post(_ body: String, contentType: String = "application/json") async throws -> Int {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/events")!)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as! HTTPURLResponse).statusCode
    }

    func testAcceptsHookPayloadAndDeliversIt() async throws {
        let received = expectation(description: "payload delivered")
        var payload: HookPayload?
        listener.onPayload = { value in
            payload = value
            received.fulfill()
        }
        let status = try await post(#"{"hook_event_name":"Stop","session_id":"abc123","cwd":"/Users/example/Projects/backend"}"#)
        XCTAssertEqual(status, 200)
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(payload?.hookEventName, "Stop")
        XCTAssertEqual(payload?.sessionID, "abc123")
    }

    func testRejectsInvalidRequestsWithoutDeliveringThem() async throws {
        listener.onPayload = { _ in XCTFail("invalid payload must not be delivered") }
        let malformed = try await post("{not json")
        XCTAssertEqual(malformed, 400)
        let wrongType = try await post(#"{"hook_event_name":"Stop","session_id":"a"}"#, contentType: "text/plain")
        XCTAssertEqual(wrongType, 415)
        // The listener answers 413 as soon as it sees Content-Length and closes the connection;
        // depending on timing the client sees the 413 or a reset while still uploading.
        do {
            let oversized = try await post(#"{"hook_event_name":"Stop","session_id":"a","x":""# + String(repeating: "a", count: 3 * 1024 * 1024) + #""}"#)
            XCTAssertEqual(oversized, 413)
        } catch is URLError {
            // Connection closed by the listener: also a rejection.
        }
    }

    func testPortConflictIsReportedNotFatal() async throws {
        let second = ClaudeEventListener()
        second.start(port: port)
        for _ in 0..<50 {
            if case .failed = second.state { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard case .failed(_, let message) = second.state else {
            return XCTFail("expected failure, got \(second.state)")
        }
        XCTAssertTrue(message.contains("\(port)"))
        second.stop()
    }
}
