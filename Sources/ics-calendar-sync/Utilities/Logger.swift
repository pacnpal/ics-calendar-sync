import Darwin
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

/// Route a record once to each distinct destination. A launchd stream can refer
/// to either log (including 2>&1) and may have been opened without O_APPEND.
private struct LogOutput {
    let files: [FileHandle]
    let console: UnsafeMutablePointer<FILE>?

    init(file: FileHandle?, otherFile: FileHandle?, stream: UnsafeMutablePointer<FILE>) {
        let streamFD = fileno(stream)
        let logFiles = [file, otherFile].compactMap { $0 }
        let redirected = logFiles.first { Self.sameFile($0.fileDescriptor, streamFD) }
        var files = [file].compactMap { $0 }
        if let redirected {
            if redirected !== file { files.append(redirected) }
            Self.protectStandardStream(streamFD, with: redirected)
        }
        self.files = files
        console = redirected == nil ? stream : nil
    }

    private static func protectStandardStream(_ fd: Int32, with file: FileHandle) {
        // CLI summaries and ArgumentParser diagnostics also use stdio directly.
        // Give this process an append descriptor without changing the flags on
        // the open file description shared with its parent.
        guard fd == STDOUT_FILENO || fd == STDERR_FILENO else { return }
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 && flags & O_APPEND == 0 else { return }
        let descriptorFlags = fcntl(fd, F_GETFD)
        guard descriptorFlags >= 0, dup2(file.fileDescriptor, fd) == fd else {
            os_log("Cannot enable append on redirected console", type: .error)
            return
        }
        if descriptorFlags != 0 && fcntl(fd, F_SETFD, descriptorFlags) == -1 {
            os_log("Cannot restore redirected console descriptor flags", type: .error)
        }
    }

    // Append mode and file identity checks contributed by Jacques Vidrine (@fboundp) in #3.
    private static func sameFile(_ lhs: Int32, _ rhs: Int32) -> Bool {
        var file = stat()
        var stream = stat()
        return fstat(lhs, &file) == 0 && fstat(rhs, &stream) == 0
            && file.st_dev == stream.st_dev && file.st_ino == stream.st_ino
    }
}

/// Thread-safe logger with os_log integration and configurable output
final class Logger: @unchecked Sendable {
    static let shared = Logger()

    private let osLog: OSLog
    private let lock = NSLock()
    private var _level: LogLevel = .info
    private var _format: LogFormat = .text
    private var _useColors: Bool
    private var _quiet: Bool = false

    private let output: LogOutput
    private let errorOutput: LogOutput

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

    init(
        logDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ics-calendar-sync", isDirectory: true),
        standardOutput: UnsafeMutablePointer<FILE> = stdout,
        standardError: UnsafeMutablePointer<FILE> = stderr
    ) {
        self.osLog = OSLog(subsystem: "com.ics-calendar-sync", category: "general")
        self._useColors = isatty(fileno(standardOutput)) != 0

        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            os_log("Cannot create log directory: %{public}@", type: .error, error.localizedDescription)
        }
        let out = Self.openLogFile(logDirectory.appendingPathComponent("stdout.log"))
        let err = Self.openLogFile(logDirectory.appendingPathComponent("stderr.log"))
        output = LogOutput(file: out, otherFile: err, stream: standardOutput)
        errorOutput = LogOutput(file: err, otherFile: out, stream: standardError)
    }

    private static func openLogFile(_ url: URL) -> FileHandle? {
        var fd: Int32
        repeat {
            fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        } while fd == -1 && errno == EINTR
        guard fd >= 0 else {
            let reason = String(cString: strerror(errno))
            os_log("Cannot open %{public}@: %{public}@", type: .error, url.path, reason)
            return nil
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
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

        let destination = level == .error ? errorOutput : output
        switch format {
        case .text:
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let location = level == .debug ? "[\((file as NSString).lastPathComponent):\(line)] " : ""
            func render(_ prefix: String) -> String { "[\(timestamp)] \(prefix) \(location)\(message)" }
            let colored = useColors && destination.console != nil
                ? render("\(level.colorCode)\(level.prefix)\u{001B}[0m")
                : nil
            writeLine(render(level.prefix), consoleText: colored, to: destination)
        case .json:
            writeLine(formatJSON(level: level, message: message, file: file, function: function, line: line), to: destination)
        }
    }

    private func writeLine(_ text: String, consoleText: String? = nil, to destination: LogOutput) {
        let record = Data((text + "\n").utf8)
        lock.withLock {
            for file in destination.files {
                do {
                    try file.write(contentsOf: record)
                    try file.synchronize()
                } catch {
                    os_log("Cannot write log: %{public}@", log: osLog, type: .error, error.localizedDescription)
                }
            }
            if let stream = destination.console {
                let data = consoleText.map { Data(($0 + "\n").utf8) } ?? record
                let count = data.withUnsafeBytes { bytes in
                    fwrite(bytes.baseAddress!, 1, bytes.count, stream)
                }
                if fflush(stream) != 0 || count != data.count {
                    os_log("Cannot write console log", log: osLog, type: .error)
                }
            }
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
        writeLine(String(repeating: "-", count: 60), to: output)
    }

    /// Log progress with spinner-like indicator
    func progress(_ message: String) {
        guard !quiet else { return }
        writeLine("  → \(message)", to: output)
    }

    /// Log success with checkmark
    func success(_ message: String) {
        guard !quiet else { return }
        let colored = useColors ? "  \u{001B}[32m✓\u{001B}[0m \(message)" : nil
        writeLine("  ✓ \(message)", consoleText: colored, to: output)
    }

    /// Log failure with X
    func failure(_ message: String) {
        let colored = useColors ? "  \u{001B}[31m✗\u{001B}[0m \(message)" : nil
        writeLine("  ✗ \(message)", consoleText: colored, to: errorOutput)
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
