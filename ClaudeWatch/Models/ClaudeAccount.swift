import Foundation
import SwiftData

/// Account metadata only. ClaudeWatch never stores Claude credentials; `cswap` stays
/// the source of truth for account configuration.
@Model
final class ClaudeAccount {
    @Attribute(.unique) var id: UUID
    /// Name shown with sessions and events (cswap alias, else email).
    @Attribute(.unique) var alias: String
    var displayName: String?
    var notificationsEnabled: Bool

    /// cswap slot number, if the account is known to cswap.
    var providerNumber: Int?
    /// Whether the last cswap refresh reported this account.
    var isKnownToProvider: Bool
    var lastSeenAt: Date?

    init(alias: String, displayName: String? = nil, notificationsEnabled: Bool = true) {
        self.id = UUID()
        self.alias = alias
        self.displayName = displayName
        self.notificationsEnabled = notificationsEnabled
        self.isKnownToProvider = false
    }
}
