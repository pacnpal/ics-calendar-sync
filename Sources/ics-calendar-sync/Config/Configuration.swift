import Foundation

// MARK: - Configuration

/// Application configuration loaded from file
struct Configuration: Codable, Sendable {
    var source: SourceConfig
    var destination: DestinationConfig
    var sync: SyncConfig
    var state: StateConfig
    var logging: LoggingConfig
    var daemon: DaemonConfig
    var notifications: NotificationConfig

    init() {
        self.source = SourceConfig()
        self.destination = DestinationConfig()
        self.sync = SyncConfig()
        self.state = StateConfig()
        self.logging = LoggingConfig()
        self.daemon = DaemonConfig()
        self.notifications = NotificationConfig()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(SourceConfig.self, forKey: .source) ?? SourceConfig()
        destination = try container.decodeIfPresent(DestinationConfig.self, forKey: .destination) ?? DestinationConfig()
        sync = try container.decodeIfPresent(SyncConfig.self, forKey: .sync) ?? SyncConfig()
        state = try container.decodeIfPresent(StateConfig.self, forKey: .state) ?? StateConfig()
        logging = try container.decodeIfPresent(LoggingConfig.self, forKey: .logging) ?? LoggingConfig()
        daemon = try container.decodeIfPresent(DaemonConfig.self, forKey: .daemon) ?? DaemonConfig()
        notifications = try container.decodeIfPresent(NotificationConfig.self, forKey: .notifications) ?? NotificationConfig()
    }

    enum CodingKeys: String, CodingKey {
        case source, destination, sync, state, logging, daemon, notifications
    }

    /// Source ICS configuration
    struct SourceConfig: Codable, Sendable {
        var url: String = ""
        var headers: [String: String] = [:]
        var timeout: Int = 30
        var verifySSL: Bool = true

        enum CodingKeys: String, CodingKey {
            case url
            case headers
            case timeout
            case verifySSL = "verify_ssl"
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
            timeout = try container.decodeIfPresent(Int.self, forKey: .timeout) ?? 30
            verifySSL = try container.decodeIfPresent(Bool.self, forKey: .verifySSL) ?? true
        }
    }

    /// Destination calendar configuration
    struct DestinationConfig: Codable, Sendable {
        var calendarName: String = "Subscribed Events"
        var createIfMissing: Bool = true
        var sourcePreference: String = "icloud"

        enum CodingKeys: String, CodingKey {
            case calendarName = "calendar_name"
            case createIfMissing = "create_if_missing"
            case sourcePreference = "source_preference"
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            calendarName = try container.decodeIfPresent(String.self, forKey: .calendarName) ?? "Subscribed Events"
            createIfMissing = try container.decodeIfPresent(Bool.self, forKey: .createIfMissing) ?? true
            sourcePreference = try container.decodeIfPresent(String.self, forKey: .sourcePreference) ?? "icloud"
        }
    }

    /// Sync behavior configuration
    struct SyncConfig: Codable, Sendable {
        var deleteOrphans: Bool = true
        var summaryPrefix: String = ""
        var windowDaysPast: Int? = 30
        var windowDaysFuture: Int? = 365
        var syncAlarms: Bool = true

        enum CodingKeys: String, CodingKey {
            case deleteOrphans = "delete_orphans"
            case summaryPrefix = "summary_prefix"
            case windowDaysPast = "window_days_past"
            case windowDaysFuture = "window_days_future"
            case syncAlarms = "sync_alarms"
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            deleteOrphans = try container.decodeIfPresent(Bool.self, forKey: .deleteOrphans) ?? true
            summaryPrefix = try container.decodeIfPresent(String.self, forKey: .summaryPrefix) ?? ""
            windowDaysPast = try container.decodeIfPresent(Int.self, forKey: .windowDaysPast) ?? 30
            windowDaysFuture = try container.decodeIfPresent(Int.self, forKey: .windowDaysFuture) ?? 365
            syncAlarms = try container.decodeIfPresent(Bool.self, forKey: .syncAlarms) ?? true
        }
    }

    /// State persistence configuration
    struct StateConfig: Codable, Sendable {
        var path: String = "~/.local/share/ics-calendar-sync/state.db"

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decodeIfPresent(String.self, forKey: .path) ?? "~/.local/share/ics-calendar-sync/state.db"
        }

