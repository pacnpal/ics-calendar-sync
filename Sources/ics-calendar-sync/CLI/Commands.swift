import ArgumentParser
import Foundation

// MARK: - Root Command

@main
struct ICSCalendarSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ics-calendar-sync",
        abstract: "Sync ICS calendar subscriptions to macOS Calendar",
        version: "1.0.0",
        subcommands: [
            SetupCommand.self,
            SyncCommand.self,
            DaemonCommand.self,
            StatusCommand.self,
            ValidateCommand.self,
            ListCommand.self,
            CalendarsCommand.self,
            ResetCommand.self,
            InstallCommand.self,
            UninstallCommand.self,
        ],
        defaultSubcommand: SyncCommand.self
    )
}

// MARK: - Sync Command

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Run a single sync operation"
    )

    @OptionGroup var global: GlobalOptions
    @OptionGroup var options: SyncOptions

    mutating func run() async throws {
        global.configureLogger()
        let logger = Logger.shared

        logger.info("Starting sync...")

        // Load configuration
        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: global.configPath)

        // Create and initialize sync engine
        let engine = try SyncEngine(config: config)
        try await engine.initialize()

        // Perform sync
        let result = try await engine.sync(dryRun: global.dryRun, fullSync: options.full)

        // Output result
        if global.json {
            printJSONResult(result)
        } else {
            printTextResult(result, dryRun: global.dryRun)
        }

        if !result.isSuccess {
            throw ExitCode.failure
        }
    }

    private func printJSONResult(_ result: SyncResult) {
        let dict: [String: Any] = [
            "created": result.created,
            "updated": result.updated,
            "deleted": result.deleted,
            "unchanged": result.unchanged,
            "errors": result.errors.map { ["uid": $0.uid, "operation": $0.operation, "message": $0.message] },
            "success": result.isSuccess
        ]

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    private func printTextResult(_ result: SyncResult, dryRun: Bool) {
        let logger = Logger.shared

        if dryRun {
            logger.info("Dry run complete (no changes made)")
        }

        logger.separator()
        print("Sync Summary:")
        print("  Created:   \(result.created)")
        print("  Updated:   \(result.updated)")
        print("  Deleted:   \(result.deleted)")
        print("  Unchanged: \(result.unchanged)")

        if !result.errors.isEmpty {
            print("\nErrors (\(result.errors.count)):")
            for error in result.errors.prefix(5) {
                print("  - [\(error.operation)] \(error.uid): \(error.message)")
            }
            if result.errors.count > 5 {
                print("  ... and \(result.errors.count - 5) more")
            }
        }
    }
}

// MARK: - Daemon Command

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run in daemon mode (continuous sync)"
    )

    @OptionGroup var global: GlobalOptions
    @OptionGroup var options: DaemonOptions

    mutating func run() async throws {
        global.configureLogger()
        let logger = Logger.shared

        logger.info("Starting daemon mode...")

        try await DaemonRunner.run(
            configPath: global.configPath,
            intervalOverride: options.interval
        )
    }
}

