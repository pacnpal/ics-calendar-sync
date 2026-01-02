import Foundation

// MARK: - Signal Handler

/// Handles POSIX signals for graceful shutdown
final class SignalHandler: @unchecked Sendable {
    private var sources: [DispatchSourceSignal] = []
    private var shutdownHandler: (() -> Void)?
    private let lock = NSLock()

    static let shared = SignalHandler()

    private init() {}

    /// Setup signal handlers for graceful shutdown
    func setup(onShutdown: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        self.shutdownHandler = onShutdown

        // Handle SIGTERM (sent by launchd for graceful stop)
        setupSignal(SIGTERM)

        // Handle SIGINT (Ctrl+C)
        setupSignal(SIGINT)

        // Handle SIGHUP (terminal hangup, often used for reload)
        setupSignal(SIGHUP)
    }

    private func setupSignal(_ sig: Int32) {
        // Ignore the default signal handler
        signal(sig, SIG_IGN)

        // Create dispatch source for the signal
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)

        source.setEventHandler { [weak self] in
            self?.handleSignal(sig)
        }

        source.resume()
        sources.append(source)
    }

    private func handleSignal(_ sig: Int32) {
        let signalName: String
        switch sig {
        case SIGTERM: signalName = "SIGTERM"
        case SIGINT: signalName = "SIGINT"
        case SIGHUP: signalName = "SIGHUP"
        default: signalName = "Signal \(sig)"
        }

        Logger.shared.info("Received \(signalName), initiating graceful shutdown...")

        lock.lock()
        let handler = shutdownHandler
        lock.unlock()

        handler?()
    }

    /// Cleanup signal handlers
    func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        shutdownHandler = nil
    }
}

// MARK: - Run Loop Helper

/// Manages the run loop for daemon mode
enum RunLoopHelper {
    /// Keep the current run loop running until stopped
    static func runUntilStopped(checkInterval: TimeInterval = 1.0, shouldStop: @escaping () -> Bool) {
        let runLoop = RunLoop.current

        while !shouldStop() {
            runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: checkInterval))
        }
    }

    /// Run the main run loop (blocks indefinitely)
    static func runForever() {
        RunLoop.current.run()
    }
}
