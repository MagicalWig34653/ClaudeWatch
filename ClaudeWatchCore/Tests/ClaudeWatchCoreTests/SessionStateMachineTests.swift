import XCTest
@testable import ClaudeWatchCore

final class SessionStateMachineTests: XCTestCase {
    private func next(_ current: SessionStatus?, _ event: ClaudeEventType) -> SessionStatus {
        SessionStateMachine.nextStatus(from: current, on: event)
    }

    func testRunningToNeedsInput() { XCTAssertEqual(next(.running, .needsInput), .needsInput) }
    func testNeedsInputToRunning() { XCTAssertEqual(next(.needsInput, .activity), .running) }
    func testRunningToFinished() { XCTAssertEqual(next(.running, .finished), .finished) }
    func testFinishedToRunning() { XCTAssertEqual(next(.finished, .activity), .running) }
    func testRunningToFailed() { XCTAssertEqual(next(.running, .failed), .failed) }
    func testFailedToRunningOnNewActivity() { XCTAssertEqual(next(.failed, .sessionStarted), .running) }

    func testAttentionStates() {
        XCTAssertEqual(next(.running, .permissionRequired), .waitingForPermission)
        XCTAssertEqual(next(.running, .planApprovalRequired), .waitingForPlanApproval)
        XCTAssertEqual(next(nil, .needsInput), .needsInput)
        XCTAssertEqual(next(.waitingForPermission, .activity), .running)
    }

    func testSessionEndKeepsFailure() {
        XCTAssertEqual(next(.failed, .sessionEnded), .failed)
        XCTAssertEqual(next(.running, .sessionEnded), .finished)
        XCTAssertEqual(next(.needsInput, .sessionEnded), .finished)
    }

    func testIdleDoesNotChangeStatus() {
        XCTAssertEqual(next(.finished, .idle), .finished)
        XCTAssertEqual(next(.needsInput, .idle), .needsInput)
        XCTAssertEqual(next(nil, .idle), .finished)
    }

    func testRequiresAttention() {
        XCTAssertTrue(SessionStateMachine.requiresAttention(.needsInput))
        XCTAssertTrue(SessionStateMachine.requiresAttention(.waitingForPermission))
        XCTAssertTrue(SessionStateMachine.requiresAttention(.waitingForPlanApproval))
        XCTAssertTrue(SessionStateMachine.requiresAttention(.failed))
        XCTAssertFalse(SessionStateMachine.requiresAttention(.running))
        XCTAssertFalse(SessionStateMachine.requiresAttention(.finished))
    }

    func testActiveStatuses() {
        XCTAssertTrue(SessionStatus.running.isActive)
        XCTAssertTrue(SessionStatus.needsInput.isActive)
        XCTAssertFalse(SessionStatus.finished.isActive)
        XCTAssertFalse(SessionStatus.failed.isActive)
    }
}
