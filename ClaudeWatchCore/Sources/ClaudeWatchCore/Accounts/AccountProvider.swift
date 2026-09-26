import Foundation

/// An account as reported by an external account tool. Contains no credentials.
public struct DetectedAccount: Sendable, Equatable, Hashable {
    /// Slot number in the provider, if it has one.
    public let number: Int?
    public let email: String?
    /// Alias configured in the provider (e.g. `cswap alias 1 work`).
    public let providerAlias: String?
    public let isActive: Bool
    /// The provider holds this account out of rotation (informational only).
    public let isDisabledInProvider: Bool

    public init(number: Int?, email: String?, providerAlias: String?, isActive: Bool, isDisabledInProvider: Bool = false) {
        self.number = number
        self.email = email
        self.providerAlias = providerAlias
        self.isActive = isActive
        self.isDisabledInProvider = isDisabledInProvider
    }

    /// The name ClaudeWatch uses for this account: the provider alias, else the email,
    /// else the slot number.
    public var alias: String {
        if let providerAlias, !providerAlias.isEmpty { return providerAlias }
        if let email, !email.isEmpty { return email }
        if let number { return "Account \(number)" }
        return AccountResolver.unknownAccountName
    }
}

public protocol AccountProvider: Sendable {
    func accounts() async throws -> [DetectedAccount]
    func currentAccount() async throws -> DetectedAccount?
}

/// Best-effort attribution of events to accounts. Never required for processing.
public enum AccountResolver {
    public static let unknownAccountName = "Unknown Account"

    /// - Parameters:
    ///   - transcriptPath: the hook payload's `transcript_path`, which lives inside the
    ///     session's Claude config directory.
    ///   - accounts: accounts known from the provider.
    ///   - activeAccount: the provider's currently active (global) account.
    public static func alias(transcriptPath: String?, accounts: [DetectedAccount], activeAccount: DetectedAccount?) -> String? {
        if let transcriptPath, let number = CSwapSessionPath.accountNumber(fromTranscriptPath: transcriptPath) {
            // A `cswap run` session: its config dir names the account slot.
            return accounts.first(where: { $0.number == number })?.alias ?? "Account \(number)"
        }
        return activeAccount?.alias
    }
}
