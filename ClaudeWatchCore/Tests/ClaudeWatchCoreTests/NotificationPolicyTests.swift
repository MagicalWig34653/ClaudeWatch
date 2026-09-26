import XCTest
@testable import ClaudeWatchCore

final class NotificationPolicyTests: XCTestCase {
    private let allOn = NotificationPreferences(nativeNotificationsEnabled: true, pushoverEnabled: true, soundEnabled: true, isPaused: false)
    private let rule = NotificationRuleSnapshot(eventType: .needsInput, enabled: true, sendNativeNotification: true, sendPushover: true)

    func testEnabledRuleSendsBothChannels() {
        let d = NotificationPolicy.decide(rule: rule, preferences: allOn, accountNotificationsEnabled: true, isDuplicate: false)
        XCTAssertEqual(d, NotificationDecision(sendNative: true, sendPushover: true, playSound: true))
    }

    func testDisabledRuleDoesNotSend() {
        var disabled = rule
        disabled.enabled = false
        XCTAssertEqual(NotificationPolicy.decide(rule: disabled, preferences: allOn, accountNotificationsEnabled: true, isDuplicate: false), .none)
        XCTAssertEqual(NotificationPolicy.decide(rule: nil, preferences: allOn, accountNotificationsEnabled: true, isDuplicate: false), .none)
    }

    func testPausedDoesNotSend() {
        var paused = allOn
        paused.isPaused = true
        XCTAssertEqual(NotificationPolicy.decide(rule: rule, preferences: paused, accountNotificationsEnabled: true, isDuplicate: false), .none)
    }

    func testAccountDisabledDoesNotSend() {
        XCTAssertEqual(NotificationPolicy.decide(rule: rule, preferences: allOn, accountNotificationsEnabled: false, isDuplicate: false), .none)
    }

    func testDuplicateDoesNotSend() {
        XCTAssertEqual(NotificationPolicy.decide(rule: rule, preferences: allOn, accountNotificationsEnabled: true, isDuplicate: true), .none)
    }

    func testChannelsAreIndependent() {
        var nativeOnly = rule
        nativeOnly.sendPushover = false
        XCTAssertEqual(
            NotificationPolicy.decide(rule: nativeOnly, preferences: allOn, accountNotificationsEnabled: true, isDuplicate: false),
            NotificationDecision(sendNative: true, sendPushover: false, playSound: true)
        )

        var pushoverGloballyOff = allOn
        pushoverGloballyOff.pushoverEnabled = false
        XCTAssertEqual(
            NotificationPolicy.decide(rule: rule, preferences: pushoverGloballyOff, accountNotificationsEnabled: true, isDuplicate: false),
            NotificationDecision(sendNative: true, sendPushover: false, playSound: true)
        )

        var nativeGloballyOff = allOn
        nativeGloballyOff.nativeNotificationsEnabled = false
        XCTAssertEqual(
            NotificationPolicy.decide(rule: rule, preferences: nativeGloballyOff, accountNotificationsEnabled: true, isDuplicate: false),
            NotificationDecision(sendNative: false, sendPushover: true, playSound: false)
        )
    }

    func testSoundPreferences() {
        var noSound = allOn
        noSound.soundEnabled = false
        XCTAssertFalse(NotificationPolicy.decide(rule: rule, preferences: noSound, accountNotificationsEnabled: true, isDuplicate: false).playSound)
        var silentRule = rule
        silentRule.playNativeSound = false
        XCTAssertFalse(NotificationPolicy.decide(rule: silentRule, preferences: allOn, accountNotificationsEnabled: true, isDuplicate: false).playSound)
    }

    func testDefaultRules() {
        for type in [ClaudeEventType.needsInput, .permissionRequired, .planApprovalRequired, .finished, .failed] {
            let r = NotificationRuleSnapshot.defaultRule(for: type)
            XCTAssertTrue(r.enabled && r.sendNativeNotification && r.sendPushover, "\(type)")
        }
        for type in [ClaudeEventType.sessionStarted, .sessionEnded, .idle] {
            let r = NotificationRuleSnapshot.defaultRule(for: type)
            XCTAssertFalse(r.enabled || r.sendNativeNotification || r.sendPushover, "\(type)")
        }
    }

    func testContentBuilder() {
        let event = ClaudeEvent(type: .needsInput, sessionID: "s1", timestamp: Date(), projectName: "backend", accountAlias: "work",
                                message: "Which migration strategy should be used?")
        let content = NotificationContentBuilder.build(event: event, rule: rule)
        XCTAssertEqual(content.pushoverTitle, "Claude · work · backend")
        XCTAssertEqual(content.pushoverMessage, "❓ Claude needs input\nWhich migration strategy should be used?")
        XCTAssertEqual(content.nativeTitle, "Claude · backend")
        XCTAssertEqual(content.nativeSubtitle, "Needs your input")
        XCTAssertEqual(content.nativeBody, "Which migration strategy should be used?")

        var minimal = rule
        minimal.includeAccountAlias = false
        minimal.includeMessagePreview = false
        let finished = ClaudeEvent(type: .finished, sessionID: "s1", timestamp: Date(), projectName: "backend-api", accountAlias: "work", message: "secret stuff")
        let c2 = NotificationContentBuilder.build(event: finished, rule: minimal)
        XCTAssertEqual(c2.pushoverTitle, "Claude · backend-api")
        XCTAssertEqual(c2.pushoverMessage, "✅ Claude finished\nbackend-api")
        XCTAssertEqual(c2.nativeBody, "")
    }

    func testContentCarriesRemoteURL() {
        let url = URL(string: "https://claude.ai/code/session_123")!
        let event = ClaudeEvent(type: .finished, sessionID: "s1", timestamp: Date(), source: .cloud, remoteURL: url)
        XCTAssertEqual(NotificationContentBuilder.build(event: event, rule: rule).url, url)
    }
}
