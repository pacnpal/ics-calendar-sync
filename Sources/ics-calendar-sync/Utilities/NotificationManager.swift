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
    ///   - subtitle: Optional subtitle (shown below title, smaller text)
    ///   - message: The notification body text
    ///   - sound: Optional sound name (from /System/Library/Sounds or ~/Library/Sounds), nil for no sound
    func send(title: String, subtitle: String? = nil, message: String, sound: String? = "default") async {
        let escapedTitle = escapeForAppleScript(title)
        let escapedMessage = escapeForAppleScript(message)

        var script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\""

        if let subtitle = subtitle {
            let escapedSubtitle = escapeForAppleScript(subtitle)
            script += " subtitle \"\(escapedSubtitle)\""
        }

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
        let title = "Calendar Sync Complete"
        let total = created + updated + deleted + unchanged

        // Build detailed change summary
        var changes: [String] = []
        if created > 0 { changes.append("+\(created) new") }
        if updated > 0 { changes.append("\(updated) updated") }
        if deleted > 0 { changes.append("-\(deleted) removed") }

        let subtitle: String?
        let message: String

        if changes.isEmpty {
            subtitle = "No changes"
            message = "\(total) event\(total == 1 ? "" : "s") up to date"
        } else {
            subtitle = changes.joined(separator: ", ")
            if unchanged > 0 {
                message = "\(unchanged) event\(unchanged == 1 ? "" : "s") unchanged"
            } else {
                message = "\(total) event\(total == 1 ? "" : "s") processed"
            }
        }

        await send(title: title, subtitle: subtitle, message: message, sound: sound)
    }

    /// Send a sync partial success notification (completed with some errors)
    func sendSyncPartial(created: Int, updated: Int, deleted: Int, errorCount: Int, errorMessages: [String] = [], sound: String? = "default") async {
        let title = "Calendar Sync Incomplete"
        let successCount = created + updated + deleted

        // Build change summary for subtitle
        var changes: [String] = []
        if created > 0 { changes.append("+\(created) new") }
        if updated > 0 { changes.append("\(updated) updated") }
        if deleted > 0 { changes.append("-\(deleted) removed") }

        let subtitle: String
        if changes.isEmpty {
            subtitle = "\(errorCount) error\(errorCount == 1 ? "" : "s")"
        } else {
            subtitle = "\(changes.joined(separator: ", ")) | \(errorCount) error\(errorCount == 1 ? "" : "s")"
        }

        // Include first error message if available
        let message: String
        if let firstError = errorMessages.first {
            let truncated = firstError.count > 80 ? String(firstError.prefix(77)) + "..." : firstError
            message = truncated
        } else {
            message = "\(successCount) event\(successCount == 1 ? "" : "s") synced, \(errorCount) failed"
        }

        await send(title: title, subtitle: subtitle, message: message, sound: sound)
    }

    /// Send a sync failure notification
    func sendSyncFailure(errorMessage: String, sound: String? = "default") async {
        let title = "Calendar Sync Failed"

        // Clean up and format error message
        let cleanedError = cleanErrorMessage(errorMessage)

        // Split into subtitle (error type) and message (details) if possible
        let subtitle: String?
        let message: String

        if let colonIndex = cleanedError.firstIndex(of: ":") {
            let errorType = String(cleanedError[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let errorDetail = String(cleanedError[cleanedError.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            if errorType.count < 40 && !errorDetail.isEmpty {
                subtitle = errorType
                message = errorDetail.count > 100 ? String(errorDetail.prefix(97)) + "..." : errorDetail
            } else {
                subtitle = nil
                message = cleanedError.count > 100 ? String(cleanedError.prefix(97)) + "..." : cleanedError
            }
        } else {
            subtitle = nil
            message = cleanedError.count > 100 ? String(cleanedError.prefix(97)) + "..." : cleanedError
        }

        await send(title: title, subtitle: subtitle, message: message, sound: sound)
    }

    // MARK: - Private Methods

    /// Clean up common error message patterns for display
    private func cleanErrorMessage(_ message: String) -> String {
        var cleaned = message

        // Remove common verbose prefixes
        let prefixesToRemove = [
            "The operation couldn't be completed. ",
            "Error Domain=",
            "NSCocoaErrorDomain Code=",
            "NSURLErrorDomain Code="
        ]

        for prefix in prefixesToRemove {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }

        // Clean up URL error messages
        cleaned = cleaned.replacingOccurrences(of: "NSLocalizedDescription=", with: "")
        cleaned = cleaned.replacingOccurrences(of: "NSUnderlyingError=", with: "")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Escape special characters for AppleScript string
    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
