import Foundation

// MARK: - Daemon

/// Manages daemon mode with scheduled sync operations
actor Daemon {
    private let syncEngine: SyncEngine
    private let intervalMinutes: Int
    private let logger = Logger.shared

    private var isRunning = false
    private var syncTask: Task<Void, Never>?
    private var shouldStop = false

    init(syncEngine: SyncEngine, intervalMinutes: Int) {
        self.syncEngine = syncEngine
        self.intervalMinutes = intervalMinutes
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
            Task { await self?.stop() }
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
    func stop() {
        guard isRunning else { return }

        logger.info("Stopping daemon...")
        shouldStop = true
        isRunning = false
        syncTask?.cancel()

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
            } else {
                logger.info("Sync complete: \(result.created) created, \(result.updated) updated, \(result.deleted) deleted, \(result.unchanged) unchanged")
            }
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
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
    /// Run the daemon with the given configuration
    static func run(configPath: String, intervalOverride: Int? = nil) async throws {
        let logger = Logger.shared

        // Load configuration
        let configManager = ConfigurationManager.shared
        let config = try await configManager.load(from: configPath)

        // Create sync engine
        let syncEngine = try SyncEngine(config: config)
        try await syncEngine.initialize()

        // Determine interval
        let interval = intervalOverride ?? config.daemon.intervalMinutes
        logger.info("Sync interval: \(interval) minutes")

        // Create and start daemon
        let daemon = Daemon(syncEngine: syncEngine, intervalMinutes: interval)
        await daemon.start()
    }

    /// Run daemon in foreground with run loop
    static func runWithRunLoop(configPath: String, intervalOverride: Int? = nil) async throws {
        try await run(configPath: configPath, intervalOverride: intervalOverride)
    }
}
