import SwiftUI
import SwiftData

@main
struct ClaudeWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState: AppState
    @AppStorage(Preferences.Key.showMenuBarItem) private var showMenuBarItem = true

    init() {
        Preferences.registerDefaults()
        _appState = State(initialValue: AppState(inMemory: AppEnvironment.isRunningTests, startServices: !AppEnvironment.isRunningTests))
    }

    var body: some Scene {
        Window("ClaudeWatch", id: AppState.mainWindowID) {
            MainView()
                .environment(appState)
                .onOpenURL { url in appState.actionHandler.handle(url: url) }
        }
        .modelContainer(appState.modelContainer)
        .defaultSize(width: 1120, height: 700)
        .handlesExternalEvents(matching: ["*"])
        .commands { AppCommands(appState: appState) }

        MenuBarExtra(isInserted: $showMenuBarItem) {
            MenuBarView()
                .environment(appState)
                .modelContainer(appState.modelContainer)
        } label: {
            MenuBarLabel()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

enum AppEnvironment {
    /// Unit tests run inside the app; they must not touch the user's store or open a port.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
