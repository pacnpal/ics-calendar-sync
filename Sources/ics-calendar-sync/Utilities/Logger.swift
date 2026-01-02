import Foundation
import os.log

// MARK: - Log Level

/// Log level for filtering messages
enum LogLevel: Int, Comparable, CaseIterable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    var prefix: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }

    var colorCode: String {
        switch self {
        case .debug: return "\u{001B}[36m"  // Cyan
        case .info: return "\u{001B}[32m"   // Green
        case .warning: return "\u{001B}[33m" // Yellow
        case .error: return "\u{001B}[31m"  // Red
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init?(string: String) {
        switch string.lowercased() {
        case "debug": self = .debug
        case "info": self = .info
        case "warning", "warn": self = .warning
        case "error": self = .error
        default: return nil
        }
    }
}

// MARK: - Log Format

/// Output format for logs
enum LogFormat: Sendable {
    case text
    case json
}

// MARK: - Logger

/// Thread-safe logger with os_log integration and configurable output
final class Logger: @unchecked Sendable {
    static let shared = Logger()

    private let osLog: OSLog
    private let lock = NSLock()
    private var _level: LogLevel = .info
    private var _format: LogFormat = .text
    private var _useColors: Bool
    private var _quiet: Bool = false

    var level: LogLevel {
        get { lock.withLock { _level } }
        set { lock.withLock { _level = newValue } }
    }

    var format: LogFormat {
        get { lock.withLock { _format } }
        set { lock.withLock { _format = newValue } }
    }

    var useColors: Bool {
        get { lock.withLock { _useColors } }
        set { lock.withLock { _useColors = newValue } }
    }

    var quiet: Bool {
        get { lock.withLock { _quiet } }
        set { lock.withLock { _quiet = newValue } }
    }

    private init() {
        self.osLog = OSLog(subsystem: "com.ics-calendar-sync", category: "general")
        self._useColors = isatty(STDOUT_FILENO) != 0
    }

    // MARK: - Logging Methods

    func debug(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message(), file: file, function: function, line: line)
    }

    func info(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message(), file: file, function: function, line: line)
    }

    func warning(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message(), file: file, function: function, line: line)
    }

    func error(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message(), file: file, function: function, line: line)
    }

    // MARK: - Private Methods

    private func log(level: LogLevel, message: String, file: String, function: String, line: Int) {
        guard level >= self.level else { return }
        guard !quiet || level == .error else { return }

        // Log to os_log
        os_log("%{public}@", log: osLog, type: level.osLogType, message)

        // Log to console
        let output: String
        switch format {
        case .text:
            output = formatText(level: level, message: message, file: file, line: line)
        case .json:
            output = formatJSON(level: level, message: message, file: file, function: function, line: line)
        }

        let stream: UnsafeMutablePointer<FILE> = level == .error ? stderr : stdout
        fputs(output + "\n", stream)
        fflush(stream)
    }

    private func formatText(level: LogLevel, message: String, file: String, line: Int) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = (file as NSString).lastPathComponent

        let reset = "\u{001B}[0m"
        let levelStr: String
        if useColors {
            levelStr = "\(level.colorCode)\(level.prefix)\(reset)"
        } else {
            levelStr = level.prefix
        }

        if level == .debug {
            return "[\(timestamp)] \(levelStr) [\(fileName):\(line)] \(message)"
        } else {
            return "[\(timestamp)] \(levelStr) \(message)"
        }
    }

    private func formatJSON(level: LogLevel, message: String, file: String, function: String, line: Int) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = (file as NSString).lastPathComponent

        var dict: [String: Any] = [
            "timestamp": timestamp,
            "level": level.prefix.lowercased(),
            "message": message
        ]

        if level == .debug {
            dict["file"] = fileName
            dict["function"] = function
            dict["line"] = line
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to serialize log\"}"
        }

        return json
    }
}

// MARK: - Convenience

extension Logger {
    /// Configure logger from settings
    func configure(level: LogLevel, format: LogFormat, quiet: Bool) {
        self.level = level
        self.format = format
        self.quiet = quiet
    }

    /// Log a separator line
    func separator() {
        guard !quiet else { return }
        print(String(repeating: "-", count: 60))
    }

    /// Log progress with spinner-like indicator
    func progress(_ message: String) {
        guard !quiet else { return }
        print("  → \(message)")
        fflush(stdout)
    }

    /// Log success with checkmark
    func success(_ message: String) {
        guard !quiet else { return }
        let check = useColors ? "\u{001B}[32m✓\u{001B}[0m" : "✓"
        print("  \(check) \(message)")
    }

    /// Log failure with X
    func failure(_ message: String) {
        let x = useColors ? "\u{001B}[31m✗\u{001B}[0m" : "✗"
        fputs("  \(x) \(message)\n", stderr)
        fflush(stderr)
    }
}

// MARK: - NSLock Extension

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