// MARK: - Status Command

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show sync status and statistics"
    )

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        global.configureLogger()

        // Load configuration
        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: global.configPath)

        // Create engine and get status
        let engine = try SyncEngine(config: config)
        try await engine.initialize()
        let status = try await engine.getStatus()

        // Check service status
        let serviceStatus = LaunchdGenerator.getStatus()

        if global.json {
            printJSONStatus(status, serviceStatus: serviceStatus, config: config)
        } else {
            printTextStatus(status, serviceStatus: serviceStatus, config: config)
        }
    }

    private func printJSONStatus(_ status: SyncEngine.SyncStatus, serviceStatus: LaunchdGenerator.ServiceStatus, config: Configuration) {
        var dict: [String: Any] = [
            "tracked_events": status.eventCount,
            "service_status": String(describing: serviceStatus),
            "source_url": config.source.url,
            "calendar_name": config.destination.calendarName
        ]

        if let lastSync = status.lastSuccessfulSync {
            dict["last_successful_sync"] = lastSync.iso8601String
        }

        dict["recent_syncs"] = status.recentHistory.prefix(5).map { record -> [String: Any] in
            var r: [String: Any] = [
                "status": record.status.rawValue,
                "started_at": record.startedAt.iso8601String,
                "created": record.eventsCreated,
                "updated": record.eventsUpdated,
                "deleted": record.eventsDeleted
            ]
            if let completed = record.completedAt {
                r["completed_at"] = completed.iso8601String
            }
            return r
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    private func printTextStatus(_ status: SyncEngine.SyncStatus, serviceStatus: LaunchdGenerator.ServiceStatus, config: Configuration) {
        print("ICS Calendar Sync Status")
        print(String(repeating: "=", count: 40))
        print()

        print("Configuration:")
        print("  Source URL:     \(config.source.url)")
        print("  Calendar:       \(config.destination.calendarName)")
        print("  Sync Interval:  \(config.daemon.intervalMinutes) minutes")
        print()

        print("Sync State:")
        print("  Tracked Events: \(status.eventCount)")
        if let lastSync = status.lastSuccessfulSync {
            print("  Last Sync:      \(lastSync.formatted())")
        } else {
            print("  Last Sync:      Never")
        }
        print()

        print("Service Status:   \(serviceStatus.description)")
        print()

        if !status.recentHistory.isEmpty {
            print("Recent Sync History:")
            for record in status.recentHistory.prefix(5) {
                let statusIcon: String
                switch record.status {
                case .success: statusIcon = "✓"
                case .partial: statusIcon = "⚠"
                case .failed: statusIcon = "✗"
                }
                let time = record.startedAt.formatted(style: .short, timeStyle: .short)
                print("  \(statusIcon) \(time) - +\(record.eventsCreated) ~\(record.eventsUpdated) -\(record.eventsDeleted)")
            }
        }
    }
}

// MARK: - Validate Command

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate configuration file"
    )

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        global.configureLogger()
        let logger = Logger.shared

        logger.info("Validating configuration...")

        let configManager = ConfigurationManager.shared

        do {
            let config = try await configManager.load(from: global.configPath)
            logger.success("Configuration is valid")

            if !global.quiet {
                print("\nConfiguration Summary:")
                print("  Source URL:     \(config.source.url)")
                print("  Calendar:       \(config.destination.calendarName)")
                print("  Delete Orphans: \(config.sync.deleteOrphans)")
                print("  Sync Interval:  \(config.daemon.intervalMinutes) min")
            }
        } catch {
            logger.failure("Configuration is invalid")
            throw error
        }
    }
}

// MARK: - List Command

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List events currently tracked in sync state"
    )

    @OptionGroup var global: GlobalOptions
    @OptionGroup var options: ListOptions

    mutating func run() async throws {
        global.configureLogger()

        // Load configuration
        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: global.configPath)

        // Get state
        let stateStore = SyncStateStore(path: config.state.path)
        try await stateStore.initialize()

        let events = try await stateStore.getAllSyncedEvents()

        if global.json {
            let list = events.values.prefix(options.all ? events.count : options.limit).map { record -> [String: Any] in
                [
                    "uid": record.sourceUID,
                    "calendar_item_id": record.calendarItemId,
                    "content_hash": String(record.contentHash.prefix(8)),
                    "sequence": record.sequence,
                    "synced_at": record.syncedAt.iso8601String
                ]
            }

            if let data = try? JSONSerialization.data(withJSONObject: ["events": list, "total": events.count], options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } else {
            print("Tracked Events (\(events.count) total):")
            print()

            let limit = options.all ? events.count : options.limit
            for (index, record) in events.values.enumerated().prefix(limit) {
                print("  \(index + 1). \(record.sourceUID)")
                print("     Hash: \(record.contentHash.prefix(8))... | Seq: \(record.sequence)")
                print("     Synced: \(record.syncedAt.formatted(style: .short, timeStyle: .short))")
                print()
            }

            if events.count > limit {
                print("  ... and \(events.count - limit) more (use --all to show all)")
            }
        }
    }
}

// MARK: - Calendars Command

