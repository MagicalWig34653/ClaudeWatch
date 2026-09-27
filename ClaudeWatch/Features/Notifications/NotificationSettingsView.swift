import SwiftUI
import SwiftData
import ClaudeWatchCore

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var rules: [NotificationRule]

    @AppStorage(Preferences.Key.pushoverEnabled) private var pushoverEnabled = false
    @AppStorage(Preferences.Key.nativeNotificationsEnabled) private var nativeEnabled = true
    @AppStorage(Preferences.Key.notificationSoundEnabled) private var soundEnabled = true
    @AppStorage(Preferences.Key.notificationsPausedUntil) private var pausedUntil = 0.0
    @AppStorage(Preferences.Key.notificationGroupingWindow) private var groupingWindow = Preferences.defaultGroupingWindow

    @State private var nativeTestError: String?

    private var orderedRules: [NotificationRule] {
        let order = ClaudeEventType.notifiable
        return rules
            .filter { $0.eventType != nil && $0.eventType != .activity }
            .sorted { (order.firstIndex(of: $0.eventType!) ?? .max) < (order.firstIndex(of: $1.eventType!) ?? .max) }
    }

    var body: some View {
        Form {
            Section("Channels") {
                Toggle("Pushover", isOn: $pushoverEnabled)
                Toggle("Native macOS notifications", isOn: $nativeEnabled)
                Toggle("Sound", isOn: $soundEnabled)
                Picker(selection: $groupingWindow) {
                    Text("Off").tag(0.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                } label: {
                    Text("Group notifications")
                    Text("Notifications arriving within this time are combined into one, e.g. “10 sessions finished”.")
                }
                pauseControls
            }

            Section("Events") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        Text("Event").fontWeight(.medium)
                        Text("macOS").fontWeight(.medium).gridColumnAlignment(.center)
                        Text("Pushover").fontWeight(.medium).gridColumnAlignment(.center)
                        Text("Pushover Priority").fontWeight(.medium)
                        Text("")
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(orderedRules) { rule in
                        RuleRow(rule: rule) { try? modelContext.save() }
                    }
                }
            }

            PushoverSettingsSection()

            Section("macOS Notifications") {
                LabeledContent("Permission", value: appState.nativeNotifications.authorization.displayName)
                HStack {
                    switch appState.nativeNotifications.authorization {
                    case .notDetermined:
                        Button("Allow Notifications…") {
                            Task { await appState.nativeNotifications.requestAuthorizationIfNeeded() }
                        }
                    case .denied:
                        Button("Open System Settings…") { appState.nativeNotifications.openSystemNotificationSettings() }
                    default:
                        EmptyView()
                    }
                    Button("Send Test Notification") {
                        Task {
                            do {
                                try await appState.nativeNotifications.sendTestNotification()
                                nativeTestError = nil
                            } catch {
                                nativeTestError = error.localizedDescription
                            }
                        }
                    }
                }
                if let nativeTestError {
                    Text(verbatim: nativeTestError).foregroundStyle(.red).font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .task { await appState.nativeNotifications.refreshAuthorization() }
    }

    @ViewBuilder
    private var pauseControls: some View {
        if Preferences.isPaused(pausedUntil: pausedUntil) {
            HStack {
                PausedLabel(pausedUntil: pausedUntil)
                Spacer()
                Button("Resume") { appState.resumeNotifications() }
            }
        } else {
            LabeledContent("Pause") {
                Menu("Pause Notifications") {
                    Button("For 1 Hour") { appState.pauseNotifications(for: 3600) }
                    Button("For 4 Hours") { appState.pauseNotifications(for: 4 * 3600) }
                    Button("Until Resumed") { appState.pauseNotifications(for: nil) }
                }
                .fixedSize()
            }
        }
    }
}

private struct RuleRow: View {
    @Bindable var rule: NotificationRule
    let onChange: () -> Void
    @State private var showOptions = false

    var body: some View {
        GridRow {
            Text(rule.eventType?.displayName ?? rule.eventTypeRaw)
            Toggle("macOS", isOn: $rule.sendNativeNotification).labelsHidden()
                .onChange(of: rule.sendNativeNotification) { changed() }
            Toggle("Pushover", isOn: $rule.sendPushover).labelsHidden()
                .onChange(of: rule.sendPushover) { changed() }
            Picker("Priority", selection: $rule.pushoverPriority) {
                Text("Lowest").tag(-2)
                Text("Low").tag(-1)
                Text("Normal").tag(0)
                Text("High").tag(1)
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!rule.sendPushover)
            .onChange(of: rule.pushoverPriority) { onChange() }
            Button {
                showOptions.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Content options")
            .popover(isPresented: $showOptions, arrowEdge: .trailing) {
                Form {
                    Toggle("Include project name", isOn: $rule.includeProjectName)
                    Toggle("Include account alias", isOn: $rule.includeAccountAlias)
                    Toggle("Include message preview", isOn: $rule.includeMessagePreview)
                    Toggle("Play sound", isOn: $rule.playNativeSound)
                }
                .padding()
                .frame(width: 260)
                .onDisappear { onChange() }
            }
        }
    }

    private func changed() {
        rule.updateEnabledFromChannels()
        onChange()
    }
}