        enum CodingKeys: String, CodingKey {
            case path
        }
    }

    /// Logging configuration
    struct LoggingConfig: Codable, Sendable {
        var level: String = "info"
        var format: String = "text"

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            level = try container.decodeIfPresent(String.self, forKey: .level) ?? "info"
            format = try container.decodeIfPresent(String.self, forKey: .format) ?? "text"
        }

        enum CodingKeys: String, CodingKey {
            case level
            case format
        }
    }

    /// Daemon mode configuration
    struct DaemonConfig: Codable, Sendable {
        var intervalMinutes: Int = 15

        enum CodingKeys: String, CodingKey {
            case intervalMinutes = "interval_minutes"
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 15
        }
    }

    /// Notification configuration
    struct NotificationConfig: Codable, Sendable {
        var enabled: Bool = false
        var onSuccess: Bool = false
        var onFailure: Bool = true
        var onPartial: Bool = true
        var sound: String? = "default"

        enum CodingKeys: String, CodingKey {
            case enabled
            case onSuccess = "on_success"
            case onFailure = "on_failure"
            case onPartial = "on_partial"
            case sound
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            onSuccess = try container.decodeIfPresent(Bool.self, forKey: .onSuccess) ?? false
            onFailure = try container.decodeIfPresent(Bool.self, forKey: .onFailure) ?? true
            onPartial = try container.decodeIfPresent(Bool.self, forKey: .onPartial) ?? true
            sound = try container.decodeIfPresent(String.self, forKey: .sound) ?? "default"
        }
    }
}

// MARK: - Configuration Manager

/// Manages loading, saving, and validating configuration
actor ConfigurationManager {
    static let shared = ConfigurationManager()
    private let logger = Logger.shared

    /// Default configuration file path
    static let defaultConfigPath = "~/.config/ics-calendar-sync/config.json"

    /// Current configuration
    private var config: Configuration?

    private init() {}

    // MARK: - Loading

    /// Load configuration from file (supports both CLI and GUI formats)
    func load(from path: String) throws -> Configuration {
        let expandedPath = path.expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw ConfigError.fileNotFound(expandedPath)
        }

        let data = try Data(contentsOf: url)

        // Try to detect config format
        var config: Configuration
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let feeds = json["feeds"] as? [[String: Any]] {
            // GUI format detected - convert to CLI format
            logger.debug("Detected GUI config format, converting...")
            config = try convertGUIConfig(json: json, feeds: feeds)
        } else {
            // Standard CLI format
            let decoder = JSONDecoder()
            config = try decoder.decode(Configuration.self, from: data)
        }

        // Expand environment variables in sensitive fields
        config = expandEnvironmentVariables(in: config)

        // Validate configuration
        try validate(config)

        self.config = config
        logger.debug("Loaded configuration from \(expandedPath)")
        return config
    }

    /// Convert GUI config format to CLI Configuration
    private func convertGUIConfig(json: [String: Any], feeds: [[String: Any]]) throws -> Configuration {
        // Find first enabled feed, or first feed if none enabled
        guard !feeds.isEmpty else {
            throw ConfigError.missingRequiredField("feeds (no feeds configured)")
        }

        guard let feed = feeds.first(where: { $0["isEnabled"] as? Bool ?? true }) ?? feeds.first else {
            throw ConfigError.missingRequiredField("feeds (no enabled feeds)")
        }

        var config = Configuration()

        // Source
        if let icsURL = feed["icsURL"] as? String {
            config.source.url = icsURL
        }

        // Destination
        if let calendarName = feed["calendarName"] as? String {
            config.destination.calendarName = calendarName
        }

        // Sync settings
        if let deleteOrphans = feed["deleteOrphans"] as? Bool {
            config.sync.deleteOrphans = deleteOrphans
        }

        // Daemon interval (feed-specific or global)
        if let syncInterval = feed["syncInterval"] as? Int {
            config.daemon.intervalMinutes = syncInterval
        } else if let globalInterval = json["global_sync_interval"] as? Int {
            config.daemon.intervalMinutes = globalInterval
        }

        // Notifications
        if let notificationsEnabled = json["notifications_enabled"] as? Bool {
            config.notifications.enabled = notificationsEnabled
        }
        if let feedNotifications = feed["notificationsEnabled"] as? Bool {
            config.notifications.enabled = feedNotifications
        }

        return config
    }

    /// Load or create default configuration
    func loadOrCreate(from path: String) throws -> Configuration {
        let expandedPath = path.expandingTildeInPath

        if FileManager.default.fileExists(atPath: expandedPath) {
            return try load(from: path)
        } else {
            let config = Configuration()
            try save(config, to: path)
            return config
        }
    }

    // MARK: - Saving

    /// Save configuration to file
    func save(_ config: Configuration, to path: String) throws {
        let expandedPath = path.expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        // Create directory if needed
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectoryIfNeeded(at: directory)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        try data.write(to: url)

        // Set file permissions to owner-only (600)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: expandedPath
        )

        self.config = config
        logger.debug("Saved configuration to \(expandedPath)")
    }

    // MARK: - Validation

    /// Validate configuration
    func validate(_ config: Configuration) throws {
        // Validate source URL
        guard !config.source.url.isEmpty else {
            throw ConfigError.missingRequiredField("source.url")
        }

        guard config.source.url.isValidURL else {
            throw ConfigError.invalidValue(
                field: "source.url",
                value: config.source.url,
                reason: "Not a valid URL"
            )
        }

        // Validate calendar name
        guard !config.destination.calendarName.isEmpty else {
            throw ConfigError.missingRequiredField("destination.calendar_name")
        }

        // Validate source preference
        let validPreferences = ["icloud", "local", "any"]
        guard validPreferences.contains(config.destination.sourcePreference.lowercased()) else {
            throw ConfigError.invalidValue(
                field: "destination.source_preference",
                value: config.destination.sourcePreference,
                reason: "Must be one of: \(validPreferences.joined(separator: ", "))"
            )
        }

        // Validate log level
        guard LogLevel(string: config.logging.level) != nil else {
            throw ConfigError.invalidValue(
                field: "logging.level",
                value: config.logging.level,
                reason: "Must be one of: debug, info, warning, error"
            )
        }

        // Validate log format
        let validFormats = ["text", "json"]
        guard validFormats.contains(config.logging.format.lowercased()) else {
            throw ConfigError.invalidValue(
                field: "logging.format",
                value: config.logging.format,
                reason: "Must be one of: \(validFormats.joined(separator: ", "))"
            )
        }

        // Validate daemon interval
        guard config.daemon.intervalMinutes >= 1 else {
            throw ConfigError.invalidValue(
                field: "daemon.interval_minutes",
                value: String(config.daemon.intervalMinutes),
                reason: "Must be at least 1 minute"
            )
        }

        // Validate timeout
        guard config.source.timeout >= 1 && config.source.timeout <= 300 else {
            throw ConfigError.invalidValue(
                field: "source.timeout",
                value: String(config.source.timeout),
                reason: "Must be between 1 and 300 seconds"
            )
        }
    }

    // MARK: - Environment Variables

    /// Expand environment variables in configuration
    private func expandEnvironmentVariables(in config: Configuration) -> Configuration {
        var expanded = config

        // Expand URL
        expanded.source.url = config.source.url.expandingEnvironmentVariables

        // Expand headers
        expanded.source.headers = config.source.headers.mapValues { $0.expandingEnvironmentVariables }

        // Expand state path
        expanded.state.path = config.state.path.expandingEnvironmentVariables

        return expanded
    }

    // MARK: - Access

    /// Get current configuration
    func current() -> Configuration? {
        config
    }

    /// Get configuration or throw
    func requireCurrent() throws -> Configuration {
        guard let config = config else {
            throw ConfigError.fileNotFound("No configuration loaded")
        }
        return config
    }
}

