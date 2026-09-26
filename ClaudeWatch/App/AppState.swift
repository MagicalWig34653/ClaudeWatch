import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI
import ClaudeWatchCore

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case overview, sessions, accounts, notifications, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .sessions: return "Sessions"
        case .accounts: return "Accounts"
        case .notifications: return "Notifications"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .sessions: return "list.bullet.rectangle"
        case .accounts: return "person.2"
        case .notifications: return "bell.badge"
        case .settings: return "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .overview: return "1"
        case .sessions: return "2"
        case .accounts: return "3"
        case .notifications: return "4"
        case .settings: return "5"
        }
    }
}

enum SessionFilter: String, CaseIterable, Identifiable {
    case active, attention, finished, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .attention: return "Needs Attention"
        case .finished: return "Finished"
        case .all: return "All"
        }
    }

    func matches(_ session: ClaudeSession) -> Bool {
        switch self {
        case .active: return session.isActive
        case .attention: return session.requiresAttention
        case .finished: return session.status == .finished || session.status == .failed
        case .all: return true
        }
    }
}

/// Application-wide state and services shared by the main window and the menu bar.
@MainActor
@Observable
final class AppState {
    static let mainWindowID = "main"

    enum TestEventStatus: Equatable {
        case idle, sending, sent(Date), failed(String)
    }

    let modelContainer: ModelContainer
    let storeError: String?

    let listener: ClaudeEventListener
    let processor: ClaudeEventProcessor
    let nativeNotifications: NativeNotificationService
    let pushover: PushoverService
    let accounts: AccountService
    let launchAtLogin: LaunchAtLoginService
    @ObservationIgnored private(set) var actionHandler: NotificationActionHandler!

    // Navigation
    var selectedSection: SidebarSection? = .overview
    var selectedSessionID: String?
    var sessionFilter: SessionFilter = .active

    // Menu bar summary
    private(set) var attentionCount = 0
    private(set) var activeCount = 0

    var testEventStatus: TestEventStatus = .idle

    /// Set by a live SwiftUI view that has access to `openWindow`.
    @ObservationIgnored var openMainWindowAction: (() -> Void)?

    @ObservationIgnored private let normalizer = ClaudeEventNormalizer(source: .local)
    @ObservationIgnored private var maintenanceTimer: Timer?

    /// - Parameters:
    ///   - inMemory: use a temporary store (tests).
    ///   - startServices: start the listener and background work (disabled in tests).
    init(inMemory: Bool = false, startServices: Bool = true) {
        Preferences.registerDefaults()
        let store = DataStore.open(inMemory: inMemory)
        modelContainer = store.container
        storeError = store.error
        let context = store.container.mainContext
        DataStore.seedNotificationRules(in: context)

        let native = NativeNotificationService()
        let pushover = PushoverService()
        nativeNotifications = native
        self.pushover = pushover
        listener = ClaudeEventListener()
        processor = ClaudeEventProcessor(context: context, native: native, pushover: pushover)
        accounts = AccountService(context: context)
        launchAtLogin = LaunchAtLoginService()

        actionHandler = NotificationActionHandler(appState: self)
        native.onActivate = { [weak self] sessionID, remoteURL in
            self?.actionHandler.activate(sessionID: sessionID, remoteURL: remoteURL)
        }
        processor.onChange = { [weak self] in self?.refreshCounts() }
        listener.onPayload = { [weak self] payload in self?.handle(payload) }

        refreshCounts()
        if startServices {
            startListener()
            Task { await self.startBackgroundWork() }
        }
    }

    // MARK: - Pipeline

    private func handle(_ payload: HookPayload) {
        let alias = accounts.alias(forTranscriptPath: payload.transcriptPath)
        switch normalizer.normalize(payload, receivedAt: Date(), accountAlias: alias) {
        case .event(let event):
            Task { await processor.process(event) }
        case .ignored(let reason):
            Log.events.debug("Ignored hook payload: \(reason, privacy: .public)")
        }
    }

    func startListener() {
        listener.start(port: Preferences.listenerPort())
    }

    func sendTestEvent() async {
        guard case .running(let port) = listener.state else {
            testEventStatus = .failed(TestEventSender.Failure.listenerNotRunning.localizedDescription)
            return
        }
        testEventStatus = .sending
        do {
            try await TestEventSender.send(port: port)
            testEventStatus = .sent(Date())
        } catch {
            testEventStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Summary

    func refreshCounts() {
        let context = modelContainer.mainContext
        let activeRaw = SessionStatus.allCases.filter(\.isActive).map(\.rawValue)
        attentionCount = (try? context.fetchCount(FetchDescriptor<ClaudeSession>(predicate: #Predicate { $0.requiresAttention == true }))) ?? 0
        activeCount = (try? context.fetchCount(FetchDescriptor<ClaudeSession>(predicate: #Predicate { activeRaw.contains($0.statusRaw) }))) ?? 0
    }

    // MARK: - Pause

    func pauseNotifications(for duration: TimeInterval?) {
        let until = duration.map { Date().addingTimeInterval($0).timeIntervalSince1970 } ?? Preferences.pausedIndefinitely
        UserDefaults.standard.set(until, forKey: Preferences.Key.notificationsPausedUntil)
    }

    func resumeNotifications() {
        UserDefaults.standard.set(0.0, forKey: Preferences.Key.notificationsPausedUntil)
    }

    // MARK: - Sessions

    func deleteSession(_ session: ClaudeSession) {
        if selectedSessionID == session.id { selectedSessionID = nil }
        RetentionService.delete(session, context: modelContainer.mainContext)
        refreshCounts()
    }

    func markFinished(_ session: ClaudeSession) {
        processor.markFinished(session)
    }

    func openMainWindow() {
        actionHandler.openMainWindow()
    }

    // MARK: - Maintenance

    private func startBackgroundWork() async {
        await nativeNotifications.refreshAuthorization()
        runRetention()
        await accounts.refresh()
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.runRetention()
                await self.accounts.refresh()
            }
        }
    }

    func runRetention() {
        RetentionService.cleanUp(
            context: modelContainer.mainContext,
            retentionDays: UserDefaults.standard.integer(forKey: Preferences.Key.historyRetentionDays)
        )
        refreshCounts()
    }
}
