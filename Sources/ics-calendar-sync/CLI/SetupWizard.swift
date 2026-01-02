import Foundation
import EventKit

// MARK: - Setup Wizard

/// Interactive setup wizard for configuring the sync tool
actor SetupWizard {
    private let configPath: String
    private let logger = Logger.shared
    private let calendarManager = CalendarManager()
    private let icsFetcher = ICSFetcher()
    private let icsParser = ICSParser()

    private var config = Configuration()

    // ANSI colors
    private let useColors = isatty(STDOUT_FILENO) != 0
    private var bold: String { useColors ? "\u{001B}[1m" : "" }
    private var green: String { useColors ? "\u{001B}[32m" : "" }
    private var yellow: String { useColors ? "\u{001B}[33m" : "" }
    private var cyan: String { useColors ? "\u{001B}[36m" : "" }
    private var reset: String { useColors ? "\u{001B}[0m" : "" }

    init(configPath: String) {
        self.configPath = configPath
    }

    // MARK: - Main Flow

    func run() async throws {
        printWelcome()

        // Step 1: Check prerequisites
        try await checkPrerequisites()

        // Step 2: Request calendar access
        try await requestCalendarAccess()

        // Step 3: Configure ICS source
        try await configureICSSource()

        // Step 4: Select calendar
        try await selectCalendar()

        // Step 5: Configure sync options
        await configureSyncOptions()

        // Step 6: Configure scheduling
        await configureScheduling()

        // Step 7: Configure notifications
        await configureNotifications()

        // Step 8: Review and save
        try await reviewAndSave()

        // Step 9: Initial sync
        try await runInitialSync()

        // Step 10: Completion
        printCompletion()
    }

    // MARK: - Welcome

    private func printWelcome() {
        print()
        print("\(bold)╔══════════════════════════════════════════════════════════╗\(reset)")
        print("\(bold)║          ICS Calendar Sync - Setup Wizard                 ║\(reset)")
        print("\(bold)╚══════════════════════════════════════════════════════════╝\(reset)")
        print()
        print("This wizard will help you configure ICS calendar synchronization.")
        print("Your ICS events will sync to your Mac's Calendar app via iCloud.")
        print()
        print("Press Ctrl+C at any time to cancel.")
        print()
    }

    // MARK: - Prerequisites

    private func checkPrerequisites() async throws {
        printSection("Checking Prerequisites")

        // Check macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(osVersion.majorVersion).\(osVersion.minorVersion)"

        if osVersion.majorVersion >= 13 {
            printSuccess("macOS \(versionString) - Compatible")
        } else {
            printFailure("macOS \(versionString) - Requires macOS 13.0 or later")
            throw SetupError.permissionDenied
        }

        // Check for existing config
        let expandedPath = configPath.expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            printWarning("Existing configuration found at \(expandedPath)")
            let overwrite = promptYesNo("Do you want to overwrite it?", defaultValue: false)
            if !overwrite {
                throw SetupError.cancelled
            }
        }

        print()
    }

    // MARK: - Calendar Access

    private func requestCalendarAccess() async throws {
        printSection("Calendar Access")

        print("This tool needs access to your calendars to sync events.")
        print("You'll see a system permission dialog.")
        print()

        let hasAccess = await calendarManager.checkAccess()
        if hasAccess {
            printSuccess("Calendar access already granted")
        } else {
            printProgress("Requesting calendar access...")

            do {
                try await calendarManager.requestAccess()
                printSuccess("Calendar access granted")
            } catch {
                printFailure("Calendar access denied")
                print()
                print("To grant access:")
                print("  1. Open System Settings")
                print("  2. Go to Privacy & Security > Calendars")
                print("  3. Enable access for this terminal/app")
                print()
                throw SetupError.calendarAccessFailed
            }
        }

        print()
    }

    // MARK: - ICS Source

    private func configureICSSource() async throws {
        printSection("ICS Source Configuration")

        // Get URL
        var validUrl: URL?
        while validUrl == nil {
            print("Enter your ICS subscription URL:")
            guard let input = readLine()?.trimmed, !input.isEmpty else {
                printWarning("URL cannot be empty")
                continue
            }

            guard let url = URL(string: input), url.scheme != nil else {
                printWarning("Invalid URL format")
                continue
            }

            validUrl = url
        }

        config.source.url = validUrl!.absoluteString

        // Test the URL
        printProgress("Testing connection...")

        var fetchConfig = ICSFetcher.FetchConfig()

        do {
            let validation = try await icsFetcher.validate(url: validUrl!, config: fetchConfig)

            if validation.isValid {
                printSuccess("Connected successfully!")
                print("  Found \(validation.eventCount) events")

                if let range = validation.dateRange {
                    print("  Date range: \(range.earliest.formatted(style: .short, timeStyle: .none)) to \(range.latest.formatted(style: .short, timeStyle: .none))")
                }

                // Show sample events
                if !validation.sampleEvents.isEmpty {
                    print()
                    print("Sample events:")
                    for event in validation.sampleEvents.prefix(3) {
                        print("  - \(event.displayTitle) (\(event.startDate.formatted(style: .short, timeStyle: .short)))")
                    }
                }
            } else {
                throw validation.error ?? ICSError.parseError("Unknown error")
            }
        } catch ICSError.authenticationRequired {
            printWarning("Authentication required")
            try await configureAuthentication(&fetchConfig)

            // Retry with auth
            let validation = try await icsFetcher.validate(url: validUrl!, config: fetchConfig)
            if validation.isValid {
                printSuccess("Authentication successful! Found \(validation.eventCount) events")
            } else {
                throw validation.error ?? SetupError.networkTestFailed(ICSError.authenticationRequired)
            }
        } catch {
            printFailure("Failed to connect: \(error.localizedDescription)")
            throw SetupError.networkTestFailed(error)
        }

        print()
    }

    private func configureAuthentication(_ config: inout ICSFetcher.FetchConfig) async throws {
        print()
        print("Select authentication method:")
        print("  1. Bearer Token")
        print("  2. Basic Auth (username/password)")
        print("  3. Cancel")

        guard let choice = readLine()?.trimmed else {
            throw SetupError.cancelled
        }

        switch choice {
        case "1":
            print("Enter your Bearer token:")
            guard let token = readLine()?.trimmed, !token.isEmpty else {
                throw SetupError.invalidInput("Token cannot be empty")
            }

            config.headers["Authorization"] = "Bearer \(token)"
            self.config.source.headers["Authorization"] = "Bearer ${ICS_AUTH_TOKEN}"

            // Offer to save to keychain
            let saveToKeychain = promptYesNo("Save token to macOS Keychain?", defaultValue: true)
            if saveToKeychain {
                try KeychainHelper.saveAuthToken(token)
                printSuccess("Token saved to Keychain")
            }

        case "2":
            print("Enter username:")
            guard let username = readLine()?.trimmed, !username.isEmpty else {
                throw SetupError.invalidInput("Username cannot be empty")
            }

            print("Enter password:")
            guard let password = readSecureLine(), !password.isEmpty else {
                throw SetupError.invalidInput("Password cannot be empty")
            }

            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let encoded = data.base64EncodedString()
                config.headers["Authorization"] = "Basic \(encoded)"
                self.config.source.headers["Authorization"] = "Basic ${ICS_BASIC_AUTH}"
            }

            // Offer to save to keychain
            let saveToKeychain = promptYesNo("Save credentials to macOS Keychain?", defaultValue: true)
            if saveToKeychain {
                try KeychainHelper.saveBasicAuth(username: username, password: password)
                printSuccess("Credentials saved to Keychain")
            }

        default:
            throw SetupError.cancelled
        }
    }

    // MARK: - Calendar Selection

    private func selectCalendar() async throws {
        printSection("Calendar Selection")

        let grouped = await calendarManager.getCalendarsGroupedBySource()

        print("Available calendars:")
        print()

        var calendarList: [EKCalendar] = []
        var index = 1

        for (source, calendars) in grouped {
            print("  \(cyan)\(source.title)\(reset)")
            for calendar in calendars where calendar.allowsContentModifications {
                print("    \(index). \(calendar.title)")
                calendarList.append(calendar)
                index += 1
            }
        }

        print()
        print("    \(index). Create new calendar")
        print()

        print("Select a calendar (1-\(index)):")
        guard let input = readLine()?.trimmed,
              let selection = Int(input),
              selection >= 1 && selection <= index else {
            // Default to creating new calendar
            try await createNewCalendar()
            return
        }

        if selection == index {
            try await createNewCalendar()
        } else {
            let calendar = calendarList[selection - 1]
            config.destination.calendarName = calendar.title
            printSuccess("Selected: \(calendar.title)")
        }

        print()
    }

    private func createNewCalendar() async throws {
        print("Enter name for new calendar:")
        let name = readLine()?.trimmed ?? "Subscribed Events"

        config.destination.calendarName = name.isEmpty ? "Subscribed Events" : name
        config.destination.createIfMissing = true

        print("Select calendar source:")
        print("  1. iCloud (Recommended - syncs to all devices)")
        print("  2. Local (This Mac only)")

        let choice = readLine()?.trimmed ?? "1"
        config.destination.sourcePreference = choice == "2" ? "local" : "icloud"

        printSuccess("Will create calendar: \(config.destination.calendarName)")
    }

    // MARK: - Sync Options

    private func configureSyncOptions() async {
        printSection("Sync Options")

        // Delete orphans
        print("When events are removed from the ICS source:")
        print()
        print("  \(cyan)1.\(reset) Delete them from calendar (Recommended)")
        print("  \(cyan)2.\(reset) Keep them in calendar")
        print()
        print("Select option [1]: ", terminator: "")
        fflush(stdout)

        let orphanChoice = readLine()?.trimmed ?? "1"
        config.sync.deleteOrphans = (orphanChoice != "2")

        // Date window
        print()
        print("Sync window (limits which events to sync):")
        print()
        print("  \(cyan)1.\(reset) Standard - 30 days past, 1 year future (Recommended)")
        print("  \(cyan)2.\(reset) Short - 7 days past, 3 months future")
        print("  \(cyan)3.\(reset) Long - 1 year past, 2 years future")
        print("  \(cyan)4.\(reset) All events - No date limits")
        print("  \(cyan)5.\(reset) Custom - Enter your own values")
        print()
        print("Select option [1]: ", terminator: "")
        fflush(stdout)

        let windowChoice = readLine()?.trimmed ?? "1"

        switch windowChoice {
        case "1", "":
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
            print("Days in the past [30]: ", terminator: "")
            fflush(stdout)
            if let input = readLine()?.trimmed, let days = Int(input), days >= 0 {
                config.sync.windowDaysPast = days
            } else {
                config.sync.windowDaysPast = 30
            }

            print("Days in the future [365]: ", terminator: "")
            fflush(stdout)
            if let input = readLine()?.trimmed, let days = Int(input), days >= 0 {
                config.sync.windowDaysFuture = days
            } else {
                config.sync.windowDaysFuture = 365
            }
        default:
            config.sync.windowDaysPast = 30
            config.sync.windowDaysFuture = 365
        }

        print()
    }

    // MARK: - Scheduling

    private func configureScheduling() async {
        printSection("Background Sync")

        print("Automatic background sync keeps your calendar up to date.")
        print()
        print("Sync frequency:")
        print()
        print("  \(cyan)1.\(reset) Every 15 minutes (Recommended)")
        print("  \(cyan)2.\(reset) Every 30 minutes")
        print("  \(cyan)3.\(reset) Every hour")
        print("  \(cyan)4.\(reset) Every 2 hours")
        print("  \(cyan)5.\(reset) Manual only - No automatic sync")
        print("  \(cyan)6.\(reset) Custom interval")
        print()
        print("Select option [1]: ", terminator: "")
        fflush(stdout)

        let intervalChoice = readLine()?.trimmed ?? "1"

        switch intervalChoice {
        case "1", "":
            config.daemon.intervalMinutes = 15
            printSuccess("Sync every 15 minutes")
        case "2":
            config.daemon.intervalMinutes = 30
            printSuccess("Sync every 30 minutes")
        case "3":
            config.daemon.intervalMinutes = 60
            printSuccess("Sync every hour")
        case "4":
            config.daemon.intervalMinutes = 120
            printSuccess("Sync every 2 hours")
        case "5":
            config.daemon.intervalMinutes = 0  // Signal for manual only
            printSuccess("Manual sync only")
        case "6":
            print("Enter interval in minutes [15]: ", terminator: "")
            fflush(stdout)
            if let input = readLine()?.trimmed, let minutes = Int(input), minutes >= 1 {
                config.daemon.intervalMinutes = minutes
            } else {
                config.daemon.intervalMinutes = 15
            }
            printSuccess("Sync every \(config.daemon.intervalMinutes) minutes")
        default:
            config.daemon.intervalMinutes = 15
            printSuccess("Sync every 15 minutes")
        }

        if config.daemon.intervalMinutes > 0 {
            print()
            print("After setup, run:")
            print("  \(cyan)ics-calendar-sync install\(reset)")
            print("to enable the background service.")
        }

        print()
    }

    // MARK: - Notifications

    private func configureNotifications() async {
        printSection("Notifications")

        print("macOS notifications help you monitor sync status when running")
        print("in the background. Choose a notification level:")
        print()
        print("  \(cyan)1.\(reset) Off - No notifications")
        print("  \(cyan)2.\(reset) Errors only - Notify on failures (Recommended)")
        print("  \(cyan)3.\(reset) Errors & warnings - Notify on failures and partial syncs")
        print("  \(cyan)4.\(reset) All - Notify on every sync (success, partial, failure)")
        print()
        print("Select option [2]: ", terminator: "")
        fflush(stdout)

        let choice = readLine()?.trimmed ?? "2"

        switch choice {
        case "1":
            config.notifications.enabled = false
            printSuccess("Notifications disabled")
        case "2", "":
            config.notifications.enabled = true
            config.notifications.onSuccess = false
            config.notifications.onFailure = true
            config.notifications.onPartial = false
            printSuccess("Notifications: errors only")
        case "3":
            config.notifications.enabled = true
            config.notifications.onSuccess = false
            config.notifications.onFailure = true
            config.notifications.onPartial = true
            printSuccess("Notifications: errors & warnings")
        case "4":
            config.notifications.enabled = true
            config.notifications.onSuccess = true
            config.notifications.onFailure = true
            config.notifications.onPartial = true
            printSuccess("Notifications: all events")
        default:
            // Default to errors only
            config.notifications.enabled = true
            config.notifications.onSuccess = false
            config.notifications.onFailure = true
            config.notifications.onPartial = false
            printSuccess("Notifications: errors only")
        }

        if config.notifications.enabled {
            print()
            print("Notification sound:")
            print("  \(cyan)1.\(reset) Default system sound (Recommended)")
            print("  \(cyan)2.\(reset) Silent (no sound)")
            print()
            print("Select option [1]: ", terminator: "")
            fflush(stdout)

            let soundChoice = readLine()?.trimmed ?? "1"
            config.notifications.sound = (soundChoice == "2") ? nil : "default"
        }

        print()
    }

    // MARK: - Review and Save

    private func reviewAndSave() async throws {
        printSection("Configuration Summary")

        print("Source URL:       \(config.source.url)")
        print("Calendar:         \(config.destination.calendarName)")
        print("Delete Orphans:   \(config.sync.deleteOrphans ? "Yes" : "No")")

        if let past = config.sync.windowDaysPast, let future = config.sync.windowDaysFuture {
            print("Date Window:      \(past) days past, \(future) days future")
        } else {
            print("Date Window:      All events")
        }

        print("Sync Interval:    \(config.daemon.intervalMinutes) minutes")

        // Notification summary
        if config.notifications.enabled {
            var triggers: [String] = []
            if config.notifications.onSuccess { triggers.append("success") }
            if config.notifications.onFailure { triggers.append("failure") }
            if config.notifications.onPartial { triggers.append("partial") }
            let triggerStr = triggers.isEmpty ? "none" : triggers.joined(separator: ", ")
            print("Notifications:    \(triggerStr)\(config.notifications.sound != nil ? " (with sound)" : "")")
        } else {
            print("Notifications:    Disabled")
        }

        print()
        print("Config File:      \(configPath.expandingTildeInPath)")
        print()

        let confirm = promptYesNo("Save this configuration?", defaultValue: true)

        if !confirm {
            throw SetupError.cancelled
        }

        // Save configuration
        let configManager = ConfigurationManager.shared
        try await configManager.save(config, to: configPath)

        printSuccess("Configuration saved!")
        print()
    }

    // MARK: - Initial Sync

    private func runInitialSync() async throws {
        printSection("Initial Sync")

        let runSync = promptYesNo("Run initial sync now?", defaultValue: true)

        if !runSync {
            print("You can run sync later with: ics-calendar-sync sync")
            return
        }

        printProgress("Syncing events...")

        let engine = try SyncEngine(config: config)
        try await engine.initialize()
        let result = try await engine.sync()

        print()
        printSuccess("Sync complete!")
        print("  Created: \(result.created) events")
        print("  Updated: \(result.updated) events")

        if !result.errors.isEmpty {
            printWarning("\(result.errors.count) errors occurred")
        }

        print()
    }

    // MARK: - Completion

    private func printCompletion() {
        print("\(bold)╔══════════════════════════════════════════════════════════╗\(reset)")
        print("\(bold)║                    Setup Complete!                        ║\(reset)")
        print("\(bold)╚══════════════════════════════════════════════════════════╝\(reset)")
        print()
        print("Quick Reference:")
        print()
        print("  \(cyan)ics-calendar-sync sync\(reset)        Run a manual sync")
        print("  \(cyan)ics-calendar-sync status\(reset)      Check sync status")
        print("  \(cyan)ics-calendar-sync daemon\(reset)      Run in foreground")
        print("  \(cyan)ics-calendar-sync install\(reset)     Install background service")
        print()
        print("View logs:")
        print("  \(cyan)log show --predicate 'subsystem == \"com.ics-calendar-sync\"' --last 1h\(reset)")
        print()
    }

    // MARK: - Helpers

    private func printSection(_ title: String) {
        print("\(bold)[\(title)]\(reset)")
        print(String(repeating: "-", count: 50))
        print()
    }

    private func printProgress(_ message: String) {
        print("  → \(message)")
    }

    private func printSuccess(_ message: String) {
        print("  \(green)✓\(reset) \(message)")
    }

    private func printFailure(_ message: String) {
        print("  \(useColors ? "\u{001B}[31m" : "")✗\(reset) \(message)")
    }

    private func printWarning(_ message: String) {
        print("  \(yellow)!\(reset) \(message)")
    }

    private func promptYesNo(_ prompt: String, defaultValue: Bool) -> Bool {
        let defaultStr = defaultValue ? "[Y/n]" : "[y/N]"
        print("\(prompt) \(defaultStr): ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmed.lowercased() else {
            return defaultValue
        }

        if input.isEmpty {
            return defaultValue
        }

        return input == "y" || input == "yes"
    }

    private func readSecureLine() -> String? {
        // Disable echo for password input
        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)

        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

        let line = readLine()

        // Restore echo
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        print() // New line after hidden input

        return line
    }
}
