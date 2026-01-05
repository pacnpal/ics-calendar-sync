import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: SyncViewModel

    private let menuWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            Text("ICS Calendar Sync")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if viewModel.hasFeeds {
                Text("\(viewModel.enabledFeeds.count) of \(viewModel.feeds.count) feeds enabled")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            }

            Divider()
                .padding(.vertical, 4)

            // Status
            if !viewModel.hasFeeds {
                menuRow(icon: "exclamationmark.triangle.fill", text: "No feeds configured")
            } else {
                menuRow(icon: statusIcon, text: viewModel.statusDescription)
                menuRow(icon: "clock", text: "Last sync: \(viewModel.lastSyncDescription)")
                menuRow(icon: "calendar", text: "\(viewModel.eventCount) events")
            }

            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
            }

            Divider()
                .padding(.vertical, 4)

            // Feed list (if not too many)
            if viewModel.feeds.count > 0 && viewModel.feeds.count <= 5 {
                ForEach(viewModel.feeds) { feed in
                    menuRow(
                        icon: feed.isEnabled ? "checkmark.circle.fill" : "circle",
                        text: feed.displayName,
                        dimmed: !feed.isEnabled
                    )
                }
                Divider()
                    .padding(.vertical, 4)
            }

            // Actions
            menuButton(icon: "arrow.triangle.2.circlepath", text: "Sync All Feeds") {
                Task { await viewModel.syncNow() }
            }
            .disabled(!viewModel.hasFeeds || viewModel.status == .syncing)

            menuButton(icon: "arrow.clockwise", text: "Refresh Status") {
                Task { await viewModel.refreshStatus() }
            }

            Divider()
                .padding(.vertical, 4)

            // Service Control
            if viewModel.isServiceInstalled {
                if viewModel.isServiceRunning {
                    menuButton(icon: "stop.fill", text: "Stop Service") {
                        Task { await viewModel.stopService() }
                    }
                } else {
                    menuButton(icon: "play.fill", text: "Start Service") {
                        Task { await viewModel.startService() }
                    }
                }

                menuButton(icon: "trash", text: "Uninstall Service") {
                    Task { await viewModel.uninstallService() }
                }
            } else {
                menuButton(icon: "arrow.down.circle", text: "Install Service") {
                    Task { await viewModel.installService() }
                }
            }

            Divider()
                .padding(.vertical, 4)

            SettingsLink {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .frame(width: 16)
                    Text("Settings...")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            menuButton(icon: "doc.text", text: "View Logs...") {
                openLogs()
            }

            menuButton(icon: "power", text: "Quit") {
                NSApplication.shared.terminate(nil)
            }

            Spacer()
                .frame(height: 8)
        }
        .frame(width: menuWidth)
    }

    @ViewBuilder
    private func menuRow(icon: String, text: String, dimmed: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
            Text(text)
            Spacer()
        }
        .foregroundColor(dimmed ? .secondary : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func menuButton(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(text)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .cornerRadius(4)
        .modifier(HoverHighlight())
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

struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(4)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

#Preview {
    MenuBarView(viewModel: SyncViewModel())
}
