import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: SyncViewModel

    var body: some View {
        Group {
            // Header
            Text("ICS Calendar Sync")
                .font(.headline)

            if viewModel.hasFeeds {
                Text("\(viewModel.enabledFeeds.count) of \(viewModel.feeds.count) feeds enabled")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Status
            if !viewModel.hasFeeds {
                Label("No feeds configured", systemImage: "exclamationmark.triangle.fill")
            } else {
                Label(viewModel.statusDescription, systemImage: statusIcon)
                Label("Last sync: \(viewModel.lastSyncDescription)", systemImage: "clock")
                Label("\(viewModel.eventCount) events", systemImage: "calendar")
            }

            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            // Feed list (if not too many)
            if viewModel.feeds.count > 0 && viewModel.feeds.count <= 5 {
                ForEach(viewModel.feeds) { feed in
                    Label(
                        feed.displayName,
                        systemImage: feed.isEnabled ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundColor(feed.isEnabled ? .primary : .secondary)
                }
                Divider()
            }

            // Actions
            Button {
                Task { await viewModel.syncNow() }
            } label: {
                Label("Sync All Feeds", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!viewModel.hasFeeds || viewModel.status == .syncing)
            .keyboardShortcut("r", modifiers: .command)

            Button {
                Task { await viewModel.refreshStatus() }
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }

            Divider()

            // Service Control
            if viewModel.isServiceInstalled {
                // Service is installed - show enable/disable options
                if viewModel.isServiceRunning {
                    Label("Service: Running", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)

                    Button {
                        Task { await viewModel.stopService() }
                    } label: {
                        Label("Disable Service", systemImage: "stop.fill")
                    }
                } else {
                    Label("Service: Stopped", systemImage: "pause.circle.fill")
                        .foregroundColor(.orange)

                    Button {
                        Task { await viewModel.startService() }
                    } label: {
                        Label("Enable Service", systemImage: "play.fill")
                    }
                }

                Button {
                    Task { await viewModel.uninstallService() }
                } label: {
                    Label("Uninstall Service", systemImage: "trash")
                }
            } else {
                // Service not installed - show install option
                Label("Service: Not Installed", systemImage: "xmark.circle")
                    .foregroundColor(.secondary)

                Button {
                    Task { await viewModel.installService() }
                } label: {
                    Label("Install Service", systemImage: "arrow.down.circle")
                }
            }

            Divider()

            SettingsLink {
                Label("Settings...", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                openLogs()
            } label: {
                Label("View Logs...", systemImage: "doc.text")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var statusIcon: String {
        switch viewModel.status {
        case .idle:
            return "checkmark.circle.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }

    private func openLogs() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let logsPath = "\(home)/Library/Logs/ics-calendar-sync"
        let logsURL = URL(fileURLWithPath: logsPath)

        // Create logs directory if it doesn't exist
        try? FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)

        // Open in Finder
        NSWorkspace.shared.open(logsURL)
    }
}

#Preview {
    MenuBarView(viewModel: SyncViewModel())
}
