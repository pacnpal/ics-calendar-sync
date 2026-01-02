import Foundation

// MARK: - ICS Errors

/// Errors related to ICS feed fetching and parsing
enum ICSError: LocalizedError {
    case fetchFailed(URL, Error)
    case invalidResponse(Int)
    case parseError(String)
    case missingUID
    case invalidStartDate
    case invalidEndDate
    case missingRequiredField(String)
    case invalidURL(String)
    case authenticationRequired
    case invalidTimezone(String)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let url, let error):
            return "Failed to fetch ICS from \(url): \(error.localizedDescription)"
        case .invalidResponse(let code):
            return "Server returned HTTP \(code)"
        case .parseError(let message):
            return "ICS parse error: \(message)"
        case .missingUID:
            return "Event missing required UID field"
        case .invalidStartDate:
            return "Event has invalid or missing start date"
        case .invalidEndDate:
            return "Event has invalid end date"
        case .missingRequiredField(let field):
            return "Event missing required field: \(field)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .authenticationRequired:
            return "Authentication required. Provide credentials via config or environment variables."
        case .invalidTimezone(let tz):
            return "Invalid or unsupported timezone: \(tz)"
        }
    }
}

// MARK: - Calendar Errors

/// Errors related to EventKit calendar operations
enum CalendarError: LocalizedError {
    case accessDenied
    case accessRestricted
    case noSuitableSource
    case calendarNotFound(String)
    case saveFailed(Error)
    case deleteFailed(Error)
    case eventNotFound(String)
    case invalidCalendarSource(String)
    case calendarCreationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access denied. Grant access in System Settings > Privacy & Security > Calendars"
        case .accessRestricted:
            return "Calendar access is restricted by system policy"
        case .noSuitableSource:
            return "No suitable calendar source found (iCloud or Local)"
        case .calendarNotFound(let name):
            return "Calendar '\(name)' not found"
        case .saveFailed(let error):
            return "Failed to save to calendar: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete from calendar: \(error.localizedDescription)"
        case .eventNotFound(let id):
            return "Event with identifier '\(id)' not found"
        case .invalidCalendarSource(let source):
            return "Invalid calendar source: \(source)"
        case .calendarCreationFailed(let error):
            return "Failed to create calendar: \(error.localizedDescription)"
        }
    }
}

// MARK: - Sync Errors

/// Errors related to the sync process
enum SyncError: LocalizedError {
    case calendarNotFound(String)
    case eventFailed(String, Error)
    case stateCorrupted
    case databaseError(Error)
    case configurationError(String)
    case networkError(Error)
    case partialFailure(created: Int, updated: Int, deleted: Int, errors: [Error])

    var errorDescription: String? {
        switch self {
        case .calendarNotFound(let name):
            return "Target calendar '\(name)' not found"
        case .eventFailed(let uid, let error):
            return "Failed to sync event \(uid): \(error.localizedDescription)"
        case .stateCorrupted:
            return "Sync state database is corrupted. Run 'ics-calendar-sync reset --force' to reset."
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .partialFailure(let created, let updated, let deleted, let errors):
            return "Partial sync failure: \(created) created, \(updated) updated, \(deleted) deleted, \(errors.count) errors"
        }
    }
}

// MARK: - Configuration Errors

/// Errors related to configuration loading and validation
enum ConfigError: LocalizedError {
    case fileNotFound(String)
    case invalidFormat(String)
    case missingRequiredField(String)
    case invalidValue(field: String, value: String, reason: String)
    case environmentVariableNotSet(String)
    case keychainAccessFailed(Error)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Configuration file not found: \(path)"
        case .invalidFormat(let message):
            return "Invalid configuration format: \(message)"
        case .missingRequiredField(let field):
            return "Missing required configuration field: \(field)"
        case .invalidValue(let field, let value, let reason):
            return "Invalid value for '\(field)': '\(value)' - \(reason)"
        case .environmentVariableNotSet(let name):
            return "Environment variable not set: \(name)"
        case .keychainAccessFailed(let error):
            return "Failed to access keychain: \(error.localizedDescription)"
        case .permissionDenied(let path):
            return "Permission denied accessing: \(path)"
        }
    }
}

// MARK: - Setup Errors

/// Errors during interactive setup
enum SetupError: LocalizedError {
    case cancelled
    case permissionDenied
    case invalidInput(String)
    case networkTestFailed(Error)
    case calendarAccessFailed
    case launchdInstallFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Setup cancelled by user"
        case .permissionDenied:
            return "Required permission was denied"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .networkTestFailed(let error):
            return "Failed to connect to ICS URL: \(error.localizedDescription)"
        case .calendarAccessFailed:
            return "Failed to obtain calendar access"
        case .launchdInstallFailed(let error):
            return "Failed to install launchd service: \(error.localizedDescription)"
        }
    }
}
