import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

// MARK: - Config Document for Export

struct ConfigDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var configData: Data

    init(data: Data) {
        self.configData = data
    }

    init(configuration: ReadConfiguration) throws {
        configData = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: configData)
    }
}

// Sheet presentation state
enum SheetType: Identifiable {
    case add
    case edit(FeedConfiguration)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let feed): return "edit-\(feed.id)"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SyncViewModel
    @State private var activeSheet: SheetType?
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var importError: String?
    @State private var exportDocument: ConfigDocument?
    @State private var showingResetConfirmation = false

    private func generateExportDocument() -> ConfigDocument {
        var configDict: [String: Any] = [
            "notifications_enabled": viewModel.notificationsEnabled,
            "global_sync_interval": 15,
            "default_calendar": viewModel.defaultCalendar,
            "version": "2.0.0"
        ]

        let feedsArray = viewModel.feeds.map { feed -> [String: Any] in
            [
                "id": feed.id.uuidString,
                "name": feed.name,
                "icsURL": feed.icsURL,
                "calendarName": feed.calendarName,
                "syncInterval": feed.syncInterval,
                "deleteOrphans": feed.deleteOrphans,
                "isEnabled": feed.isEnabled,
                "notificationsEnabled": feed.notificationsEnabled
            ]
        }
        configDict["feeds"] = feedsArray

        let data = (try? JSONSerialization.data(withJSONObject: configDict, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return ConfigDocument(data: data)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Access Warnings
            if !viewModel.hasCalendarAccess {
                calendarAccessWarning
            }

            // Feeds List
            feedsListSection

            Divider()

            // Global Settings
            globalSettingsSection

            Divider()

            // Status Bar
            statusBarSection
        }
        .frame(width: 550, height: 480)
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .add:
                FeedEditorView(
                    viewModel: viewModel,
                    feed: nil,
                    onSave: { newFeed in
                        viewModel.addFeed(newFeed)
                        Task { await viewModel.saveConfig() }
                    },
                    onCancel: { activeSheet = nil }
                )
            case .edit(let feed):
                FeedEditorView(
                    viewModel: viewModel,
                    feed: feed,
                    onSave: { updatedFeed in
                        viewModel.updateFeed(updatedFeed)
                        Task { await viewModel.saveConfig() }
                    },
                    onCancel: { activeSheet = nil }
                )
            }
        }
        .onAppear {
            Task { await viewModel.loadAll() }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        do {
                            try await viewModel.importConfig(from: url)
                            importError = nil
                        } catch {
                            importError = error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument ?? ConfigDocument(data: Data()),
            contentType: .json,
            defaultFilename: "ics-calendar-sync-config.json"
        ) { result in
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
            exportDocument = nil
        }
        .alert("Import Error", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Reset Sync State?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task { await viewModel.resetSyncState() }
            }
        } message: {
            Text("This will delete all sync state. Events in your calendars will not be affected, but the next sync will treat all events as new.")
        }
    }

    // MARK: - Access Warnings

    private var calendarAccessWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar Access Required")
                    .font(.headline)

                Text("This app needs access to your calendars to sync events.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Feeds List

    private var feedsListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Calendar Feeds")
                    .font(.headline)
                Spacer()

                // Import/Export buttons
                Button {
                    showingImporter = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .help("Import configuration from JSON file")

                Button {
                    exportDocument = generateExportDocument()
                    showingExporter = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Export configuration to JSON file")

                Button {
                    activeSheet = .add
                } label: {
                    Label("Add Feed", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            // List
            if viewModel.feeds.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No feeds configured")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Click \"Add Feed\" to add your first ICS calendar feed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Add Your First Feed") {
                        activeSheet = .add
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.feeds) { feed in
                        FeedRowView(
                            feed: feed,
                            onToggle: {
                                viewModel.toggleFeed(feed)
                                Task { await viewModel.saveConfig() }
                            },
                            onEdit: {
                                activeSheet = .edit(feed)
                            },
                            onDelete: {
                                viewModel.deleteFeed(feed)
                                Task { await viewModel.saveConfig() }
                            }
                        )
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }
        }
    }

    // MARK: - Global Settings

    private var globalSettingsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                // Global notifications toggle (master switch)
                Toggle("Notifications", isOn: $viewModel.notificationsEnabled)
                    .onChange(of: viewModel.notificationsEnabled) { _, newValue in
                        Task {
                            if newValue {
                                await viewModel.requestNotificationPermission()
                            }
                            await viewModel.saveConfig()
                        }
                    }

                Spacer()

                // Service status
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isServiceRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isServiceRunning ? "Service Running" : "Service Stopped")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Default calendar picker
            if !viewModel.availableCalendars.isEmpty {
                HStack(spacing: 12) {
                    Text("Default Calendar:")
                        .foregroundColor(.secondary)
                    Picker("", selection: $viewModel.defaultCalendar) {
                        Text("None").tag("")
                        ForEach(viewModel.availableCalendars) { cal in
                            Text("\(cal.title) (\(cal.source))").tag(cal.title)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 250)
                    .onChange(of: viewModel.defaultCalendar) { _, _ in
                        Task { await viewModel.saveConfig() }
                    }
                    Spacer()
                }
            }

            // Maintenance actions
            HStack(spacing: 12) {
                Button {
                    openLogs()
                } label: {
                    Label("View Logs", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Button {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset Sync State", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)

                Spacer()
            }
        }
        .padding()
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

    // MARK: - Status Bar

    private var statusBarSection: some View {
        HStack {
            Text("\(viewModel.feeds.count) feeds (\(viewModel.enabledFeeds.count) enabled)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("•")
                .foregroundColor(.secondary)

            Text("\(viewModel.eventCount) events")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("•")
                .foregroundColor(.secondary)

            Text("Last sync: \(viewModel.lastSyncDescription)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if let error = viewModel.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help(error)
            }

            Text("•")
                .foregroundColor(.secondary)

            Text("ICS Calendar Sync v\(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

// MARK: - Feed Row View

struct FeedRowView: View {
    let feed: FeedConfiguration
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Enable toggle
            Toggle("", isOn: Binding(
                get: { feed.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            // Feed info
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.displayName)
                    .font(.body)
                    .foregroundColor(feed.isEnabled ? .primary : .secondary)

                HStack(spacing: 4) {
                    Text(feed.calendarName)
                    if !feed.icsURL.isEmpty {
                        Text("•")
                        Text(shortenURL(feed.icsURL))
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer()

            // Interval
            Text(intervalLabel(feed.syncInterval))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50)

            // Actions
            HStack(spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Edit feed")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash.circle")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete feed")
            }
        }
        .padding(.vertical, 4)
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            return "1 hour"
        }
    }

    private func shortenURL(_ url: String) -> String {
        guard let urlObj = URL(string: url) else { return url }
        return urlObj.host ?? url
    }
}

// MARK: - Feed Editor View

struct FeedEditorView: View {
    @ObservedObject var viewModel: SyncViewModel

    let feed: FeedConfiguration?
    let onSave: (FeedConfiguration) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var icsURL: String = ""
    @State private var calendarName: String = "Subscribed Events"
    @State private var syncInterval: Int = 15
    @State private var deleteOrphans: Bool = true
    @State private var isEnabled: Bool = true
    @State private var notificationsEnabled: Bool = true

    private var isEditing: Bool { feed != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Feed" : "Add Feed")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
            }
            .padding()

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Feed Details Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Feed Details")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Name:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("Optional nickname", text: $name)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("ICS URL:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("https://example.com/calendar.ics", text: $icsURL)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Calendar:")
                                    .frame(width: 80, alignment: .trailing)
                                if viewModel.availableCalendars.isEmpty {
                                    TextField("Target calendar name", text: $calendarName)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    Picker("", selection: $calendarName) {
                                        ForEach(viewModel.availableCalendars) { cal in
                                            Text("\(cal.title) (\(cal.source))")
                                                .tag(cal.title)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    Divider()

                    // Sync Settings Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sync Settings")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Interval:")
                                    .frame(width: 80, alignment: .trailing)
                                Picker("", selection: $syncInterval) {
                                    ForEach(viewModel.syncIntervals, id: \.self) { interval in
                                        Text(intervalLabel(interval)).tag(interval)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GridRow {
                                Text("")
                                    .frame(width: 80)
                                Toggle("Delete orphaned events", isOn: $deleteOrphans)
                            }

                            GridRow {
                                Text("")
                                    .frame(width: 80)
                                Toggle("Show notifications", isOn: $notificationsEnabled)
                            }

                            GridRow {
                                Text("")
                                    .frame(width: 80)
                                Toggle("Enabled", isOn: $isEnabled)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let newFeed = FeedConfiguration(
                        id: feed?.id ?? UUID(),
                        name: name,
                        icsURL: icsURL,
                        calendarName: calendarName,
                        syncInterval: syncInterval,
                        deleteOrphans: deleteOrphans,
                        isEnabled: isEnabled,
                        notificationsEnabled: notificationsEnabled
                    )
                    onSave(newFeed)
                    onCancel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(icsURL.isEmpty || calendarName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 420)
        .onAppear {
            if let feed = feed {
                name = feed.name
                icsURL = feed.icsURL
                calendarName = feed.calendarName
                syncInterval = feed.syncInterval
                deleteOrphans = feed.deleteOrphans
                isEnabled = feed.isEnabled
                notificationsEnabled = feed.notificationsEnabled
            }
            // Set default calendar for new feeds or if current isn't available
            if !viewModel.availableCalendars.isEmpty {
                let calendarNames = viewModel.availableCalendars.map { $0.title }
                if calendarName.isEmpty || !calendarNames.contains(calendarName) {
                    // Use the configured default calendar, or fall back to first available
                    if !viewModel.defaultCalendar.isEmpty && calendarNames.contains(viewModel.defaultCalendar) {
                        calendarName = viewModel.defaultCalendar
                    } else {
                        calendarName = viewModel.availableCalendars.first?.title ?? ""
                    }
                }
            }
        }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes"
        } else {
            return "1 hour"
        }
    }
}

#Preview {
    SettingsView(viewModel: SyncViewModel())
}
