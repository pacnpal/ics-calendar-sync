import Foundation

// MARK: - Daemon

/// Manages daemon mode with scheduled sync operations
actor Daemon {
    private let syncEngine: SyncEngine
    private let intervalMinutes: Int
    private let notificationConfig: Configuration.NotificationConfig
    private let logger = Logger.shared
    private let notificationManager = NotificationManager.shared

    private var isRunning = false
    private var syncTask: Task<Void, Never>?
    private var shouldStop = false

    init(syncEngine: SyncEngine, intervalMinutes: Int, notificationConfig: Configuration.NotificationConfig = Configuration.NotificationConfig()) {
        self.syncEngine = syncEngine
        self.intervalMinutes = intervalMinutes
        self.notificationConfig = notificationConfig
    }

    // MARK: - Lifecycle

    /// Start the daemon
    func start() async {
        guard !isRunning else {
            logger.warning("Daemon is already running")
            return
        }

        isRunning = true
        shouldStop = false

        logger.info("Starting daemon with \(intervalMinutes) minute sync interval")

        // Setup signal handlers
        SignalHandler.shared.setup { [weak self] in
            guard let daemon = self else { return }
            Task { await daemon.stop() }
        }

        // Perform initial sync
        await performSync()

        // Start the sync loop
        syncTask = Task {
            await runSyncLoop()
        }

        // Keep running until stopped
        while !shouldStop {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }

        logger.info("Daemon stopped")
    }

    /// Stop the daemon
    func stop() async {
        guard isRunning else { return }

        logger.info("Stopping daemon...")
        shouldStop = true
        isRunning = false
        syncTask?.cancel()

        // Gracefully shutdown sync engine (closes database)
        await syncEngine.shutdown()

        SignalHandler.shared.cleanup()
    }

    // MARK: - Sync Loop

    private func runSyncLoop() async {
        let intervalNanos = UInt64(intervalMinutes) * 60 * 1_000_000_000

        while !shouldStop {
            // Sleep for the interval
            do {
                try await Task.sleep(nanoseconds: intervalNanos)
            } catch {
                // Task was cancelled
                break
            }

            guard !shouldStop else { break }

            await performSync()
        }
    }

    private func performSync() async {
        logger.info("Starting scheduled sync...")

        do {
            let result = try await syncEngine.sync()

            if result.hasErrors {
                logger.warning("Sync completed with \(result.errors.count) errors")

                // Send partial success notification
                if notificationConfig.enabled && notificationConfig.onPartial {
                    let errorMessages = result.errors.map { $0.message }
                    await notificationManager.sendSyncPartial(
                        created: result.created,
                        updated: result.updated,
                        deleted: result.deleted,
                        errorCount: result.errors.count,
                        errorMessages: errorMessages,
                        sound: notificationConfig.sound
                    )
                }
            } else {
                // Send success notification
                if notificationConfig.enabled && notificationConfig.onSuccess {
                    await notificationManager.sendSyncSuccess(
                        created: result.created,
                        updated: result.updated,
                        deleted: result.deleted,
                        unchanged: result.unchanged,
                        sound: notificationConfig.sound
                    )
                }
            }
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")

            // Send failure notification
            if notificationConfig.enabled && notificationConfig.onFailure {
                await notificationManager.sendSyncFailure(
                    errorMessage: error.localizedDescription,
                    sound: notificationConfig.sound
                )
            }
        }
    }

    // MARK: - Status

    /// Check if daemon is running
    var running: Bool {
        isRunning
    }
}

// MARK: - Daemon Runner

/// Convenience wrapper for running the daemon
enum DaemonRunner {
    /// Run the daemon with the given configuration (supports multi-feed GUI configs)
    static func run(configPath: String, intervalOverride: Int? = nil) async throws {
        let logger = Logger.shared
        let expandedPath = configPath.expandingTildeInPath

        // Check if this is a GUI multi-feed config
        let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let feeds = json["feeds"] as? [[String: Any]] {
            // Multi-feed mode
            try await runMultiFeed(json: json, feeds: feeds, intervalOverride: intervalOverride)
        } else {
            // Single-feed mode (legacy CLI config)
            try await runSingleFeed(configPath: configPath, intervalOverride: intervalOverride)
        }
    }

