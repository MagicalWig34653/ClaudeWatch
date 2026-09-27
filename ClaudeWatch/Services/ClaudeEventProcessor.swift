import Foundation
import SwiftData
import ClaudeWatchCore

/// Applies normalized events: session state, event history, deduplication and notifications.
///
/// Runs on the main actor with the shared `ModelContainer`'s main context, so both the
/// main window and the menu bar observe changes immediately.
@MainActor
final class ClaudeEventProcessor {
    struct Outcome: Equatable {
        var status: SessionStatus
        var isDuplicate: Bool
        var recorded: Bool
        var decision: NotificationDecision
    }

    private let context: ModelContext
    private let native: NativeNotifying
    private let pushover: PushoverSending
    private let preferences: () -> NotificationPreferences
    private let deduplicator: EventDeduplicator
    private let now: () -> Date
    private var batcher: NotificationBatcher<PendingDelivery>!

    /// A notification waiting in the grouping window, with the record to update once sent.
    private struct PendingDelivery {
        let recordID: UUID?
        let item: NotificationBatchItem
        let decision: NotificationDecision
    }

    /// Called after every processed event (e.g. to refresh menu bar counts).
    var onChange: (() -> Void)?

    init(
        context: ModelContext,
        native: NativeNotifying,
        pushover: PushoverSending,
        preferences: @escaping () -> NotificationPreferences = { Preferences.notificationPreferences() },
        deduplicator: EventDeduplicator = EventDeduplicator(),
        groupingWindow: @escaping () -> TimeInterval = { 0 },
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.native = native
        self.pushover = pushover
        self.preferences = preferences
        self.deduplicator = deduplicator
        self.now = now
        self.batcher = NotificationBatcher(window: groupingWindow) { [weak self] group in
            await self?.deliver(group)
        }
    }

    /// Sends notifications still waiting in the grouping window now.
    func flushPendingNotifications() async {
        await batcher.flush()
    }

    /// Processes one event. State and history are saved before any notification is sent,
    /// so a concurrent duplicate always sees this event.
    @discardableResult
    func process(_ event: ClaudeEvent) async -> Outcome {
        let receivedAt = now()
        let fingerprint = EventFingerprint.make(for: event)
        let isDuplicate = event.type != .activity
            && deduplicator.isDuplicate(event, fingerprint: fingerprint, priorEvents: priorEvents(for: event.sessionID, before: receivedAt))

        let session = fetchOrCreateSession(for: event, at: receivedAt)
        let previousStatus = session.status
        if !isDuplicate {
            apply(event, to: session, at: receivedAt)
        }

        // Every non-activity event is recorded (duplicates flagged for debugging);
        // activity events only when they change the session's status.
        let shouldRecord = event.type != .activity || session.status != previousStatus
        var record: ClaudeEventRecord?
        if shouldRecord {
            let newRecord = ClaudeEventRecord(event: event, fingerprint: fingerprint, isDuplicate: isDuplicate, receivedAt: receivedAt)
            context.insert(newRecord)
            record = newRecord
        }

        let rule = rule(for: event.type)
        let decision = NotificationPolicy.decide(
            rule: rule,
            preferences: preferences(),
            accountNotificationsEnabled: accountNotificationsEnabled(for: event.accountAlias),
            isDuplicate: isDuplicate
        )
        save()
        Log.events.info("Processed \(event.type.rawValue, privacy: .public) for session \(event.sessionID, privacy: .public): status=\(session.status.rawValue, privacy: .public) duplicate=\(isDuplicate, privacy: .public)")
        onChange?()

        if let rule, decision.sendsAnything {
            await batcher.add(PendingDelivery(
                recordID: record?.id,
                item: NotificationBatchItem(event: event, rule: rule),
                decision: decision
            ))
        }
        return Outcome(status: session.status, isDuplicate: isDuplicate, recorded: record != nil, decision: decision)
    }

    /// Explicit user action for sessions that will never report completion (e.g. a crashed terminal).
    func markFinished(_ session: ClaudeSession) {
        let at = now()
        session.status = SessionStateMachine.nextStatus(from: session.status, on: .finished)
        session.finishedAt = at
        session.updatedAt = at
        save()
        onChange?()
    }

    // MARK: - Steps

