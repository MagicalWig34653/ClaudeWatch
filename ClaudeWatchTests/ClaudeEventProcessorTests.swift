import XCTest
import SwiftData
@testable import ClaudeWatch
import ClaudeWatchCore

/// Exercises the pipeline from raw hook JSON to SwiftData and notification channels.
@MainActor
final class ClaudeEventProcessorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var native: FakeNativeNotifier!
    private var pushover: FakePushover!
    private var preferences = NotificationPreferences(nativeNotificationsEnabled: true, pushoverEnabled: true, soundEnabled: true, isPaused: false)
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
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
            now: { [unowned self] in self.clock }
        )
    }

    // MARK: Helpers

    private func hook(_ json: String, alias: String? = "work") -> ClaudeEvent {
        let payload = try! HookPayloadDecoder().decode(Data(json.utf8))
        guard case .event(let event) = ClaudeEventNormalizer().normalize(payload, receivedAt: clock, accountAlias: alias) else {
            fatalError("fixture did not normalize")
        }
        return event
    }

    private func askQuestion(_ question: String, turn: String = "t1") -> ClaudeEvent {
        hook(#"{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/Users/example/Projects/backend-api","prompt_id":"\#(turn)","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"\#(question)","header":"Q","options":[],"multiSelect":false}]}}"#)
    }

    private var stop: ClaudeEvent {
        hook(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/Users/example/Projects/backend-api","prompt_id":"t1","last_assistant_message":"All done."}"#)
    }

    private var activity: ClaudeEvent {
        hook(#"{"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/Users/example/Projects/backend-api","tool_name":"Bash","tool_input":{"command":"ls"}}"#)
    }

    private func session(_ id: String = "s1") throws -> ClaudeSession {
        try XCTUnwrap(context.fetch(FetchDescriptor<ClaudeSession>(predicate: #Predicate { $0.id == id })).first)
    }

    private func records() throws -> [ClaudeEventRecord] {
        try context.fetch(FetchDescriptor<ClaudeEventRecord>(sortBy: [SortDescriptor(\.receivedAt)]))
    }

    // MARK: Tests

    func testVerticalSliceNeedsInputCreatesSessionRecordAndNotifications() async throws {
        await processor.process(askQuestion("Which migration strategy should be used?"))

        let s = try session()
        XCTAssertEqual(s.status, .needsInput)
        XCTAssertTrue(s.requiresAttention)
        XCTAssertEqual(s.projectName, "backend-api")
        XCTAssertEqual(s.accountAlias, "work")
        XCTAssertEqual(s.lastMessage, "Which migration strategy should be used?")

        let record = try XCTUnwrap(records().first)
        XCTAssertEqual(record.eventType, .needsInput)
        XCTAssertTrue(record.wasNativeNotificationSent)
        XCTAssertTrue(record.wasPushoverSent)

        XCTAssertEqual(native.delivered.count, 1)
        XCTAssertEqual(pushover.sent.count, 1)
        XCTAssertEqual(pushover.sent.first?.content.pushoverTitle, "Claude · work · backend-api")
        XCTAssertEqual(pushover.sent.first?.content.pushoverMessage, "❓ Claude needs input\nWhich migration strategy should be used?")
        XCTAssertEqual(pushover.sent.first?.priority, 1)
    }

    func testDuplicateDeliveriesNotifyOnce() async throws {
        let event = askQuestion("Which strategy?")
        await processor.process(event)
        clock.addTimeInterval(1)
        let second = await processor.process(askQuestion("Which strategy?"))
        clock.addTimeInterval(1)
        await processor.process(askQuestion("Which strategy?"))

        XCTAssertTrue(second.isDuplicate)
        XCTAssertEqual(native.delivered.count, 1)
        XCTAssertEqual(pushover.sent.count, 1)
        XCTAssertEqual(try records().filter(\.isDuplicate).count, 2)
    }

    func testNewQuestionInSameSessionNotifiesAgain() async throws {
        await processor.process(askQuestion("Which strategy?"))
        clock.addTimeInterval(5)
        await processor.process(askQuestion("Which database?"))
        XCTAssertEqual(pushover.sent.count, 2)
    }

    func testStateTransitionsThroughPipeline() async throws {
        await processor.process(askQuestion("Q?"))
        XCTAssertEqual(try session().status, .needsInput)

        clock.addTimeInterval(10)
        await processor.process(activity)
        XCTAssertEqual(try session().status, .running)

        clock.addTimeInterval(10)
        await processor.process(stop)
        let s = try session()
        XCTAssertEqual(s.status, .finished)
        XCTAssertNotNil(s.finishedAt)
        XCTAssertFalse(s.requiresAttention)

        clock.addTimeInterval(10)
        await processor.process(activity)
        XCTAssertEqual(try session().status, .running)
        XCTAssertNil(try session().finishedAt)
    }

    func testActivityIsRecordedOnlyOnStatusChange() async throws {
        await processor.process(activity) // unknown → running: recorded
        await processor.process(activity) // running → running: not recorded
        await processor.process(activity)
        XCTAssertEqual(try records().count, 1)
        XCTAssertEqual(native.delivered.count, 0)
    }

    func testPausedStillRecordsButDoesNotNotify() async throws {
        preferences.isPaused = true
        await processor.process(stop)
        XCTAssertEqual(try session().status, .finished)
        XCTAssertEqual(try records().count, 1)
        XCTAssertTrue(native.delivered.isEmpty)
        XCTAssertTrue(pushover.sent.isEmpty)
    }

    func testChannelsCanBeDisabledIndependently() async throws {
        preferences.pushoverEnabled = false
        await processor.process(stop)
        XCTAssertEqual(native.delivered.count, 1)
        XCTAssertEqual(pushover.sent.count, 0)

        preferences.pushoverEnabled = true
        preferences.nativeNotificationsEnabled = false
        clock.addTimeInterval(1)
        await processor.process(askQuestion("Another?"))
        XCTAssertEqual(native.delivered.count, 1)
        XCTAssertEqual(pushover.sent.count, 1)
    }

    func testDisabledRuleDoesNotNotify() async throws {
        let raw = ClaudeEventType.finished.rawValue
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<NotificationRule>(predicate: #Predicate { $0.eventTypeRaw == raw })).first)
        rule.sendPushover = false
        rule.sendNativeNotification = false
        rule.updateEnabledFromChannels()
        await processor.process(stop)
        XCTAssertTrue(native.delivered.isEmpty)
        XCTAssertTrue(pushover.sent.isEmpty)
    }

    func testSessionStartIsSilentByDefault() async throws {
        await processor.process(hook(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/tmp/x","source":"startup"}"#))
        XCTAssertEqual(try session().status, .running)
        XCTAssertTrue(native.delivered.isEmpty)
    }

    func testAccountDisabledSuppressesNotifications() async throws {
        context.insert(ClaudeAccount(alias: "work", notificationsEnabled: false))
        await processor.process(stop)
        XCTAssertTrue(native.delivered.isEmpty)
        XCTAssertTrue(pushover.sent.isEmpty)
    }

    func testUnknownAccountIsRegisteredAndEnabled() async throws {
        await processor.process(hook(#"{"hook_event_name":"Stop","session_id":"s2"}"#, alias: "client-a"))
        let accounts = try context.fetch(FetchDescriptor<ClaudeAccount>())
        XCTAssertEqual(accounts.map(\.alias), ["client-a"])
        XCTAssertEqual(native.delivered.count, 1)

        await processor.process(hook(#"{"hook_event_name":"Stop","session_id":"s3"}"#, alias: nil))
        XCTAssertEqual(try session("s3").displayAccount, "Unknown Account")
    }

    func testDeliveryErrorsAreRecordedWithoutBreakingProcessing() async throws {
        pushover.error = PushoverError.network("You appear to be offline.")
        native.error = NativeNotificationError.notAuthorized
        await processor.process(stop)
        let record = try XCTUnwrap(records().first)
        XCTAssertFalse(record.wasPushoverSent)
        XCTAssertEqual(record.pushoverError, "Could not reach Pushover: You appear to be offline.")
        XCTAssertFalse(record.wasNativeNotificationSent)
        XCTAssertNotNil(record.nativeNotificationError)
        XCTAssertEqual(try session().status, .finished)
    }

    func testLateSupplementaryNotificationDoesNotRegressState() async throws {
        await processor.process(hook(#"{"hook_event_name":"PermissionRequest","session_id":"s1","prompt_id":"t1","tool_name":"Bash","tool_input":{"command":"make"}}"#))
        clock.addTimeInterval(1)
        await processor.process(activity)
        clock.addTimeInterval(1)
        let late = await processor.process(hook(#"{"hook_event_name":"Notification","session_id":"s1","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}"#))
        XCTAssertTrue(late.isDuplicate)
        XCTAssertEqual(try session().status, .running)
        XCTAssertEqual(pushover.sent.count, 1)
    }

    func testRetentionAndDeletionNeverRemoveActiveSessions() async throws {
        await processor.process(askQuestion("Q?")) // active: needsInput
        await processor.process(hook(#"{"hook_event_name":"Stop","session_id":"old"}"#))

        clock.addTimeInterval(40 * 86_400)
        let result = RetentionService.cleanUp(context: context, retentionDays: 30, now: clock)
        XCTAssertEqual(result.sessions, 1)
        XCTAssertNoThrow(try session("s1"))
        XCTAssertThrowsError(try session("old"))

        XCTAssertFalse(RetentionService.delete(try session("s1"), context: context))
        XCTAssertNoThrow(try session("s1"))
    }

    func testMarkFinished() async throws {
        await processor.process(activity)
        processor.markFinished(try session())
        XCTAssertEqual(try session().status, .finished)
    }

    func testOldRecordWithUnknownEventTypeDoesNotBreakProcessing() async throws {
        let record = ClaudeEventRecord(event: stop, fingerprint: "x", isDuplicate: false, receivedAt: clock)
        record.eventTypeRaw = "some_future_type"
        context.insert(record)
        try context.save()
        await processor.process(stop)
        XCTAssertEqual(try session().status, .finished)
        XCTAssertNil(try records().first(where: { $0.eventTypeRaw == "some_future_type" })?.eventType)
    }
}
