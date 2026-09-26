import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $appState.selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(section == .sessions ? appState.attentionCount : 0)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) { StatusFooter() }
        } detail: {
            switch appState.selectedSection ?? .overview {
            case .overview: OverviewView()
            case .sessions: SessionsView()
            case .accounts: AccountsView()
            case .notifications: NotificationSettingsView()
            case .settings: GeneralSettingsView()
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .onAppear {
            let openWindow = openWindow
            appState.openMainWindowAction = { openWindow(id: AppState.mainWindowID) }
        }
    }
}
