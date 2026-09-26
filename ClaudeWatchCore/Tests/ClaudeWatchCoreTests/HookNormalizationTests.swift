import XCTest
@testable import ClaudeWatchCore

final class HookNormalizationTests: XCTestCase {
    private let decoder = HookPayloadDecoder()
    private let normalizer = ClaudeEventNormalizer()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = "6f1c2b8e-4d3a-4e5f-9a7b-1c2d3e4f5a6b"

    private func event(_ fixture: String, alias: String? = nil) throws -> ClaudeEvent {
        let payload = try decoder.decode(try Fixture.data("hooks/\(fixture)"))
        guard case .event(let event) = normalizer.normalize(payload, receivedAt: now, accountAlias: alias) else {
            XCTFail("Expected \(fixture) to normalize to an event")
            throw NSError(domain: "test", code: 0)
        }
        return event
    }

    func testStopBecomesFinishedWithLastMessage() throws {
        let e = try event("stop", alias: "work")
        XCTAssertEqual(e.type, .finished)
        XCTAssertEqual(e.sessionID, sessionID)
        XCTAssertEqual(e.projectName, "backend-api")
        XCTAssertEqual(e.workingDirectory, "/Users/example/Projects/backend-api")
        XCTAssertEqual(e.accountAlias, "work")
        XCTAssertEqual(e.source, .local)
        XCTAssertEqual(e.message, "Added the migration and updated the tests. All 42 tests pass.")
        XCTAssertNotNil(e.turnID)
        XCTAssertFalse(e.isSupplementary)
    }

    func testAskUserQuestionToolEventBecomesNeedsInput() throws {
        let e = try event("pre-tool-use-ask-user-question")
        XCTAssertEqual(e.type, .needsInput)
        XCTAssertEqual(e.toolName, "AskUserQuestion")
        XCTAssertEqual(e.message, "Which migration strategy should be used?")
    }

    func testAskUserQuestionPermissionRequestBecomesNeedsInputWithSameFingerprint() throws {
        let pre = try event("pre-tool-use-ask-user-question")
        let permission = try event("permission-request-ask-user-question")
        XCTAssertEqual(permission.type, .needsInput)
        XCTAssertEqual(EventFingerprint.make(for: pre), EventFingerprint.make(for: permission))
    }

    func testPermissionRequestBecomesPermissionRequired() throws {
        let e = try event("permission-request-bash")
        XCTAssertEqual(e.type, .permissionRequired)
        XCTAssertEqual(e.toolName, "Bash")
        XCTAssertEqual(e.message, "Bash: ls /Users/example/Projects")
    }

    func testExitPlanModeBecomesPlanApproval() throws {
        for fixture in ["pre-tool-use-exit-plan-mode", "permission-request-exit-plan-mode"] {
            let e = try event(fixture)
            XCTAssertEqual(e.type, .planApprovalRequired, fixture)
            XCTAssertEqual(e.message, "## Plan: add orders migration", fixture)
        }
    }

    func testNotificationHookEventsAreSupplementary() throws {
        let permission = try event("notification-permission-prompt")
        XCTAssertEqual(permission.type, .permissionRequired)
        XCTAssertTrue(permission.isSupplementary)

        let idle = try event("notification-idle-prompt")
        XCTAssertEqual(idle.type, .idle)
        XCTAssertTrue(idle.isSupplementary)
    }

    func testStopFailureBecomesFailed() throws {
        let e = try event("stop-failure")
        XCTAssertEqual(e.type, .failed)
        XCTAssertEqual(e.message, "Rate limit reached — 5-hour limit reached")
    }

    func testActivityAndLifecycleEvents() throws {
        XCTAssertEqual(try event("session-start").type, .sessionStarted)
        XCTAssertEqual(try event("user-prompt-submit").type, .activity)
        XCTAssertEqual(try event("pre-tool-use-bash").type, .activity)
        XCTAssertEqual(try event("post-tool-use-failure-bash").type, .activity)
        XCTAssertEqual(try event("session-end").type, .sessionEnded)
    }

    func testUserPromptTextIsNotCarriedIntoEvents() throws {
        let e = try event("user-prompt-submit")
        XCTAssertNil(e.message)
    }

    func testMalformedPayloadIsRejected() throws {
        XCTAssertThrowsError(try decoder.decode(try Fixture.data("hooks/malformed"))) { error in
            XCTAssertEqual(error as? HookPayloadDecodingError, .malformedJSON)
        }
        XCTAssertThrowsError(try decoder.decode(Data("[1,2]".utf8))) { error in
            XCTAssertEqual(error as? HookPayloadDecodingError, .malformedJSON)
        }
    }

    func testMissingSessionIDIsRejected() throws {
        XCTAssertThrowsError(try decoder.decode(try Fixture.data("hooks/missing-session-id"))) { error in
            XCTAssertEqual(error as? HookPayloadDecodingError, .missingRequiredField("session_id"))
        }
    }

    func testUnsafeSessionIDIsRejected() {
        let body = Data(#"{"hook_event_name":"Stop","session_id":"../../etc/passwd"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(body)) { error in
            XCTAssertEqual(error as? HookPayloadDecodingError, .invalidSessionID)
        }
    }

    func testUnknownEventIsIgnoredNotFatal() throws {
        let payload = try decoder.decode(try Fixture.data("hooks/unknown-event"))
        guard case .ignored = normalizer.normalize(payload, receivedAt: now) else {
            return XCTFail("Unknown events must be ignored")
        }
    }

    func testUnknownFieldsAndWrongTypesAreTolerated() throws {
        let body = Data(#"{"hook_event_name":"Stop","session_id":"abc123","cwd":42,"brand_new_field":{"x":[1,2]},"last_assistant_message":"done"}"#.utf8)
        let payload = try decoder.decode(body)
        XCTAssertNil(payload.cwd)
        guard case .event(let e) = normalizer.normalize(payload, receivedAt: now) else { return XCTFail() }
        XCTAssertEqual(e.type, .finished)
        XCTAssertNil(e.projectName)
    }

    func testMessagesAreSanitized() throws {
        let body = Data(#"{"hook_event_name":"Stop","session_id":"abc","last_assistant_message":"line one\u0007\n\n\n  line‮ two  "}"#.utf8)
        guard case .event(let e) = normalizer.normalize(try decoder.decode(body), receivedAt: now) else { return XCTFail() }
        XCTAssertEqual(e.message, "line one\nline two")
    }

    func testProjectName() {
        XCTAssertEqual(ClaudeEventNormalizer.projectName(forDirectory: "/Users/a/Projects/web/"), "web")
        XCTAssertEqual(ClaudeEventNormalizer.projectName(forDirectory: "/"), "/")
    }
}
