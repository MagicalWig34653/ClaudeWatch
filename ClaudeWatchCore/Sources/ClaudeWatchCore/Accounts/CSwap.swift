import Foundation

/// Decoders for `cswap` (claude-swap) `--json` output, schema version 1.
///
/// Shapes verified against claude-swap 0.26.0 (`cswap list --json`, `cswap status --json`).
/// Only identity metadata is decoded; usage data and anything credential-related is ignored.
public enum CSwapDecoder {
    public static let supportedSchemaVersion = 1

    public static func decodeList(_ data: Data) throws -> [DetectedAccount] {
        let response = try decode(ListResponse.self, from: data)
        return response.accounts.map { account in
            DetectedAccount(
                number: account.number,
                email: account.email,
                providerAlias: account.alias,
                isActive: account.active ?? (account.number == response.activeAccountNumber),
                isDisabledInProvider: account.disabled ?? false
            )
        }
    }

    public static func decodeStatus(_ data: Data) throws -> DetectedAccount? {
        let response = try decode(StatusResponse.self, from: data)
        guard let active = response.active else { return nil }
        return DetectedAccount(number: active.number, email: active.email, providerAlias: active.alias, isActive: true)
    }

    /// The message of cswap's `{"error": {"type", "message"}}` envelope, if `data` is one.
    public static func reportedError(in data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else { return nil }
        return TextSanitizer.preview(envelope.error.message, maxLength: 300) ?? "unknown error"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let message = reportedError(in: data) {
            throw CSwapError.reportedError(message)
        }
        guard let version = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            throw CSwapError.unreadableOutput
        }
        guard version.schemaVersion == supportedSchemaVersion else {
            throw CSwapError.unsupportedSchemaVersion(version.schemaVersion)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CSwapError.unreadableOutput
        }
    }

    private struct VersionProbe: Decodable { let schemaVersion: Int }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }

    private struct ListResponse: Decodable {
        struct Account: Decodable {
            let number: Int
            let email: String?
            let alias: String?
            let active: Bool?
            let disabled: Bool?
        }
        let activeAccountNumber: Int?
        let accounts: [Account]
    }

    private struct StatusResponse: Decodable {
        struct Active: Decodable {
            let number: Int?
            let email: String?
            let alias: String?
        }
        let active: Active?
    }
}

public enum CSwapError: Error, Equatable, LocalizedError {
    case executableNotFound
    case commandFailed(exitCode: Int32, detail: String)
    case timedOut
    case unsupportedSchemaVersion(Int)
    case unreadableOutput
    case reportedError(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "cswap was not found. Install claude-swap or set its path in Settings."
        case .commandFailed(let code, let detail):
            return "cswap exited with status \(code)." + (detail.isEmpty ? "" : " \(detail)")
        case .timedOut:
            return "cswap did not respond in time."
        case .unsupportedSchemaVersion(let version):
            return "This cswap version reports JSON schema \(version); ClaudeWatch supports schema \(CSwapDecoder.supportedSchemaVersion)."
        case .unreadableOutput:
            return "cswap produced output ClaudeWatch could not read."
        case .reportedError(let message):
            return "cswap reported an error: \(message)"
        }
    }
}

/// Recognizes Claude config directories created by `cswap run`.
///
/// claude-swap launches per-account sessions with
/// `CLAUDE_CONFIG_DIR=<backup root>/sessions/<number>-<email slug>`, where the backup
/// root is `~/.claude-swap-backup` on macOS and `$XDG_DATA_HOME/claude-swap` on Linux.
/// Claude Code stores transcripts below the config dir, so `transcript_path` reveals the slot.
public enum CSwapSessionPath {
    private static let markers = ["/.claude-swap-backup/sessions/", "/claude-swap/sessions/"]

    public static func accountNumber(fromTranscriptPath path: String) -> Int? {
        for marker in markers {
            guard let range = path.range(of: marker) else { continue }
            let remainder = path[range.upperBound...]
            let digits = remainder.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty, remainder.dropFirst(digits.count).first == "-" else { continue }
            return Int(digits)
        }
        return nil
    }
}

/// Finds the `cswap` executable without assuming a single install location.
public struct CSwapExecutableLocator: Sendable {
    public static let executableName = "cswap"

    public let homeDirectory: String

    public init(homeDirectory: String) {
        self.homeDirectory = homeDirectory
    }

    /// Directories searched before falling back to the login shell.
    /// Covers uv/pipx (`~/.local/bin`), Homebrew on Apple silicon and Intel, and MacPorts.
    public var searchDirectories: [String] {
        [
            "\(homeDirectory)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(homeDirectory)/bin",
            "/opt/local/bin",
        ]
    }

    public func locateInKnownDirectories(isExecutable: (String) -> Bool) -> URL? {
        for directory in searchDirectories {
            let path = "\(directory)/\(Self.executableName)"
            if isExecutable(path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// Asks the user's login shell where `cswap` is. The command string is a constant;
    /// nothing user- or payload-controlled is interpolated.
    public func locateViaLoginShell(shell: String, runner: CommandRunner, isExecutable: (String) -> Bool) async -> URL? {
        guard shell.hasPrefix("/") else { return nil }
        guard let result = try? await runner.run(
            executable: URL(fileURLWithPath: shell),
            arguments: ["-l", "-c", "command -v \(Self.executableName)"],
            environment: nil,
            timeout: 5
        ), result.exitCode == 0 else { return nil }
        let output = String(decoding: result.standardOutput, as: UTF8.self)
        let candidate = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { $0.hasPrefix("/") }
        guard let candidate, isExecutable(candidate) else { return nil }
        return URL(fileURLWithPath: candidate)
    }
}

/// `AccountProvider` backed by the `cswap` CLI.
public struct CSwapAccountProvider: AccountProvider {
    private let executable: @Sendable () async -> URL?
    private let runner: CommandRunner
    private let timeout: TimeInterval

    /// - Parameter executable: resolves the cswap executable (cached/located by the caller).
    public init(executable: @escaping @Sendable () async -> URL?, runner: CommandRunner = ProcessCommandRunner(), timeout: TimeInterval = 30) {
        self.executable = executable
        self.runner = runner
        self.timeout = timeout
    }

    public func accounts() async throws -> [DetectedAccount] {
        try CSwapDecoder.decodeList(try await run(["list", "--json"]))
    }

    public func currentAccount() async throws -> DetectedAccount? {
        try CSwapDecoder.decodeStatus(try await run(["status", "--json"]))
    }

    private func run(_ arguments: [String]) async throws -> Data {
        guard let url = await executable() else { throw CSwapError.executableNotFound }
        var environment = ProcessInfo.processInfo.environment
        // GUI apps start with a minimal PATH; keep common tool locations reachable for cswap itself.
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", url.deletingLastPathComponent().path]
        environment["PATH"] = (extra + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        environment["NO_COLOR"] = "1"
        let result: CommandResult
        do {
            result = try await runner.run(executable: url, arguments: arguments, environment: environment, timeout: timeout)
        } catch CommandError.timedOut {
            throw CSwapError.timedOut
        } catch {
            throw CSwapError.executableNotFound
        }
        if result.exitCode != 0 {
            // cswap emits a JSON error envelope on stdout for handled errors.
            if let message = CSwapDecoder.reportedError(in: result.standardOutput) {
                throw CSwapError.reportedError(message)
            }
            let stderr = TextSanitizer.firstLine(String(decoding: result.standardError, as: UTF8.self), maxLength: 200) ?? ""
            throw CSwapError.commandFailed(exitCode: result.exitCode, detail: stderr)
        }
        return result.standardOutput
    }
}
