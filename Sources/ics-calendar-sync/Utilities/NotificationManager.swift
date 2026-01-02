import Foundation

// MARK: - NotificationManager

/// Manages macOS notifications using osascript
/// Uses the built-in `display notification` AppleScript command
actor NotificationManager {
    static let shared = NotificationManager()

    private let logger = Logger.shared

    private init() {}

    // MARK: - Public Methods

    /// Send a macOS notification
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification body text
    ///   - sound: Optional sound name (from /System/Library/Sounds or ~/Library/Sounds), nil for no sound
    func send(title: String, message: String, sound: String? = "default") async {
        let escapedTitle = escapeForAppleScript(title)
        let escapedMessage = escapeForAppleScript(message)

        var script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\""

        if let sound = sound {
            let escapedSound = escapeForAppleScript(sound)
            script += " sound name \"\(escapedSound)\""
        }

        logger.debug("Sending notification: \(title)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        // Suppress output
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                logger.warning("Notification failed with exit code: \(process.terminationStatus)")
            }
        } catch {
            logger.warning("Failed to send notification: \(error.localizedDescription)")
        }
    }

    /// Send a sync success notification
    func sendSyncSuccess(created: Int, updated: Int, deleted: Int, unchanged: Int, sound: String? = "default") async {
        let title = "Sync Complete"

        var parts: [String] = []
        if created > 0 { parts.append("\(created) created") }
        if updated > 0 { parts.append("\(updated) updated") }
        if deleted > 0 { parts.append("\(deleted) deleted") }

        let message: String
        if parts.isEmpty {
            message = "No changes detected"
        } else {
            message = parts.joined(separator: ", ")
        }

        await send(title: title, message: message, sound: sound)
    }

    /// Send a sync partial success notification (completed with some errors)
    func sendSyncPartial(created: Int, updated: Int, deleted: Int, errorCount: Int, sound: String? = "default") async {
        let total = created + updated + deleted
        let title = "Sync Completed with Errors"
        let message = "\(total) events synced, \(errorCount) error\(errorCount == 1 ? "" : "s")"

        await send(title: title, message: message, sound: sound)
    }

    /// Send a sync failure notification
    func sendSyncFailure(errorMessage: String, sound: String? = "default") async {
        let title = "Sync Failed"
        // Truncate long error messages
        let message = errorMessage.count > 100
            ? String(errorMessage.prefix(97)) + "..."
            : errorMessage

        await send(title: title, message: message, sound: sound)
    }

    // MARK: - Private Methods

    /// Escape special characters for AppleScript string
    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