// MARK: - Configuration Extensions

extension Configuration {
    /// Get fetch configuration for ICS
    func getFetchConfig() -> ICSFetcher.FetchConfig {
        var config = ICSFetcher.FetchConfig()
        config.timeout = TimeInterval(source.timeout)
        config.verifySSL = source.verifySSL
        config.headers = source.headers
        return config
    }

    /// Get event mapping configuration
    func getMappingConfig() -> EventMapper.MappingConfig {
        var config = EventMapper.MappingConfig()
        config.summaryPrefix = sync.summaryPrefix
        config.syncAlarms = sync.syncAlarms
        if let url = URL(string: source.url) {
            config.sourceURL = url
        }
        return config
    }

    /// Get calendar source preference
    func getSourcePreference() -> CalendarManager.SourcePreference {
        CalendarManager.SourcePreference(rawValue: destination.sourcePreference.lowercased()) ?? .iCloud
    }
}

// MARK: - Configuration Builder

extension Configuration {
    /// Builder for programmatic configuration
    final class Builder {
        private var config = Configuration()

        func setSourceURL(_ url: String) -> Builder {
            config.source.url = url
            return self
        }

        func setCalendarName(_ name: String) -> Builder {
            config.destination.calendarName = name
            return self
        }

        func setDeleteOrphans(_ delete: Bool) -> Builder {
            config.sync.deleteOrphans = delete
            return self
        }

        func setSummaryPrefix(_ prefix: String) -> Builder {
            config.sync.summaryPrefix = prefix
            return self
        }

        func setStatePath(_ path: String) -> Builder {
            config.state.path = path
            return self
        }

        func setLogLevel(_ level: String) -> Builder {
            config.logging.level = level
            return self
        }

        func setDaemonInterval(_ minutes: Int) -> Builder {
            config.daemon.intervalMinutes = minutes
            return self
        }

        func addHeader(_ key: String, value: String) -> Builder {
            config.source.headers[key] = value
            return self
        }

        func setNotificationsEnabled(_ enabled: Bool) -> Builder {
            config.notifications.enabled = enabled
            return self
        }

        func setNotifyOnSuccess(_ notify: Bool) -> Builder {
            config.notifications.onSuccess = notify
            return self
        }

        func setNotifyOnFailure(_ notify: Bool) -> Builder {
            config.notifications.onFailure = notify
            return self
        }

        func setNotifyOnPartial(_ notify: Bool) -> Builder {
            config.notifications.onPartial = notify
            return self
        }

        func setNotificationSound(_ sound: String?) -> Builder {
            config.notifications.sound = sound
            return self
        }

        func build() -> Configuration {
            config
        }
    }

    static func builder() -> Builder {
        Builder()
    }
}
