import XCTest
@testable import ClaudeWatchCore

final class NotificationSummaryTests: XCTestCase {
    private func item(_ type: ClaudeEventType, _ project: String, session: String? = nil, account: String? = "work", priority: Int = 0) -> NotificationBatchItem {
        var rule = NotificationRuleSnapshot.defaultRule(for: type)
        rule.pushoverPriority = priority
        return NotificationBatchItem(
            event: ClaudeEvent(type: type, sessionID: session ?? project, timestamp: Date(), projectName: project, accountAlias: account, message: "done"),
            rule: rule
        )
    }

    func testSingleItemMatchesIndividualNotification() {
        let one = item(.finished, "docs")
        XCTAssertEqual(NotificationSummaryBuilder.build([one]), NotificationContentBuilder.build(event: one.event, rule: one.rule))
    }

    func testSameTypeGroup() {
        let items = (1...10).map { item(.finished, "project-\($0)") }
        let content = NotificationSummaryBuilder.build(items)
        XCTAssertEqual(content.nativeTitle, "Claude · 10 sessions")
        XCTAssertEqual(content.nativeSubtitle, "10 sessions finished")
        XCTAssertEqual(content.pushoverTitle, "Claude · work · 10 sessions")
        XCTAssertEqual(content.pushoverMessage, """
        ✅ 10 sessions finished
        ✅ project-1
        ✅ project-2
        ✅ project-3
        ✅ project-4
        ✅ project-5
        ✅ project-6
        +4 more
        """)
        XCTAssertEqual(content.sessionID, "")
        XCTAssertNil(content.url)
    }

    func testMixedGroupListsAttentionFirst() {
        let items = [item(.finished, "docs"), item(.needsInput, "backend-api", account: "personal"), item(.failed, "pipeline")]
        let content = NotificationSummaryBuilder.build(items)
        XCTAssertEqual(content.nativeSubtitle, "3 session updates")
        XCTAssertEqual(content.pushoverTitle, "Claude · 3 sessions", "mixed accounts are not named")
        XCTAssertEqual(content.nativeBody, """
        ❓ backend-api — needs input
        ❌ pipeline — failed
        ✅ docs — finished
        """)
        XCTAssertTrue(content.pushoverMessage.hasPrefix("🔔 3 session updates\n"))
    }

    func testSameSessionTwiceCountsOneSession() {
        let items = [item(.needsInput, "api", session: "s1"), item(.finished, "api", session: "s1")]
        let content = NotificationSummaryBuilder.build(items)
        XCTAssertEqual(content.nativeTitle, "Claude · 1 session")
        XCTAssertEqual(content.sessionID, "s1")
    }

    func testProjectNamesRespectRules() {
        var hidden = item(.finished, "secret-project")
        hidden = NotificationBatchItem(event: hidden.event, rule: {
            var rule = hidden.rule
            rule.includeProjectName = false
            return rule
        }())
        let content = NotificationSummaryBuilder.build([hidden, item(.finished, "docs")])
        XCTAssertFalse(content.pushoverMessage.contains("secret-project"))
        XCTAssertTrue(content.pushoverMessage.contains("✅ Session"))
    }

    func testPriorityIsHighestInGroup() {
        let items = [item(.finished, "a", priority: 0), item(.needsInput, "b", priority: 1), item(.sessionStarted, "c", priority: -1)]
        XCTAssertEqual(NotificationSummaryBuilder.pushoverPriority(items), 1)
    }
}
