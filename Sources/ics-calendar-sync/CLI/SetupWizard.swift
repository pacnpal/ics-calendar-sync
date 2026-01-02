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
        print("When events are removed from the ICS source, should they")
        print("be deleted from your calendar?")
        config.sync.deleteOrphans = promptYesNo("Delete removed events?", defaultValue: true)

        // Date window
        print()
        print("Sync events within a date window? (Recommended for large calendars)")
        let useWindow = promptYesNo("Use date window?", defaultValue: true)

        if useWindow {
            print("Days in the past to sync (default: 30):")
            if let input = readLine()?.trimmed, let days = Int(input), days >= 0 {
                config.sync.windowDaysPast = days
            }

            print("Days in the future to sync (default: 365):")
            if let input = readLine()?.trimmed, let days = Int(input), days >= 0 {
                config.sync.windowDaysFuture = days
            }
        } else {
            config.sync.windowDaysPast = nil
            config.sync.windowDaysFuture = nil
        }

        print()
    }

    // MARK: - Scheduling

    private func configureScheduling() async {
        printSection("Background Sync")

        print("Would you like to set up automatic background syncing?")
        let setupDaemon = promptYesNo("Enable background sync?", defaultValue: true)

        if setupDaemon {
            print()
            print("Sync interval in minutes (default: 15):")
            if let input = readLine()?.trimmed, let minutes = Int(input), minutes >= 1 {
                config.daemon.intervalMinutes = minutes
            }

            print()
            printSuccess("Background sync will run every \(config.daemon.intervalMinutes) minutes")
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

        print("Would you like to receive macOS notifications for sync events?")
        print("(Useful for monitoring sync status when running in background)")
        print()

        let enableNotifications = promptYesNo("Enable notifications?", defaultValue: true)

        if enableNotifications {
            config.notifications.enabled = true

            print()
            print("When should notifications be shown?")
            print()

            // Success notifications
            print("Notify on successful sync? (Shows event counts)")
            config.notifications.onSuccess = promptYesNo("  Sync success", defaultValue: false)

            // Failure notifications
            print("Notify when sync fails? (Shows error message)")
            config.notifications.onFailure = promptYesNo("  Sync failure", defaultValue: true)

            // Partial notifications
            print("Notify on partial sync? (Some events failed)")
            config.notifications.onPartial = promptYesNo("  Partial sync", defaultValue: true)

            // Sound
            print()
            print("Play sound with notifications?")
            let useSound = promptYesNo("Enable notification sound?", defaultValue: true)
            config.notifications.sound = useSound ? "default" : nil

            print()
            printSuccess("Notifications configured")
        } else {
            config.notifications.enabled = false
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
