import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Preferences.Key.showMenuBarItem) private var showMenuBarItem = true
    @AppStorage(Preferences.Key.historyRetentionDays) private var retentionDays = Preferences.defaultRetentionDays
    @AppStorage(Preferences.Key.listenerPort) private var listenerPort = Preferences.defaultListenerPort
    @AppStorage(Preferences.Key.cswapPathOverride) private var cswapPath = ""

    @State private var portText = ""

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch ClaudeWatch at login", isOn: Binding(
                    get: { appState.launchAtLogin.isEnabled },
                    set: { appState.launchAtLogin.setEnabled($0) }
                ))
                launchAtLoginStatus
                Toggle("Show menu bar item", isOn: $showMenuBarItem)
                Picker("History retention", selection: $retentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("Forever").tag(0)
                }
                .onChange(of: retentionDays) { appState.runRetention() }
            }

            Section("Local Listener") {
                LabeledContent("Status") { ListenerStatusLabel(state: appState.listener.state) }
                LabeledContent("Port") {
                    HStack {
                        TextField("Port", text: $portText)
                            .labelsHidden()
                            .frame(width: 80)
                            .onSubmit(applyPort)
                        Button("Apply", action: applyPort)
                            .disabled(parsedPort == nil || (parsedPort == listenerPort && appState.listener.isRunning))
                    }
                }
                if parsedPort == nil {
                    Text("Enter a port between 1024 and 65535.").font(.callout).foregroundStyle(.red)
                }
                LabeledContent("Events received") {
                    Text(verbatim: "\(appState.listener.acceptedCount) accepted, \(appState.listener.rejectedCount) rejected")
                }
                HStack {
                    Button("Send Test Event") { Task { await appState.sendTestEvent() } }
                    testEventStatus
                }
            }

            Section("Claude Code Hooks") {
                Text("Add the hook configuration to `~/.claude/settings.json` (or a project’s `.claude/settings.json`). ClaudeWatch never edits Claude Code settings itself. See README.md for details.")
                    .foregroundStyle(.secondary)
                Text(verbatim: HookSetup.exampleSettings(port: listenerPort))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Button("Copy Hook Configuration") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(HookSetup.exampleSettings(port: listenerPort), forType: .string)
                }
            }

            Section("cswap") {
                TextField("cswap path", text: $cswapPath, prompt: Text("Detect automatically"))
                Text("Leave empty to search ~/.local/bin, Homebrew and your login shell’s PATH.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            portText = String(listenerPort)
            appState.launchAtLogin.refresh()
        }
    }

    private var parsedPort: Int? {
        guard let value = Int(portText.trimmingCharacters(in: .whitespaces)), (1024...65535).contains(value) else { return nil }
        return value
    }

    private func applyPort() {
        guard let port = parsedPort else { return }
        listenerPort = port
        appState.startListener()
    }

    @ViewBuilder
    private var launchAtLoginStatus: some View {
        let service = appState.launchAtLogin
        if let error = service.lastError {
            Text(verbatim: error).font(.callout).foregroundStyle(.red)
        }
        if service.status == .requiresApproval {
            HStack {
                Text(service.statusDescription).font(.callout).foregroundStyle(.secondary)
                Button("Open Login Items…") { service.openLoginItemsSettings() }
            }
        }
    }

    @ViewBuilder
    private var testEventStatus: some View {
        switch appState.testEventStatus {
        case .idle:
            EmptyView()
        case .sending:
            ProgressView().controlSize(.small)
        case .sent:
            Label("Test event accepted by the listener", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "xmark.octagon.fill")
            }
            .foregroundStyle(.red)
        }
    }
}

enum HookSetup {
    /// The recommended hook configuration, mirroring `Integration/claude-settings.example.json`.
    static func exampleSettings(port: Int) -> String {
        let command = port == Preferences.defaultListenerPort
            ? "~/.claude/hooks/claude-watch-hook.sh"
            : "CLAUDE_WATCH_PORT=\(port) ~/.claude/hooks/claude-watch-hook.sh"
        let hook = "[{ \"hooks\": [{ \"type\": \"command\", \"command\": \"\(command)\", \"timeout\": 5 }] }]"
        let matched = { (matcher: String) in
            "[{ \"matcher\": \"\(matcher)\", \"hooks\": [{ \"type\": \"command\", \"command\": \"\(command)\", \"timeout\": 5 }] }]"
        }
        return """
        {
          "hooks": {
            "SessionStart": \(hook),
            "UserPromptSubmit": \(hook),
            "PreToolUse": \(matched("AskUserQuestion|ExitPlanMode")),
            "PermissionRequest": \(matched("*")),
            "PostToolUse": \(matched("*")),
            "Notification": \(hook),
            "Stop": \(hook),
            "StopFailure": \(hook),
            "SessionEnd": \(hook)
          }
        }
        """
    }
}
