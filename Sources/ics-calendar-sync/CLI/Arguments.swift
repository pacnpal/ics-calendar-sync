import ArgumentParser
import Foundation

// MARK: - Global Options

/// Global options shared across all commands
struct GlobalOptions: ParsableArguments {
    @Option(name: [.short, .customLong("config")], help: "Configuration file path")
    var configPath: String = ConfigurationManager.defaultConfigPath

    @Flag(name: .shortAndLong, help: "Increase verbosity (can be repeated)")
    var verbose: Int

    @Flag(name: .shortAndLong, help: "Suppress non-error output")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show what would happen without making changes")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Output in JSON format")
    var json: Bool = false

    /// Configure logger based on options
    func configureLogger() {
        let logger = Logger.shared

        // Set log level based on verbosity
        if quiet {
            logger.level = .error
            logger.quiet = true
        } else {
            switch verbose {
            case 0: logger.level = .info
            case 1: logger.level = .debug
            default: logger.level = .debug
            }
        }

        // Set output format
        if json {
            logger.format = .json
        }
    }
}

// MARK: - Sync Options

/// Options specific to sync command
struct SyncOptions: ParsableArguments {
    @Flag(name: .long, help: "Force full sync, ignoring existing state")
    var full: Bool = false
}

// MARK: - Daemon Options

/// Options specific to daemon command
struct DaemonOptions: ParsableArguments {
    @Option(name: .long, help: "Override sync interval (minutes)")
    var interval: Int?
}

// MARK: - Setup Options

/// Options specific to setup command
struct SetupOptions: ParsableArguments {
    @Flag(name: .long, help: "Use defaults and flags instead of interactive prompts")
    var nonInteractive: Bool = false

    @Option(name: .long, help: "ICS subscription URL")
    var icsUrl: String?

    @Option(name: .long, help: "Target calendar name")
    var calendar: String?

    @Flag(name: .long, help: "Skip initial sync after setup")
    var skipSync: Bool = false
}

// MARK: - Reset Options

/// Options specific to reset command
struct ResetOptions: ParsableArguments {
    @Flag(name: .long, help: "Required to confirm reset")
    var force: Bool = false
}

// MARK: - List Options

/// Options specific to list command
struct ListOptions: ParsableArguments {
    @Option(name: .short, help: "Maximum number of events to show")
    var limit: Int = 20

    @Flag(name: .long, help: "Show all events")
    var all: Bool = false
}
