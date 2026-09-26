import XCTest
@testable import ClaudeWatchCore

private struct StubRunner: CommandRunner {
    let result: Result<CommandResult, CommandError>
    func run(executable: URL, arguments: [String], environment: [String: String]?, timeout: TimeInterval) async throws -> CommandResult {
        try result.get()
    }
}

final class CSwapTests: XCTestCase {
    func testDecodesRealListOutput() throws {
        let accounts = try CSwapDecoder.decodeList(try Fixture.data("cswap/list"))
        XCTAssertEqual(accounts, [
            DetectedAccount(number: 1, email: "work@example.com", providerAlias: "work", isActive: true, isDisabledInProvider: false),
            DetectedAccount(number: 2, email: "me@example.org", providerAlias: "personal", isActive: false, isDisabledInProvider: true),
        ])
        XCTAssertEqual(accounts.map(\.alias), ["work", "personal"])
    }

    func testDecodesRealStatusOutput() throws {
        let active = try XCTUnwrap(CSwapDecoder.decodeStatus(try Fixture.data("cswap/status")))
        XCTAssertEqual(active.alias, "work")
        XCTAssertEqual(active.number, 1)
        XCTAssertNil(try CSwapDecoder.decodeStatus(try Fixture.data("cswap/status-none")))
        XCTAssertEqual(try CSwapDecoder.decodeList(try Fixture.data("cswap/list-empty")), [])
    }

    func testUnmanagedActiveAccountFallsBackToEmail() throws {
        let data = Data(#"{"schemaVersion":1,"active":{"email":"solo@example.com","managed":false}}"#.utf8)
        XCTAssertEqual(try CSwapDecoder.decodeStatus(data)?.alias, "solo@example.com")
    }

    func testRejectsUnsupportedSchemaAndGarbage() {
        XCTAssertThrowsError(try CSwapDecoder.decodeList(Data(#"{"schemaVersion":2,"accounts":[]}"#.utf8))) {
            XCTAssertEqual($0 as? CSwapError, .unsupportedSchemaVersion(2))
        }
        XCTAssertThrowsError(try CSwapDecoder.decodeList(Data("Accounts:\n  1: x".utf8))) {
            XCTAssertEqual($0 as? CSwapError, .unreadableOutput)
        }
        XCTAssertThrowsError(try CSwapDecoder.decodeList(Data(#"{"schemaVersion":1,"error":{"type":"ClaudeSwitchError","message":"boom"}}"#.utf8))) {
            XCTAssertEqual($0 as? CSwapError, .reportedError("boom"))
        }
    }

    func testSessionPathParsing() {
        XCTAssertEqual(CSwapSessionPath.accountNumber(fromTranscriptPath: "/Users/a/.claude-swap-backup/sessions/2-me_example.org/projects/-Users-a-x/abc.jsonl"), 2)
        XCTAssertEqual(CSwapSessionPath.accountNumber(fromTranscriptPath: "/home/a/.local/share/claude-swap/sessions/12-x/projects/p/s.jsonl"), 12)
        XCTAssertNil(CSwapSessionPath.accountNumber(fromTranscriptPath: "/Users/a/.claude/projects/-Users-a-x/abc.jsonl"))
        XCTAssertNil(CSwapSessionPath.accountNumber(fromTranscriptPath: "/Users/a/.claude-swap-backup/sessions/x-1/projects"))
    }

    func testAccountResolution() {
        let accounts = [
            DetectedAccount(number: 1, email: "work@example.com", providerAlias: "work", isActive: true),
            DetectedAccount(number: 2, email: "me@example.org", providerAlias: nil, isActive: false),
        ]
        let sessionPath = "/Users/a/.claude-swap-backup/sessions/2-me_example.org/projects/p/s.jsonl"
        XCTAssertEqual(AccountResolver.alias(transcriptPath: sessionPath, accounts: accounts, activeAccount: accounts[0]), "me@example.org")
        XCTAssertEqual(AccountResolver.alias(transcriptPath: "/Users/a/.claude/projects/p/s.jsonl", accounts: accounts, activeAccount: accounts[0]), "work")
        XCTAssertNil(AccountResolver.alias(transcriptPath: nil, accounts: [], activeAccount: nil))
    }

    func testLocatorSearchesKnownDirectoriesInOrder() {
        let locator = CSwapExecutableLocator(homeDirectory: "/Users/a")
        XCTAssertEqual(locator.locateInKnownDirectories { $0 == "/usr/local/bin/cswap" || $0 == "/Users/a/bin/cswap" }?.path, "/usr/local/bin/cswap")
        XCTAssertEqual(locator.locateInKnownDirectories { $0 == "/Users/a/.local/bin/cswap" }?.path, "/Users/a/.local/bin/cswap")
        XCTAssertNil(locator.locateInKnownDirectories { _ in false })
    }

    func testLocatorLoginShellFallback() async {
        let locator = CSwapExecutableLocator(homeDirectory: "/Users/a")
        let output = CommandResult(exitCode: 0, standardOutput: Data("Welcome!\n/Users/a/tools/cswap\n".utf8), standardError: Data())
        let found = await locator.locateViaLoginShell(shell: "/bin/zsh", runner: StubRunner(result: .success(output))) { $0 == "/Users/a/tools/cswap" }
        XCTAssertEqual(found?.path, "/Users/a/tools/cswap")
        let notFound = await locator.locateViaLoginShell(shell: "/bin/zsh", runner: StubRunner(result: .success(CommandResult(exitCode: 1, standardOutput: Data(), standardError: Data())))) { _ in true }
        XCTAssertNil(notFound)
    }

    func testProviderErrors() async {
        let missing = CSwapAccountProvider(executable: { nil }, runner: StubRunner(result: .failure(.timedOut)))
        do { _ = try await missing.accounts(); XCTFail() } catch { XCTAssertEqual(error as? CSwapError, .executableNotFound) }

        let exe = URL(fileURLWithPath: "/usr/local/bin/cswap")
        let slow = CSwapAccountProvider(executable: { exe }, runner: StubRunner(result: .failure(.timedOut)))
        do { _ = try await slow.accounts(); XCTFail() } catch { XCTAssertEqual(error as? CSwapError, .timedOut) }

        let failing = CSwapAccountProvider(executable: { exe }, runner: StubRunner(result: .success(CommandResult(
            exitCode: 1, standardOutput: Data(#"{"schemaVersion":1,"error":{"type":"X","message":"No accounts"}}"#.utf8), standardError: Data()))))
        do { _ = try await failing.accounts(); XCTFail() } catch { XCTAssertEqual(error as? CSwapError, .reportedError("No accounts")) }

        let ok = CSwapAccountProvider(executable: { exe }, runner: StubRunner(result: .success(CommandResult(
            exitCode: 0, standardOutput: (try? Fixture.data("cswap/list")) ?? Data(), standardError: Data()))))
        let accounts = try? await ok.accounts()
        XCTAssertEqual(accounts?.count, 2)
    }

    func testProcessRunnerRunsWithArgumentArray() async throws {
        let runner = ProcessCommandRunner()
        let result = try await runner.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hello; rm -rf /", "$(whoami)"], environment: nil, timeout: 5)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(String(decoding: result.standardOutput, as: UTF8.self), "hello; rm -rf / $(whoami)\n")
    }

    func testProcessRunnerTimesOut() async {
        do {
            _ = try await ProcessCommandRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], environment: nil, timeout: 0.3)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? CommandError, .timedOut)
        }
    }
}