    /// Run daemon with multiple feeds from GUI config
    private static func runMultiFeed(json: [String: Any], feeds: [[String: Any]], intervalOverride: Int?) async throws {
        let logger = Logger.shared

        // Filter to enabled feeds only
        let enabledFeeds = feeds.filter { $0["isEnabled"] as? Bool ?? true }
        guard !enabledFeeds.isEmpty else {
            throw ConfigError.missingRequiredField("feeds (no enabled feeds)")
        }

        logger.info("Multi-feed daemon mode: \(enabledFeeds.count) feeds")

        // Global settings
        let globalInterval = intervalOverride ?? (json["global_sync_interval"] as? Int) ?? 15
        let notificationsEnabled = json["notifications_enabled"] as? Bool ?? false

        // Build configs for each feed
        var syncEngines: [(name: String, engine: SyncEngine)] = []
        for feed in enabledFeeds {
            guard let icsURL = feed["icsURL"] as? String, !icsURL.isEmpty else { continue }

            let feedName = feed["name"] as? String ?? "Unnamed"
            var config = Configuration()
            config.source.url = icsURL
            config.destination.calendarName = feed["calendarName"] as? String ?? "Subscribed Events"
            config.sync.deleteOrphans = feed["deleteOrphans"] as? Bool ?? true
            config.daemon.intervalMinutes = feed["syncInterval"] as? Int ?? globalInterval
            config.notifications.enabled = notificationsEnabled

            do {
                let engine = try SyncEngine(config: config)
                try await engine.initialize()
                syncEngines.append((name: feedName, engine: engine))
                logger.info("Initialized feed: \(feedName)")
            } catch {
                logger.error("Failed to initialize feed '\(feedName)': \(error.localizedDescription)")
            }
        }

        guard !syncEngines.isEmpty else {
            throw ConfigError.missingRequiredField("feeds (no valid feeds)")
        }

        logger.info("Sync interval: \(globalInterval) minutes")

        // Create multi-feed daemon
        let notificationConfig = Configuration.NotificationConfig()
        let daemon = MultiFeedDaemon(
            syncEngines: syncEngines,
            intervalMinutes: globalInterval,
            notificationConfig: notificationConfig
        )
        await daemon.start()
    }

    /// Run daemon with single feed (legacy mode)
    private static func runSingleFeed(configPath: String, intervalOverride: Int?) async throws {
        let logger = Logger.shared
        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: configPath)

        let syncEngine = try SyncEngine(config: config)
        try await syncEngine.initialize()

        let interval = intervalOverride ?? config.daemon.intervalMinutes
        logger.info("Sync interval: \(interval) minutes")

        if config.notifications.enabled {
            logger.info("Notifications enabled (success: \(config.notifications.onSuccess), failure: \(config.notifications.onFailure), partial: \(config.notifications.onPartial))")
        }

        let daemon = Daemon(syncEngine: syncEngine, intervalMinutes: interval, notificationConfig: config.notifications)
        await daemon.start()
    }

    /// Run daemon in foreground with run loop
    static func runWithRunLoop(configPath: String, intervalOverride: Int? = nil) async throws {
        try await run(configPath: configPath, intervalOverride: intervalOverride)
    }
}

// MARK: - Multi-Feed Daemon

/// Daemon that syncs multiple feeds
actor MultiFeedDaemon {
    private let syncEngines: [(name: String, engine: SyncEngine)]
    private let intervalMinutes: Int
    private let notificationConfig: Configuration.NotificationConfig
    private let logger = Logger.shared
    private let notificationManager = NotificationManager.shared

    private var isRunning = false
    private var syncTask: Task<Void, Never>?
    private var shouldStop = false

    init(syncEngines: [(name: String, engine: SyncEngine)], intervalMinutes: Int, notificationConfig: Configuration.NotificationConfig) {
        self.syncEngines = syncEngines
        self.intervalMinutes = intervalMinutes
        self.notificationConfig = notificationConfig
    }

    func start() async {
        guard !isRunning else {
            logger.warning("Daemon is already running")
            return
        }

        isRunning = true
        shouldStop = false

        logger.info("Starting multi-feed daemon with \(intervalMinutes) minute sync interval (\(syncEngines.count) feeds)")

        SignalHandler.shared.setup { [weak self] in
            guard let daemon = self else { return }
            Task { await daemon.stop() }
        }

        await performSyncAll()

        syncTask = Task {
            await runSyncLoop()
        }

        while !shouldStop {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        logger.info("Daemon stopped")
    }

    func stop() async {
        guard isRunning else { return }
        logger.info("Stopping daemon...")
        shouldStop = true
        isRunning = false
        syncTask?.cancel()

        // Gracefully shutdown all sync engines
        for (name, engine) in syncEngines {
            logger.debug("Shutting down engine for feed: \(name)")
            await engine.shutdown()
        }

        SignalHandler.shared.cleanup()
    }

    private func runSyncLoop() async {
        let intervalNanos = UInt64(intervalMinutes) * 60 * 1_000_000_000

        while !shouldStop {
            do {
                try await Task.sleep(nanoseconds: intervalNanos)
            } catch {
                break
            }

            guard !shouldStop else { break }
            await performSyncAll()
        }
    }

    private func performSyncAll() async {
        logger.info("Starting scheduled sync for \(syncEngines.count) feeds...")

        var totalCreated = 0
        var totalUpdated = 0
        var totalDeleted = 0
        var totalUnchanged = 0
        var totalErrors = 0

        for (name, engine) in syncEngines {
            do {
                let result = try await engine.sync()
                totalCreated += result.created
                totalUpdated += result.updated
                totalDeleted += result.deleted
                totalUnchanged += result.unchanged
                totalErrors += result.errors.count

                if result.hasErrors {
                    logger.warning("[\(name)] Sync completed with \(result.errors.count) errors")
                } else {
                    logger.info("[\(name)] Sync complete: \(result.created) created, \(result.updated) updated, \(result.deleted) deleted, \(result.unchanged) unchanged")
                }
            } catch {
                totalErrors += 1
                logger.error("[\(name)] Sync failed: \(error.localizedDescription)")
            }
        }

        logger.info("All feeds synced: \(totalCreated) created, \(totalUpdated) updated, \(totalDeleted) deleted, \(totalUnchanged) unchanged, \(totalErrors) errors")
    }
}
