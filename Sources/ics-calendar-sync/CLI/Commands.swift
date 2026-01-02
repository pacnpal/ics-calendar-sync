import ArgumentParser
import Foundation

// MARK: - Root Command

@main
struct ICSCalendarSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ics-calendar-sync",
        abstract: "Sync ICS calendar subscriptions to macOS Calendar",
        version: "1.0.4",
        subcommands: [
            SetupCommand.self,
            ConfigureCommand.self,
            SyncCommand.self,
            DaemonCommand.self,
            StatusCommand.self,
            StartCommand.self,
            StopCommand.self,
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

// MARK: - Start Command

struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the background service (temporary, until restart)"
    )

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        global.configureLogger()
        let logger = Logger.shared

        // Check if service is installed
        guard LaunchdGenerator.isInstalled() else {
            logger.error("Service is not installed")
            logger.info("Run 'ics-calendar-sync install' first to install the service")
            throw ExitCode.failure
        }

        // Check current status
        let status = LaunchdGenerator.getStatus()
        if case .running = status {
            logger.info("Service is already running")
            return
        }

        // Start the service
        do {
            try LaunchdGenerator.start()
            logger.info("Note: This is temporary and won't persist through system restarts")
        } catch {
            logger.error("Failed to start service: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Stop Command

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the background service (temporary, until restart)"
    )

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        global.configureLogger()
        let logger = Logger.shared

        // Check if service is installed
        guard LaunchdGenerator.isInstalled() else {
            logger.error("Service is not installed")
            throw ExitCode.failure
        }

        // Check current status
        let status = LaunchdGenerator.getStatus()
        if case .stopped = status {
            logger.info("Service is already stopped")
            return
        }
        if case .notInstalled = status {
            logger.info("Service is not running")
            return
        }

        // Stop the service
        do {
            try LaunchdGenerator.stop()
            logger.info("Note: Service will start again on next system restart")
            logger.info("Use 'ics-calendar-sync uninstall' to permanently remove")
        } catch {
            logger.error("Failed to stop service: \(error.localizedDescription)")
            throw ExitCode.failure
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

// MARK: - Configure Command

struct ConfigureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "configure",
        abstract: "Interactively modify configuration settings"
    )

    @OptionGroup var global: GlobalOptions

    // ANSI colors
    private var useColors: Bool { isatty(STDOUT_FILENO) != 0 }
    private var bold: String { useColors ? "\u{001B}[1m" : "" }
    private var green: String { useColors ? "\u{001B}[32m" : "" }
    private var yellow: String { useColors ? "\u{001B}[33m" : "" }
    private var cyan: String { useColors ? "\u{001B}[36m" : "" }
    private var reset: String { useColors ? "\u{001B}[0m" : "" }

    mutating func run() async throws {
        global.configureLogger()
        let logger = Logger.shared

        // Load existing configuration
        let configManager = ConfigurationManager.shared
        var config: Configuration

        let configPath = global.configPath.expandingTildeInPath
        if FileManager.default.fileExists(atPath: configPath) {
            config = try await configManager.load(from: global.configPath)
        } else {
            logger.error("No configuration found at \(configPath)")
            logger.info("Run 'ics-calendar-sync setup' first to create a configuration")
            throw ExitCode.failure
        }

        var hasChanges = false

        while true {
            printMenu(config: config)

            print("\n\(bold)Enter option (1-8, or 'q' to quit):\(reset) ", terminator: "")
            fflush(stdout)

            guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
                continue
            }

            switch input {
            case "1":
                config.source.url = promptString("ICS URL", current: config.source.url)
                hasChanges = true
            case "2":
                config.destination.calendarName = promptString("Calendar name", current: config.destination.calendarName)
                hasChanges = true
            case "3":
                configureSyncOptions(&config)
                hasChanges = true
            case "4":
                config.daemon.intervalMinutes = promptInt("Sync interval (minutes)", current: config.daemon.intervalMinutes, min: 1)
                hasChanges = true
            case "5":
                configureNotifications(&config)
                hasChanges = true
            case "6":
                config.logging.level = promptChoice("Log level", options: ["debug", "info", "warning", "error"], current: config.logging.level)
                hasChanges = true
            case "7":
                // Show current config
                printCurrentConfig(config)
            case "8", "s":
                if hasChanges {
                    try await configManager.save(config, to: global.configPath)
                    logger.success("Configuration saved!")
                } else {
                    print("No changes to save.")
                }
            case "q", "quit", "exit":
                if hasChanges {
                    print("\nYou have unsaved changes.")
                    if promptYesNo("Save before exiting?", defaultValue: true) {
                        try await configManager.save(config, to: global.configPath)
                        logger.success("Configuration saved!")
                    }
                }
                return
            default:
                print("\(yellow)Invalid option. Please try again.\(reset)")
            }
        }
    }

    private func printMenu(config: Configuration) {
        print("\n\(bold)╔════════════════════════════════════════════════════════╗\(reset)")
        print("\(bold)║              Configuration Settings                     ║\(reset)")
        print("\(bold)╚════════════════════════════════════════════════════════╝\(reset)")
        print()
        print("  \(cyan)1.\(reset) ICS Source URL")
        print("     Current: \(truncate(config.source.url, maxLength: 50))")
        print()
        print("  \(cyan)2.\(reset) Target Calendar")
        print("     Current: \(config.destination.calendarName)")
        print()
        print("  \(cyan)3.\(reset) Sync Options")
        print("     Delete orphans: \(config.sync.deleteOrphans ? "Yes" : "No"), Window: \(formatWindow(config))")
        print()
        print("  \(cyan)4.\(reset) Sync Interval")
        print("     Current: \(config.daemon.intervalMinutes) minutes")
        print()
        print("  \(cyan)5.\(reset) Notifications")
        print("     \(formatNotifications(config))")
        print()
        print("  \(cyan)6.\(reset) Log Level")
        print("     Current: \(config.logging.level)")
        print()
        print("  \(cyan)7.\(reset) Show Full Configuration")
        print("  \(cyan)8.\(reset) Save Changes")
        print("  \(cyan)q.\(reset) Quit")
    }

    private func configureSyncOptions(_ config: inout Configuration) {
        print("\n\(bold)[Sync Options]\(reset)")

        // Delete orphans
        print()
        print("When events are removed from ICS source:")
        print("  \(cyan)1.\(reset) Delete them from calendar")
        print("  \(cyan)2.\(reset) Keep them in calendar")
        let currentOrphan = config.sync.deleteOrphans ? "1" : "2"
        print("Select option [\(currentOrphan)]: ", terminator: "")
        fflush(stdout)
        let orphanChoice = readLine()?.trimmingCharacters(in: .whitespaces) ?? currentOrphan
        config.sync.deleteOrphans = (orphanChoice.isEmpty ? currentOrphan : orphanChoice) != "2"

        // Date window
        print()
        print("Sync window:")
        print("  \(cyan)1.\(reset) Standard - 30 days past, 1 year future")
        print("  \(cyan)2.\(reset) Short - 7 days past, 3 months future")
        print("  \(cyan)3.\(reset) Long - 1 year past, 2 years future")
        print("  \(cyan)4.\(reset) All events - No date limits")
        print("  \(cyan)5.\(reset) Custom")

        let currentWindow: String
        if config.sync.windowDaysPast == nil {
            currentWindow = "4"
        } else if config.sync.windowDaysPast == 7 && config.sync.windowDaysFuture == 90 {
            currentWindow = "2"
        } else if config.sync.windowDaysPast == 365 && config.sync.windowDaysFuture == 730 {
            currentWindow = "3"
        } else if config.sync.windowDaysPast == 30 && config.sync.windowDaysFuture == 365 {
            currentWindow = "1"
        } else {
            currentWindow = "5"
        }

        print("Select option [\(currentWindow)]: ", terminator: "")
        fflush(stdout)
        let windowChoice = readLine()?.trimmingCharacters(in: .whitespaces) ?? currentWindow

        switch windowChoice.isEmpty ? currentWindow : windowChoice {
        case "1":
            config.sync.windowDaysPast = 30
            config.sync.windowDaysFuture = 365
        case "2":
            config.sync.windowDaysPast = 7
            config.sync.windowDaysFuture = 90
        case "3":
            config.sync.windowDaysPast = 365
            config.sync.windowDaysFuture = 730
        case "4":
            config.sync.windowDaysPast = nil
            config.sync.windowDaysFuture = nil
        case "5":
            config.sync.windowDaysPast = promptInt("Days in the past", current: config.sync.windowDaysPast ?? 30, min: 0)
            config.sync.windowDaysFuture = promptInt("Days in the future", current: config.sync.windowDaysFuture ?? 365, min: 0)
        default:
            break
        }

        // Alarms
        print()
        print("Sync event alarms/reminders:")
        print("  \(cyan)1.\(reset) Yes - Sync alarms")
        print("  \(cyan)2.\(reset) No - Ignore alarms")
        let currentAlarm = config.sync.syncAlarms ? "1" : "2"
        print("Select option [\(currentAlarm)]: ", terminator: "")
        fflush(stdout)
        let alarmChoice = readLine()?.trimmingCharacters(in: .whitespaces) ?? currentAlarm
        config.sync.syncAlarms = (alarmChoice.isEmpty ? currentAlarm : alarmChoice) != "2"

        print("\(green)✓\(reset) Sync options updated")
    }

    private func configureNotifications(_ config: inout Configuration) {
        print("\n\(bold)[Notification Settings]\(reset)")
        print()
        print("Choose notification level:")
        print()
        print("  \(cyan)1.\(reset) Off - No notifications")
        print("  \(cyan)2.\(reset) Errors only - Notify on failures")
        print("  \(cyan)3.\(reset) Errors & warnings - Notify on failures and partial syncs")
        print("  \(cyan)4.\(reset) All - Notify on every sync")
        print()

        // Show current setting
        let currentLevel: String
        if !config.notifications.enabled {
            currentLevel = "1"
        } else if config.notifications.onSuccess {
            currentLevel = "4"
        } else if config.notifications.onPartial {
            currentLevel = "3"
        } else {
            currentLevel = "2"
        }

        print("Select option [\(currentLevel)]: ", terminator: "")
        fflush(stdout)

        let choice = readLine()?.trimmingCharacters(in: .whitespaces) ?? currentLevel

        switch choice.isEmpty ? currentLevel : choice {
        case "1":
            config.notifications.enabled = false
            config.notifications.onSuccess = false
            config.notifications.onFailure = false
            config.notifications.onPartial = false
        case "2":
            config.notifications.enabled = true
            config.notifications.onSuccess = false
            config.notifications.onFailure = true
            config.notifications.onPartial = false
        case "3":
            config.notifications.enabled = true
            config.notifications.onSuccess = false
            config.notifications.onFailure = true
            config.notifications.onPartial = true
        case "4":
            config.notifications.enabled = true
            config.notifications.onSuccess = true
            config.notifications.onFailure = true
            config.notifications.onPartial = true
        default:
            break  // Keep current
        }

        if config.notifications.enabled {
            print()
            print("Notification sound:")
            print("  \(cyan)1.\(reset) Default system sound")
            print("  \(cyan)2.\(reset) Silent (no sound)")
            let currentSound = config.notifications.sound != nil ? "1" : "2"
            print("Select option [\(currentSound)]: ", terminator: "")
            fflush(stdout)

            let soundChoice = readLine()?.trimmingCharacters(in: .whitespaces) ?? currentSound
            config.notifications.sound = (soundChoice == "2") ? nil : "default"
        }

        print("\(green)✓\(reset) Notification settings updated")
    }

    private func printCurrentConfig(_ config: Configuration) {
        print("\n\(bold)Current Configuration:\(reset)")
        print(String(repeating: "-", count: 50))
        print()
        print("Source:")
        print("  URL: \(config.source.url)")
        print("  Timeout: \(config.source.timeout)s")
        print("  Verify SSL: \(config.source.verifySSL)")
        print()
        print("Destination:")
        print("  Calendar: \(config.destination.calendarName)")
        print("  Create if missing: \(config.destination.createIfMissing)")
        print("  Source preference: \(config.destination.sourcePreference)")
        print()
        print("Sync:")
        print("  Delete orphans: \(config.sync.deleteOrphans)")
        print("  Sync alarms: \(config.sync.syncAlarms)")
        if let past = config.sync.windowDaysPast, let future = config.sync.windowDaysFuture {
            print("  Date window: \(past) days past, \(future) days future")
        } else {
            print("  Date window: All events")
        }
        print()
        print("Daemon:")
        print("  Interval: \(config.daemon.intervalMinutes) minutes")
        print()
        print("Notifications:")
        print("  Enabled: \(config.notifications.enabled)")
        if config.notifications.enabled {
            print("  On success: \(config.notifications.onSuccess)")
            print("  On failure: \(config.notifications.onFailure)")
            print("  On partial: \(config.notifications.onPartial)")
            print("  Sound: \(config.notifications.sound ?? "none")")
        }
        print()
        print("Logging:")
        print("  Level: \(config.logging.level)")
        print("  Format: \(config.logging.format)")
        print()
        print("Press Enter to continue...")
        _ = readLine()
    }

    // MARK: - Helpers

    private func promptString(_ prompt: String, current: String) -> String {
        print("\(prompt) [\(truncate(current, maxLength: 40))]:")
        print("(Press Enter to keep current, or enter new value)")
        print("> ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
            return current
        }
        return input
    }

    private func promptInt(_ prompt: String, current: Int, min: Int = 0) -> Int {
        print("\(prompt) [\(current)]:")
        print("> ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces),
              !input.isEmpty,
              let value = Int(input),
              value >= min else {
            return current
        }
        return value
    }

    private func promptChoice(_ prompt: String, options: [String], current: String) -> String {
        print("\(prompt):")
        for (index, option) in options.enumerated() {
            let marker = option == current ? " (current)" : ""
            print("  \(index + 1). \(option)\(marker)")
        }
        print("> ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces),
              let index = Int(input),
              index >= 1 && index <= options.count else {
            return current
        }
        return options[index - 1]
    }

    private func promptYesNo(_ prompt: String, defaultValue: Bool) -> Bool {
        let defaultStr = defaultValue ? "[Y/n]" : "[y/N]"
        print("\(prompt) \(defaultStr): ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return defaultValue
        }

        if input.isEmpty {
            return defaultValue
        }

        return input == "y" || input == "yes"
    }

    private func truncate(_ str: String, maxLength: Int) -> String {
        if str.count <= maxLength {
            return str
        }
        return String(str.prefix(maxLength - 3)) + "..."
    }

    private func formatWindow(_ config: Configuration) -> String {
        if let past = config.sync.windowDaysPast, let future = config.sync.windowDaysFuture {
            return "\(past)d past, \(future)d future"
        }
        return "All events"
    }

    private func formatNotifications(_ config: Configuration) -> String {
        if !config.notifications.enabled {
            return "Disabled"
        }
        var triggers: [String] = []
        if config.notifications.onSuccess { triggers.append("success") }
        if config.notifications.onFailure { triggers.append("failure") }
        if config.notifications.onPartial { triggers.append("partial") }
        if triggers.isEmpty { return "Enabled (no triggers)" }
        return triggers.joined(separator: ", ") + (config.notifications.sound != nil ? " (with sound)" : "")
    }
}
