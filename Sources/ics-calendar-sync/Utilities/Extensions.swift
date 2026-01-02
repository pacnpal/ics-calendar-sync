import Foundation

// MARK: - String Extensions

extension String {
    /// Unescape ICS-encoded string
    var icsUnescaped: String {
        self.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Escape string for ICS format
    var icsEscaped: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Expand environment variables in the form ${VAR_NAME}
    var expandingEnvironmentVariables: String {
        var result = self
        let pattern = "\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self
        }

        let matches = regex.matches(in: self, options: [], range: NSRange(self.startIndex..., in: self))

        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: self),
                  let varNameRange = Range(match.range(at: 1), in: self) else {
                continue
            }

            let varName = String(self[varNameRange])
            let value = ProcessInfo.processInfo.environment[varName] ?? ""
            result.replaceSubrange(fullRange, with: value)
        }

        return result
    }

    /// Expand tilde to home directory
    var expandingTildeInPath: String {
        if hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path + dropFirst()
        }
        return self
    }

    /// Trim whitespace and newlines
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if string is a valid URL
    var isValidURL: Bool {
        guard let url = URL(string: self) else { return false }
        return url.scheme != nil && url.host != nil
    }

    /// Mask sensitive data for logging (show first/last few chars)
    var masked: String {
        guard count > 8 else { return String(repeating: "*", count: count) }
        let prefix = String(self.prefix(4))
        let suffix = String(self.suffix(4))
        let middle = String(repeating: "*", count: min(8, count - 8))
        return "\(prefix)\(middle)\(suffix)"
    }
}

// MARK: - Date Extensions

extension Date {
    /// ISO8601 string representation
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }

    /// Format for display
    func formatted(style: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = timeStyle
        return formatter.string(from: self)
    }

    /// Start of day
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// End of day
    var endOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: self) ?? self
    }

    /// Add days
    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// Days from now
    static func daysFromNow(_ days: Int) -> Date {
        Date().addingDays(days)
    }
}

// MARK: - URL Extensions

extension URL {
    /// Check if URL is reachable (synchronous, use with caution)
    var isReachable: Bool {
        guard let reachable = try? checkResourceIsReachable() else { return false }
        return reachable
    }

    /// Get URL with scheme defaulting to https
    var withHTTPSScheme: URL {
        guard scheme == "http" else { return self }
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? self
    }
}

// MARK: - Collection Extensions

extension Collection {
    /// Safe subscript that returns nil for out-of-bounds indices
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Optional Extensions

extension Optional where Wrapped == String {
    /// Returns true if nil or empty
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let value): return value.isEmpty
        }
    }
}

// MARK: - FileManager Extensions

extension FileManager {
    /// Create directory if it doesn't exist
    func createDirectoryIfNeeded(at url: URL) throws {
        if !fileExists(atPath: url.path) {
            try createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Create directory if it doesn't exist (path version)
    func createDirectoryIfNeeded(atPath path: String) throws {
        let url = URL(fileURLWithPath: path.expandingTildeInPath)
        try createDirectoryIfNeeded(at: url)
    }

    /// Get or create app support directory
    func appSupportDirectory(for bundleId: String) throws -> URL {
        let appSupport = try url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let appDir = appSupport.appendingPathComponent(bundleId)
        try createDirectoryIfNeeded(at: appDir)
        return appDir
    }

    /// Get or create config directory
    func configDirectory(for appName: String) throws -> URL {
        let home = homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".config").appendingPathComponent(appName)
        try createDirectoryIfNeeded(at: configDir)
        return configDir
    }

    /// Get or create data directory
    func dataDirectory(for appName: String) throws -> URL {
        let home = homeDirectoryForCurrentUser
        let dataDir = home.appendingPathComponent(".local/share").appendingPathComponent(appName)
        try createDirectoryIfNeeded(at: dataDir)
        return dataDir
    }
}

// MARK: - Data Extensions

extension Data {
    /// Hex string representation
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Minutes in seconds
    static func minutes(_ minutes: Double) -> TimeInterval {
        minutes * 60
    }

    /// Hours in seconds
    static func hours(_ hours: Double) -> TimeInterval {
        hours * 3600
    }

    /// Days in seconds
    static func days(_ days: Double) -> TimeInterval {
        days * 86400
    }
}

// MARK: - Result Extensions

extension Result {
    /// Get success value or nil
    var success: Success? {
        switch self {
        case .success(let value): return value
        case .failure: return nil
        }
    }

    /// Get failure error or nil
    var failure: Failure? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
