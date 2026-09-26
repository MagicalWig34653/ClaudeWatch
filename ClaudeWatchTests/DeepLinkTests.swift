import XCTest
@testable import ClaudeWatch

@MainActor
final class DeepLinkTests: XCTestCase {
    func testSessionAndSectionLinks() {
        let appState = AppState(inMemory: true, startServices: false)

        appState.actionHandler.handle(url: URL(string: "claudewatch://section/notifications")!)
        XCTAssertEqual(appState.selectedSection, .notifications)

        appState.actionHandler.handle(url: URL(string: "claudewatch://session/abc-123")!)
        XCTAssertEqual(appState.selectedSection, .sessions)
        XCTAssertEqual(appState.selectedSessionID, "abc-123")
        XCTAssertEqual(appState.sessionFilter, .all)
    }

    func testInvalidLinksAreIgnored() {
        let appState = AppState(inMemory: true, startServices: false)
        appState.actionHandler.handle(url: URL(string: "claudewatch://section/nope")!)
        appState.actionHandler.handle(url: URL(string: "claudewatch://session/a%20b%3Cscript%3E")!)
        appState.actionHandler.handle(url: URL(string: "https://example.com/section/settings")!)
        XCTAssertEqual(appState.selectedSection, .overview)
        XCTAssertNil(appState.selectedSessionID)
    }
}
