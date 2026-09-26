import XCTest
@testable import ClaudeWatchCore

final class ListenerParsingTests: XCTestCase {
    private let parser = HTTPRequestParser(maxHeaderBytes: 1024, maxBodyBytes: 4096)
    private let router = HookRequestRouter()

    private func raw(_ method: String = "POST", path: String = "/v1/events", headers: [String: String] = ["Content-Type": "application/json"], body: String) -> Data {
        var text = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1:17831\r\n"
        var headers = headers
        if headers["Content-Length"] == nil { headers["Content-Length"] = String(body.utf8.count) }
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) { text += "\(k): \(v)\r\n" }
        return Data((text + "\r\n" + body).utf8)
    }

    private func request(_ data: Data) throws -> HTTPRequest {
        guard case .complete(let request) = parser.parse(data) else {
            XCTFail("Expected a complete request")
            throw NSError(domain: "test", code: 0)
        }
        return request
    }

    func testParsesCompleteRequest() throws {
        let body = #"{"hook_event_name":"Stop","session_id":"abc123","cwd":"/Users/example/Projects/backend"}"#
        let r = try request(raw(body: body))
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/v1/events")
        XCTAssertEqual(r.headers["content-type"], "application/json")
        XCTAssertEqual(String(decoding: r.body, as: UTF8.self), body)
    }

    func testIncompleteUntilBodyArrives() {
        let data = raw(body: #"{"hook_event_name":"Stop","session_id":"abc"}"#)
        XCTAssertEqual(parser.parse(data.prefix(20)), .incomplete)
        XCTAssertEqual(parser.parse(data.dropLast(3)), .incomplete)
    }

    func testRejectsOversizedBody() {
        let data = raw(headers: ["Content-Type": "application/json", "Content-Length": "999999"], body: "")
        guard case .failure(let response) = parser.parse(data) else { return XCTFail() }
        XCTAssertEqual(response.status, 413)
    }

    func testRejectsOversizedHeaders() {
        let data = Data(("POST /v1/events HTTP/1.1\r\nX: " + String(repeating: "a", count: 2000)).utf8)
        guard case .failure(let response) = parser.parse(data) else { return XCTFail() }
        XCTAssertEqual(response.status, 431)
    }

    func testRejectsChunkedBodies() {
        let data = raw(headers: ["Content-Type": "application/json", "Transfer-Encoding": "chunked", "Content-Length": "0"], body: "")
        guard case .failure(let response) = parser.parse(data) else { return XCTFail() }
        XCTAssertEqual(response.status, 411)
    }

    func testRoutesValidHookPayload() throws {
        let r = try request(raw(body: #"{"hook_event_name":"Stop","session_id":"abc123"}"#))
        guard case .respond(let response, let payload) = router.route(r) else { return XCTFail() }
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "{}")
        XCTAssertEqual(payload?.hookEventName, "Stop")
    }

    func testRejectsNonJSON() throws {
        let r = try request(raw(headers: ["Content-Type": "text/plain"], body: #"{"hook_event_name":"Stop","session_id":"a"}"#))
        guard case .respond(let response, let payload) = router.route(r) else { return XCTFail() }
        XCTAssertEqual(response.status, 415)
        XCTAssertNil(payload)
    }

    func testRejectsMalformedJSON() throws {
        let r = try request(raw(body: "{nope"))
        guard case .respond(let response, let payload) = router.route(r) else { return XCTFail() }
        XCTAssertEqual(response.status, 400)
        XCTAssertNil(payload)
    }

    func testRejectsBrowserOrigin() throws {
        let r = try request(raw(headers: ["Content-Type": "application/json", "Origin": "https://evil.example"], body: #"{"hook_event_name":"Stop","session_id":"a"}"#))
        guard case .respond(let response, let payload) = router.route(r) else { return XCTFail() }
        XCTAssertEqual(response.status, 403)
        XCTAssertNil(payload)
    }

    func testUnknownPathAndMethod() throws {
        guard case .respond(let notFound, _) = router.route(try request(raw(path: "/admin", body: "{}"))) else { return XCTFail() }
        XCTAssertEqual(notFound.status, 404)
        guard case .respond(let wrongMethod, _) = router.route(try request(raw("GET", path: "/v1/events", body: ""))) else { return XCTFail() }
        XCTAssertEqual(wrongMethod.status, 405)
        guard case .respond(let health, _) = router.route(try request(raw("GET", path: "/v1/health", headers: [:], body: ""))) else { return XCTFail() }
        XCTAssertEqual(health.status, 200)
    }

    func testResponseSerialization() {
        let text = String(decoding: HTTPResponse.error(400, "bad \"x\"").serialized(), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 21\r\n"))
        XCTAssertTrue(text.hasSuffix(#"{"error":"bad \"x\""}"#))
    }
}
