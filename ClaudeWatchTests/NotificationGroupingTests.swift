import XCTest
import SwiftData
@testable import ClaudeWatch
import ClaudeWatchCore

/// Notifications arriving within the grouping window are combined per channel.
@MainActor
final class NotificationGroupingTests: XCTestCase {
    /// Held for the whole test: a ModelContext does not keep its container alive.
    private var container: ModelContainer!
    private var context: ModelContext!
    private var native: FakeNativeNotifier!
    private var pushover: FakePushover!
    private var preferences = NotificationPreferences(nativeNotificationsEnabled: true, pushoverEnabled: true, soundEnabled: true, isPaused: false)
    private var window: TimeInterval = 60
    private var processor: ClaudeEventProcessor!

    override func setUp() async throws {
        container = DataStore.makeInMemory()
        context = container.mainContext
        DataStore.seedNotificationRules(in: context)
        native = FakeNativeNotifier()
        pushover = FakePushover()
        processor = ClaudeEventProcessor(
            context: context,
            native: native,
            pushover: pushover,
            preferences: { [unowned self] in self.preferences },
            groupingWindow: { [unowned self] in self.window }
        )
    }

    private func event(_ type: ClaudeEventType, _ project: String, message: String? = nil) -> ClaudeEvent {
        ClaudeEvent(type: type, sessionID: "session-\(project)", timestamp: Date(), workingDirectory: "/Users/example/\(project)",
                    projectName: project, accountAlias: "work", message: message, turnID: UUID().uuidString)
    }

    private func records() throws -> [ClaudeEventRecord] {
        try context.fetch(FetchDescriptor<ClaudeEventRecord>())
    }

    func testTenFinishedSessionsProduceOneNotificationPerChannel() async throws {
        for index in 1...10 {
            await processor.process(event(.finished, "project-\(index)"))
        }
        XCTAssertTrue(native.delivered.isEmpty, "nothing is sent while the window is open")
        XCTAssertTrue(pushover.sent.isEmpty)
        XCTAssertEqual(try records().count, 10, "state and history are recorded immediately")

        await processor.flushPendingNotifications()

        XCTAssertEqual(native.delivered.count, 1)
        XCTAssertEqual(native.delivered.first?.nativeTitle, "Claude · 10 sessions")
        XCTAssertEqual(native.delivered.first?.nativeSubtitle, "10 sessions finished")
        XCTAssertEqual(pushover.sent.count, 1)
        XCTAssertEqual(pushover.sent.first?.content.pushoverTitle, "Claude · work · 10 sessions")
        XCTAssertTrue(try records().allSatisfy { $0.wasNativeNotificationSent && $0.wasPushoverSent })
    }

    func testSingleNotificationInWindowIsUnchanged() async throws {
        let e = event(.needsInput, "backend-api", message: "Which migration strategy should be used?")
        await processor.process(e)
        await processor.flushPendingNotifications()
        XCTAssertEqual(pushover.sent.count, 1)
        XCTAssertEqual(pushover.sent.first?.content.pushoverTitle, "Claude · work · backend-api")
        XCTAssertEqual(pushover.sent.first?.content.pushoverMessage, "❓ Claude needs input\nWhich migration strategy should be used?")
        XCTAssertEqual(pushover.sent.first?.priority, 1)
    }

    func testMixedGroupKeepsHighestPriority() async throws {
        await processor.process(event(.finished, "docs"))
        await processor.process(event(.needsInput, "api", message: "Which?"))
        await processor.flushPendingNotifications()
        XCTAssertEqual(pushover.sent.count, 1)
        XCTAssertEqual(pushover.sent.first?.priority, 1, "needs input is high priority, finished is normal")
        XCTAssertTrue(pushover.sent.first?.content.pushoverMessage.hasPrefix("🔔 2 session updates") ?? false)
    }

    func testChannelsAreGroupedIndependently() async throws {
        let raw = ClaudeEventType.finished.rawValue
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<NotificationRule>(predicate: #Predicate { $0.eventTypeRaw == raw })).first)
        rule.sendPushover = false

        await processor.process(event(.finished, "a"))
        await processor.process(event(.finished, "b"))
        await processor.process(event(.needsInput, "c"))
        await processor.flushPendingNotifications()

        XCTAssertEqual(native.delivered.count, 1)
        XCTAssertEqual(native.delivered.first?.nativeSubtitle, "3 session updates")
        XCTAssertEqual(pushover.sent.count, 1)
        XCTAssertEqual(pushover.sent.first?.content.pushoverTitle, "Claude · work · c", "only one item went to Pushover")
    }

    func testPausingDuringTheWindowDropsTheGroup() async throws {
        await processor.process(event(.finished, "a"))
        await processor.process(event(.finished, "b"))
        preferences.isPaused = true
        await processor.flushPendingNotifications()
        XCTAssertTrue(native.delivered.isEmpty)
        XCTAssertTrue(pushover.sent.isEmpty)
        XCTAssertTrue(try records().allSatisfy { !$0.wasNativeNotificationSent && !$0.wasPushoverSent })
    }

    func testWindowTimerFlushesAutomatically() async throws {
        window = 0.2
        await processor.process(event(.finished, "a"))
        await processor.process(event(.finished, "b"))
        XCTAssertTrue(native.delivered.isEmpty)
        for _ in 0..<40 where native.delivered.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(native.delivered.count, 1)
        XCTAssertEqual(native.delivered.first?.nativeSubtitle, "2 sessions finished")
    }

    func testZeroWindowSendsImmediately() async throws {
        window = 0
        await processor.process(event(.finished, "a"))
        await processor.process(event(.finished, "b"))
        XCTAssertEqual(native.delivered.count, 2)
    }
}
