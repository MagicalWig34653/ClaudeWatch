import Foundation
import Observation
import SwiftData
import ClaudeWatchCore

/// Discovers accounts through `cswap` (best-effort) and keeps `ClaudeAccount` metadata in sync.
/// Event processing never waits on this service.
@MainActor
@Observable
final class AccountService {
    enum State: Equatable {
        case idle
        case refreshing
        case loaded(Date)
        case cswapMissing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var executablePath: String?
    private(set) var activeAccount: DetectedAccount?
    @ObservationIgnored private(set) var detectedAccounts: [DetectedAccount] = []

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private var cachedExecutable: URL?

    init(context: ModelContext, runner: CommandRunner = ProcessCommandRunner()) {
        self.context = context
        self.runner = runner
    }

    /// Best-effort alias for a hook payload; `nil` means "Unknown Account".
    func alias(forTranscriptPath path: String?) -> String? {
        AccountResolver.alias(transcriptPath: path, accounts: detectedAccounts, activeAccount: activeAccount)
    }

    func refresh() async {
        guard state != .refreshing else { return }
        state = .refreshing
        cachedExecutable = nil
        guard let executable = await locateExecutable() else {
            executablePath = nil
            state = .cswapMissing
            Log.cswap.info("cswap not found")
            return
        }
        executablePath = executable.path
        let provider = CSwapAccountProvider(executable: { executable }, runner: runner)
        do {
            let accounts = try await provider.accounts()
            let active = try? await provider.currentAccount()
            detectedAccounts = accounts
            activeAccount = active ?? accounts.first(where: \.isActive)
            upsert(accounts)
            state = .loaded(Date())
            Log.cswap.info("Loaded \(accounts.count, privacy: .public) accounts from cswap")
        } catch {
            state = .failed(error.localizedDescription)
            Log.cswap.error("cswap refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func locateExecutable() async -> URL? {
        if let cachedExecutable { return cachedExecutable }
        let fileManager = FileManager.default
        let override = UserDefaults.standard.string(forKey: Preferences.Key.cswapPathOverride)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let locator = CSwapExecutableLocator(homeDirectory: NSHomeDirectory())
        if let found = locator.locateInKnownDirectories(isExecutable: { fileManager.isExecutableFile(atPath: $0) }) {
            cachedExecutable = found
            return found
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let found = await locator.locateViaLoginShell(shell: shell, runner: runner) { path in
            FileManager.default.isExecutableFile(atPath: path)
        }
        cachedExecutable = found
        return found
    }

    private func upsert(_ detected: [DetectedAccount]) {
        let existing = (try? context.fetch(FetchDescriptor<ClaudeAccount>())) ?? []
        var byAlias = Dictionary(existing.map { ($0.alias, $0) }, uniquingKeysWith: { first, _ in first })
        let detectedAliases = Set(detected.map(\.alias))
        for account in detected {
            let model: ClaudeAccount
            if let known = byAlias[account.alias] {
                model = known
            } else {
                model = ClaudeAccount(alias: account.alias)
                context.insert(model)
                byAlias[account.alias] = model
            }
            model.displayName = account.email
            model.providerNumber = account.number
            model.isKnownToProvider = true
        }
        for model in existing where !detectedAliases.contains(model.alias) {
            model.isKnownToProvider = false
        }
        do { try context.save() } catch {
            Log.persistence.error("Could not save accounts: \(error.localizedDescription, privacy: .public)")
        }
    }
}