    private func priorEvents(for sessionID: String, before date: Date) -> [EventDeduplicator.PriorEvent] {
        let cutoff = date.addingTimeInterval(-max(deduplicator.identicalWindow, deduplicator.crossSourceWindow))
        var descriptor = FetchDescriptor<ClaudeEventRecord>(
            predicate: #Predicate { $0.sessionID == sessionID && $0.isDuplicate == false && $0.receivedAt >= cutoff },
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let records = (try? context.fetch(descriptor)) ?? []
        return records.compactMap { record in
            guard let type = record.eventType else { return nil }
            return EventDeduplicator.PriorEvent(
                fingerprint: record.fingerprint,
                type: type,
                receivedAt: record.sourceTimestamp ?? record.receivedAt,
                isSupplementary: record.isSupplementary
            )
        }
    }

    private func fetchOrCreateSession(for event: ClaudeEvent, at date: Date) -> ClaudeSession {
        let id = event.sessionID
        var descriptor = FetchDescriptor<ClaudeSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let session = ClaudeSession(
            id: id,
            projectName: event.projectName ?? "Unknown Project",
            source: event.source,
            status: .unknown,
            startedAt: date
        )
        context.insert(session)
        Log.sessions.info("New session \(id, privacy: .public)")
        return session
    }

    private func apply(_ event: ClaudeEvent, to session: ClaudeSession, at date: Date) {
        let current: SessionStatus? = session.status == .unknown ? nil : session.status
        let next = SessionStateMachine.nextStatus(from: current, on: event.type)
        if next != session.status {
            Log.sessions.info("Session \(session.id, privacy: .public): \(session.status.rawValue, privacy: .public) → \(next.rawValue, privacy: .public)")
        }
        session.status = next
        session.updatedAt = date
        session.lastEventTypeRaw = event.type.rawValue
        switch next {
        case .finished, .failed:
            if session.finishedAt == nil || event.type == .finished || event.type == .failed { session.finishedAt = date }
        default:
            session.finishedAt = nil
        }
        if let project = event.projectName { session.projectName = project }
        if let directory = event.workingDirectory { session.workingDirectory = directory }
        if let alias = event.accountAlias { session.accountAlias = alias }
        if let remoteID = event.remoteSessionID { session.remoteSessionID = remoteID }
        if let url = event.remoteURL { session.remoteURL = url }
        if event.source != .unknown { session.source = event.source }
        if event.type != .activity, event.type != .idle, let message = event.message {
            session.lastMessage = message
        }
    }

    private func rule(for type: ClaudeEventType) -> NotificationRuleSnapshot? {
        let raw = type.rawValue
        var descriptor = FetchDescriptor<NotificationRule>(predicate: #Predicate { $0.eventTypeRaw == raw })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.snapshot
    }

    /// Unknown accounts are registered (enabled) so they can be muted later; no alias means enabled.
    private func accountNotificationsEnabled(for alias: String?) -> Bool {
        guard let alias, !alias.isEmpty else { return true }
        var descriptor = FetchDescriptor<ClaudeAccount>(predicate: #Predicate { $0.alias == alias })
        descriptor.fetchLimit = 1
        if let account = try? context.fetch(descriptor).first {
            account.lastSeenAt = now()
            return account.notificationsEnabled
        }
        let account = ClaudeAccount(alias: alias)
        account.lastSeenAt = now()
        context.insert(account)
        return true
    }

    /// Delivers a group: one notification per channel, combined when the group has
    /// several items. Records are updated with the per-channel result.
    private func deliver(_ group: [PendingDelivery]) async {
        guard !preferences().isPaused else {
            Log.notifications.info("Dropped \(group.count, privacy: .public) grouped notifications: paused")
            return
        }

        let nativeItems = group.filter(\.decision.sendNative)
        var nativeError: String?
        if !nativeItems.isEmpty {
            let content = NotificationSummaryBuilder.build(nativeItems.map(\.item))
            nativeError = await deliverNative(content, playSound: nativeItems.contains(where: \.decision.playSound))
        }

        let pushoverItems = group.filter(\.decision.sendPushover).map(\.item)
        var pushoverError: String?
        if !pushoverItems.isEmpty {
            pushoverError = await deliverPushover(
                NotificationSummaryBuilder.build(pushoverItems),
                priority: NotificationSummaryBuilder.pushoverPriority(pushoverItems),
                playSound: pushoverItems.contains(where: \.rule.playNativeSound)
            )
        }

        let ids = group.compactMap(\.recordID)
        guard !ids.isEmpty else { return }
        let records = (try? context.fetch(FetchDescriptor<ClaudeEventRecord>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let recordsByID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in group {
            guard let id = entry.recordID, let record = recordsByID[id] else { continue }
            if entry.decision.sendNative {
                record.wasNativeNotificationSent = nativeError == nil
                record.nativeNotificationError = nativeError
            }
            if entry.decision.sendPushover {
                record.wasPushoverSent = pushoverError == nil
                record.pushoverError = pushoverError
            }
        }
        save()
    }

    /// Returns an error description, or nil on success.
    private func deliverNative(_ content: NotificationContent, playSound: Bool) async -> String? {
        do {
            try await native.deliver(content, playSound: playSound)
            return nil
        } catch {
            Log.notifications.error("Native notification failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private func deliverPushover(_ content: NotificationContent, priority: Int, playSound: Bool) async -> String? {
        do {
            try await pushover.send(content, priority: priority, playSound: playSound)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Log.persistence.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
