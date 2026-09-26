import XCTest
@testable import ClaudeWatchCore

final class DeduplicationTests: XCTestCase {
    private let dedup = EventDeduplicator()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ type: ClaudeEventType, message: String?, turn: String? = "turn-1", at offset: TimeInterval = 0, supplementary: Bool = false, tool: String? = nil) -> ClaudeEvent {
        ClaudeEvent(type: type, sessionID: "s1", timestamp: t0.addingTimeInterval(offset), message: message, toolName: tool, turnID: turn, isSupplementary: supplementary)
    }

    private func prior(_ e: ClaudeEvent) -> EventDeduplicator.PriorEvent {
        .init(fingerprint: EventFingerprint.make(for: e), type: e.type, receivedAt: e.timestamp, isSupplementary: e.isSupplementary)
    }

    func testFingerprintIsDeterministic() {
        let a = event(.needsInput, message: "Which  strategy?")
        let b = event(.needsInput, message: "which strategy?", at: 10)
        XCTAssertEqual(EventFingerprint.make(for: a), EventFingerprint.make(for: b))
        XCTAssertEqual(EventFingerprint.make(for: a).count, 16)
    }

    func testDuplicateDeliveryIsDetected() {
        let first = event(.needsInput, message: "Which strategy?")
        let again = event(.needsInput, message: "Which strategy?", at: 1)
        XCTAssertTrue(dedup.isDuplicate(again, fingerprint: EventFingerprint.make(for: again), priorEvents: [prior(first)]))
    }

    func testNewQuestionInSameSessionIsNotSuppressed() {
        let first = event(.needsInput, message: "Which strategy?")
        let second = event(.needsInput, message: "Which database?", at: 5)
        XCTAssertFalse(dedup.isDuplicate(second, fingerprint: EventFingerprint.make(for: second), priorEvents: [prior(first)]))
    }

    func testSameTextInNewTurnIsNotSuppressed() {
        let first = event(.finished, message: "Done.", turn: "turn-1")
        let second = event(.finished, message: "Done.", turn: "turn-2", at: 20)
        XCTAssertFalse(dedup.isDuplicate(second, fingerprint: EventFingerprint.make(for: second), priorEvents: [prior(first)]))
    }

    func testIdenticalEventAfterWindowIsNew() {
        let first = event(.needsInput, message: "Which strategy?")
        let later = event(.needsInput, message: "Which strategy?", at: 301)
        XCTAssertFalse(dedup.isDuplicate(later, fingerprint: EventFingerprint.make(for: later), priorEvents: [prior(first)]))
    }

    func testNotificationHookDoesNotRepeatSpecificHook() {
        let specific = event(.permissionRequired, message: "Bash: rm -rf build", tool: "Bash")
        let generic = event(.permissionRequired, message: "Claude needs your permission to use Bash", turn: nil, at: 2, supplementary: true)
        XCTAssertTrue(dedup.isDuplicate(generic, fingerprint: EventFingerprint.make(for: generic), priorEvents: [prior(specific)]))
        // …in either order.
        let specificLater = event(.permissionRequired, message: "Bash: rm -rf build", at: 3, tool: "Bash")
        XCTAssertTrue(dedup.isDuplicate(specificLater, fingerprint: EventFingerprint.make(for: specificLater), priorEvents: [prior(generic)]))
    }

    func testTwoSpecificPermissionRequestsAreBothNotified() {
        let a = event(.permissionRequired, message: "Bash: make", tool: "Bash")
        let b = event(.permissionRequired, message: "Bash: make test", at: 3, tool: "Bash")
        XCTAssertFalse(dedup.isDuplicate(b, fingerprint: EventFingerprint.make(for: b), priorEvents: [prior(a)]))
    }

    func testPreToolUseAndPermissionRequestForSameQuestionAreOneEvent() throws {
        let decoder = HookPayloadDecoder()
        let normalizer = ClaudeEventNormalizer()
        var priors: [EventDeduplicator.PriorEvent] = []
        var notifications = 0
        for (offset, name) in ["pre-tool-use-ask-user-question", "permission-request-ask-user-question", "pre-tool-use-ask-user-question"].enumerated() {
            let payload = try decoder.decode(try Fixture.data("hooks/\(name)"))
            guard case .event(let e) = normalizer.normalize(payload, receivedAt: t0.addingTimeInterval(Double(offset))) else { return XCTFail() }
            let fp = EventFingerprint.make(for: e)
            if !dedup.isDuplicate(e, fingerprint: fp, priorEvents: priors) {
                notifications += 1
                priors.append(.init(fingerprint: fp, type: e.type, receivedAt: e.timestamp, isSupplementary: e.isSupplementary))
            }
        }
        XCTAssertEqual(notifications, 1)
    }
}
