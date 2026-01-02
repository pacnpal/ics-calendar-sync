import Foundation

// MARK: - ICS Fetcher

/// Fetches ICS content from remote URLs with support for authentication
actor ICSFetcher {
    private let logger = Logger.shared
    private let session: URLSession

    /// Configuration for fetch operations
    struct FetchConfig: Sendable {
        var timeout: TimeInterval = 30
        var headers: [String: String] = [:]
        var verifySSL: Bool = true
        var maxRetries: Int = 3
        var retryDelay: TimeInterval = 2

        init() {}
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Fetch ICS content from URL
    func fetch(from url: URL, config: FetchConfig = FetchConfig()) async throws -> String {
        var lastError: Error = ICSError.fetchFailed(url, NSError(domain: "Unknown", code: -1))
        var delay = config.retryDelay

        for attempt in 1...config.maxRetries {
            do {
                logger.debug("Fetching ICS from \(url) (attempt \(attempt)/\(config.maxRetries))")
                let content = try await performFetch(url: url, config: config)
                return content
            } catch {
                lastError = error
                logger.warning("Fetch attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < config.maxRetries {
                    // Exponential backoff
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2
                }
            }
        }

        throw lastError
    }

    /// Validate that a URL returns valid ICS content
    func validate(url: URL, config: FetchConfig = FetchConfig()) async throws -> ValidationResult {
        let content = try await fetch(from: url, config: config)
        let parser = ICSParser()

        do {
            let events = try await parser.parse(content)
            return ValidationResult(
                isValid: true,
                eventCount: events.count,
                sampleEvents: Array(events.prefix(5)),
                dateRange: calculateDateRange(events)
            )
        } catch {
            return ValidationResult(
                isValid: false,
                eventCount: 0,
                sampleEvents: [],
                dateRange: nil,
                error: error
            )
        }
    }

    /// Result of ICS validation
    struct ValidationResult: Sendable {
        let isValid: Bool
        let eventCount: Int
        let sampleEvents: [ICSEvent]
        let dateRange: DateRange?
        var error: Error?

        struct DateRange: Sendable {
            let earliest: Date
            let latest: Date
        }
    }

    // MARK: - Private Methods

    private func performFetch(url: URL, config: FetchConfig) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = config.timeout

        // Add custom headers
        for (key, value) in config.headers {
            // Expand environment variables in header values
            request.setValue(value.expandingEnvironmentVariables, forHTTPHeaderField: key)
        }

        // Add standard headers
        request.setValue("text/calendar, text/plain;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ics-calendar-sync/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ICSError.fetchFailed(url, NSError(domain: "Not HTTP", code: -1))
        }

        switch httpResponse.statusCode {
        case 200...299:
            break // Success
        case 401, 403:
            throw ICSError.authenticationRequired
        case 404:
            throw ICSError.fetchFailed(url, NSError(domain: "Not Found", code: 404))
        default:
            throw ICSError.invalidResponse(httpResponse.statusCode)
        }

        // Try to decode as UTF-8, fall back to Latin-1
        if let content = String(data: data, encoding: .utf8) {
            return content
        } else if let content = String(data: data, encoding: .isoLatin1) {
            logger.warning("ICS content was not UTF-8, decoded as Latin-1")
            return content
        } else {
            throw ICSError.parseError("Unable to decode ICS content")
        }
    }

    private func calculateDateRange(_ events: [ICSEvent]) -> ValidationResult.DateRange? {
        guard !events.isEmpty else { return nil }

        let startDates = events.map { $0.startDate }
        let endDates = events.map { $0.endDate }

        guard let earliest = startDates.min(),
              let latest = endDates.max() else {
            return nil
        }

        return ValidationResult.DateRange(earliest: earliest, latest: latest)
    }
}

// MARK: - Authentication Helper

extension ICSFetcher {
    /// Create fetch config with Bearer token authentication
    static func configWithBearerToken(_ token: String, timeout: TimeInterval = 30) -> FetchConfig {
        var config = FetchConfig()
        config.timeout = timeout
        config.headers["Authorization"] = "Bearer \(token)"
        return config
    }

    /// Create fetch config with Basic authentication
    static func configWithBasicAuth(username: String, password: String, timeout: TimeInterval = 30) -> FetchConfig {
        var config = FetchConfig()
        config.timeout = timeout

        let credentials = "\(username):\(password)"
        if let data = credentials.data(using: .utf8) {
            let encoded = data.base64EncodedString()
            config.headers["Authorization"] = "Basic \(encoded)"
        }

        return config
    }

    /// Create fetch config from environment variables
    static func configFromEnvironment(timeout: TimeInterval = 30) -> FetchConfig {
        var config = FetchConfig()
        config.timeout = timeout

        // Check for bearer token
        if let token = ProcessInfo.processInfo.environment["ICS_AUTH_TOKEN"] {
            config.headers["Authorization"] = "Bearer \(token)"
        }

        // Check for basic auth
        if let username = ProcessInfo.processInfo.environment["ICS_USERNAME"],
           let password = ProcessInfo.processInfo.environment["ICS_PASSWORD"] {
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                config.headers["Authorization"] = "Basic \(data.base64EncodedString())"
            }
        }

        return config
    }
}
