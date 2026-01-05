import SwiftUI

@main
struct ICSCalendarSyncApp: App {
    @StateObject private var viewModel = SyncViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            Label("ICS Calendar Sync", systemImage: viewModel.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
