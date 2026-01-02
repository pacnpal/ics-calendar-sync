import Foundation

// MARK: - Launchd Generator

/// Generates and manages launchd plist files for background scheduling
enum LaunchdGenerator {
    /// Service identifier
    static let serviceLabel = "com.ics-calendar-sync"

    /// Default plist path
    static var defaultPlistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(serviceLabel).plist"
    }

    /// Default log directory
    static var defaultLogDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Logs/ics-calendar-sync"
    }

    // MARK: - Generation

    /// Generate plist content
    static func generatePlist(
        executablePath: String,
        configPath: String,
        logDir: String? = nil
    ) -> String {
        let logDirectory = logDir ?? defaultLogDir

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(serviceLabel)</string>

            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
                <string>daemon</string>
                <string>--config</string>
                <string>\(configPath)</string>
            </array>

            <key>RunAtLoad</key>
            <true/>

            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>

            <key>StandardOutPath</key>
            <string>\(logDirectory)/stdout.log</string>

            <key>StandardErrorPath</key>
            <string>\(logDirectory)/stderr.log</string>

            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
            </dict>

            <key>ProcessType</key>
            <string>Background</string>

            <key>LowPriorityBackgroundIO</key>
            <true/>

            <key>ThrottleInterval</key>
            <integer>60</integer>
        </dict>
        </plist>
        """
    }

    // MARK: - Installation

    /// Install the launchd service
    static func install(
        executablePath: String,
        configPath: String,
        plistPath: String? = nil,
        logDir: String? = nil
    ) throws {
        let logger = Logger.shared
        let plist = plistPath ?? defaultPlistPath
        let logDirectory = logDir ?? defaultLogDir

        // Create log directory
        try FileManager.default.createDirectoryIfNeeded(atPath: logDirectory)

        // Create LaunchAgents directory if needed
        let launchAgentsDir = (plist as NSString).deletingLastPathComponent
        try FileManager.default.createDirectoryIfNeeded(atPath: launchAgentsDir)

        // Generate plist content
        let content = generatePlist(
            executablePath: executablePath,
            configPath: configPath,
            logDir: logDirectory
        )

        // Write plist file
        try content.write(toFile: plist, atomically: true, encoding: .utf8)
        logger.info("Created plist at \(plist)")

        // Load the service
        let loadResult = shell("launchctl load \(plist)")
        if loadResult.exitCode != 0 {
            throw LaunchdError.loadFailed(loadResult.output)
        }

        logger.success("Service installed and started")
        logger.info("View logs: tail -f \(logDirectory)/stdout.log")
    }

    /// Uninstall the launchd service
    static func uninstall(plistPath: String? = nil) throws {
        let logger = Logger.shared
        let plist = plistPath ?? defaultPlistPath

        // Check if plist exists
        guard FileManager.default.fileExists(atPath: plist) else {
            throw LaunchdError.notInstalled
        }

        // Unload the service
        let unloadResult = shell("launchctl unload \(plist)")
        if unloadResult.exitCode != 0 && !unloadResult.output.contains("Could not find") {
            throw LaunchdError.unloadFailed(unloadResult.output)
        }

        // Remove plist file
        try FileManager.default.removeItem(atPath: plist)
        logger.info("Removed plist at \(plist)")

        logger.success("Service uninstalled")
    }

    // MARK: - Status

    /// Check if service is installed
    static func isInstalled(plistPath: String? = nil) -> Bool {
        let plist = plistPath ?? defaultPlistPath
        return FileManager.default.fileExists(atPath: plist)
    }

    /// Check if service is running
    static func isRunning() -> Bool {
        let result = shell("launchctl list | grep \(serviceLabel)")
        return result.exitCode == 0 && !result.output.isEmpty
    }

    /// Get service status
    static func getStatus() -> ServiceStatus {
        let installed = isInstalled()
        let running = isRunning()

        if !installed {
            return .notInstalled
        } else if running {
            return .running
        } else {
            return .stopped
        }
    }

    enum ServiceStatus {
        case notInstalled
        case running
        case stopped

        var description: String {
            switch self {
            case .notInstalled: return "Not installed"
            case .running: return "Running"
            case .stopped: return "Stopped (installed but not running)"
            }
        }
    }

    // MARK: - Control

    /// Start the service
    static func start(plistPath: String? = nil) throws {
        let plist = plistPath ?? defaultPlistPath

        guard isInstalled(plistPath: plist) else {
            throw LaunchdError.notInstalled
        }

        let result = shell("launchctl load \(plist)")
        if result.exitCode != 0 {
            throw LaunchdError.loadFailed(result.output)
        }
    }

    /// Stop the service
    static func stop(plistPath: String? = nil) throws {
        let plist = plistPath ?? defaultPlistPath

        guard isInstalled(plistPath: plist) else {
            throw LaunchdError.notInstalled
        }

        let result = shell("launchctl unload \(plist)")
        if result.exitCode != 0 {
            throw LaunchdError.unloadFailed(result.output)
        }
    }

    /// Restart the service
    static func restart(plistPath: String? = nil) throws {
        try stop(plistPath: plistPath)
        try start(plistPath: plistPath)
    }

    // MARK: - Helper

    private static func shell(_ command: String) -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ("Failed to execute: \(error)", -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return (output.trimmingCharacters(in: .whitespacesAndNewlines), task.terminationStatus)
    }
}

// MARK: - Launchd Errors

enum LaunchdError: LocalizedError {
    case notInstalled
    case loadFailed(String)
    case unloadFailed(String)
    case alreadyInstalled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Service is not installed"
        case .loadFailed(let output):
            return "Failed to load service: \(output)"
        case .unloadFailed(let output):
            return "Failed to unload service: \(output)"
        case .alreadyInstalled:
            return "Service is already installed"
        }
    }
}