struct CalendarsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendars",
        abstract: "List available calendars"
    )

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        global.configureLogger()

        let calendarManager = CalendarManager()

        // Request access if needed
        let hasAccess = await calendarManager.checkAccess()
        if !hasAccess {
            try await calendarManager.requestAccess()
        }

        let grouped = await calendarManager.getCalendarsGroupedBySource()

        if global.json {
            var sources: [[String: Any]] = []
            for (source, calendars) in grouped {
                sources.append([
                    "name": source.title,
                    "type": String(describing: source.sourceType),
                    "calendars": calendars.map { cal -> [String: Any] in
                        [
                            "identifier": cal.calendarIdentifier,
                            "title": cal.title,
                            "writable": cal.allowsContentModifications
                        ]
                    }
                ])
            }

            if let data = try? JSONSerialization.data(withJSONObject: ["sources": sources], options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        } else {
            print("Available Calendars:")
            print()

            for (source, calendars) in grouped {
                print("  \(source.title):")
                for cal in calendars {
                    let writable = cal.allowsContentModifications ? "" : " (read-only)"
                    print("    - \(cal.title)\(writable)")
                }
                print()
            }
        }
    }
}

// MARK: - Reset Command

struct ResetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Reset sync state (requires --force)"
    )

    @OptionGroup var global: GlobalOptions
    @OptionGroup var options: ResetOptions

    mutating func run() async throws {
        global.configureLogger()
        let logger = Logger.shared

        guard options.force else {
            logger.error("Reset requires --force flag to confirm")
            logger.info("This will delete all sync state. Events in calendar will not be affected.")
            throw ExitCode.failure
        }

        // Load configuration
        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: global.configPath)

        // Reset state
        let stateStore = SyncStateStore(path: config.state.path)
        try await stateStore.initialize()
        try await stateStore.reset()

        logger.success("Sync state has been reset")
        logger.info("Next sync will treat all events as new")
    }
}

// MARK: - Install Command

struct InstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install as launchd background service"
    )

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        global.configureLogger()
        let logger = Logger.shared

        // Get executable path
        let executablePath = CommandLine.arguments[0]
        let resolvedPath: String

        if executablePath.hasPrefix("/") {
            resolvedPath = executablePath
        } else {
            // Resolve relative path
            let currentDir = FileManager.default.currentDirectoryPath
            resolvedPath = (currentDir as NSString).appendingPathComponent(executablePath)
        }

        // Validate config exists
        let configPath = global.configPath.expandingTildeInPath
        guard FileManager.default.fileExists(atPath: configPath) else {
            logger.error("Configuration file not found: \(configPath)")
            logger.info("Run 'ics-calendar-sync setup' first")
            throw ExitCode.failure
        }

        // Check if already installed
        if LaunchdGenerator.isInstalled() {
            logger.warning("Service is already installed")
            logger.info("Use 'ics-calendar-sync uninstall' to remove first")
            throw ExitCode.failure
        }

        // Install
        try LaunchdGenerator.install(
            executablePath: resolvedPath,
            configPath: configPath
        )
    }
}

// MARK: - Uninstall Command

struct UninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove launchd background service"
    )

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        global.configureLogger()

        try LaunchdGenerator.uninstall()
    }
}

// MARK: - Setup Command (placeholder - full implementation in SetupWizard)

struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Interactive setup wizard"
    )

    @OptionGroup var global: GlobalOptions
    @OptionGroup var options: SetupOptions

    mutating func run() async throws {
        global.configureLogger()

        if options.nonInteractive {
            try await runNonInteractive()
        } else {
            let wizard = SetupWizard(configPath: global.configPath)
            try await wizard.run()
        }
    }

    private func runNonInteractive() async throws {
        let logger = Logger.shared

        guard let icsUrl = options.icsUrl else {
            logger.error("--ics-url is required in non-interactive mode")
            throw ExitCode.failure
        }

        let calendarName = options.calendar ?? "Subscribed Events"

        // Build configuration
        let config = Configuration.builder()
            .setSourceURL(icsUrl)
            .setCalendarName(calendarName)
            .build()

        // Save configuration
        let configManager = ConfigurationManager.shared
        try await configManager.save(config, to: global.configPath)

        logger.success("Configuration saved to \(global.configPath)")

        // Run initial sync if not skipped
        if !options.skipSync {
            logger.info("Running initial sync...")
            let engine = try SyncEngine(config: config)
            try await engine.initialize()
            let result = try await engine.sync()
            logger.success("Initial sync complete: \(result.created) events created")
        }
    }
}
