import Foundation

/// Rivulet configuration loaded from environment variables.
///
/// Variable names mirror Miniflux where a single value maps cleanly; deviations are
/// documented in `docs/architecture.md` (`DATABASE_URL` is required and points to a
/// SQLite file, `RUN_MIGRATIONS` defaults to `true`).
public struct Config: Sendable, Equatable {
    /// Log verbosity. Matches the Miniflux choices.
    public enum LogLevel: String, Sendable, CaseIterable {
        case debug, info, warning, error
    }

    /// Log output format.
    public enum LogFormat: String, Sendable, CaseIterable {
        case text, json
    }

    /// Address the HTTP server binds to (`LISTEN_ADDR`).
    public let listenAddress: ListenAddress

    /// Public base URL used in generated links (`BASE_URL`).
    public let baseURL: URL

    /// Path to the SQLite database file (`DATABASE_URL`).
    public let databasePath: String

    /// Minimum log level (`LOG_LEVEL`).
    public let logLevel: LogLevel

    /// Log output format (`LOG_FORMAT`).
    public let logFormat: LogFormat

    /// Whether `serve` applies pending migrations at startup (`RUN_MIGRATIONS`).
    public let runMigrations: Bool

    /// Creates a configuration value.
    public init(
        listenAddress: ListenAddress,
        baseURL: URL,
        databasePath: String,
        logLevel: LogLevel,
        logFormat: LogFormat,
        runMigrations: Bool
    ) {
        self.listenAddress = listenAddress
        self.baseURL = baseURL
        self.databasePath = databasePath
        self.logLevel = logLevel
        self.logFormat = logFormat
        self.runMigrations = runMigrations
    }

    /// Loads the configuration from an environment dictionary.
    ///
    /// Unknown variables are ignored. Missing optional variables fall back to the
    /// Miniflux-compatible defaults.
    ///
    /// - Throws: ``ConfigError`` when a required variable is missing or a value is invalid.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Config {
        let databasePath = try requiredNonEmpty("DATABASE_URL", in: environment)
        guard !databasePath.contains("://") else {
            throw ConfigError.invalidValue(
                variable: "DATABASE_URL",
                value: databasePath,
                reason: "Rivulet stores data in SQLite, DATABASE_URL must be a file path"
            )
        }

        let listenAddress = try environment["LISTEN_ADDR"].map(ListenAddress.parse)
            ?? ListenAddress(host: "127.0.0.1", port: 8080)

        let baseURL = try parseBaseURL(environment["BASE_URL"])

        let logLevel = try parseEnum(
            LogLevel.self,
            variable: "LOG_LEVEL",
            value: environment["LOG_LEVEL"],
            fallback: .info
        )
        let logFormat = try parseEnum(
            LogFormat.self,
            variable: "LOG_FORMAT",
            value: environment["LOG_FORMAT"],
            fallback: .text
        )

        let runMigrations = try parseBoolean(
            variable: "RUN_MIGRATIONS",
            value: environment["RUN_MIGRATIONS"],
            fallback: true
        )

        return Config(
            listenAddress: listenAddress,
            baseURL: baseURL,
            databasePath: databasePath,
            logLevel: logLevel,
            logFormat: logFormat,
            runMigrations: runMigrations
        )
    }

    // MARK: - Parsing helpers

    private static func requiredNonEmpty(
        _ variable: String,
        in environment: [String: String]
    ) throws -> String {
        guard let value = environment[variable], !value.isEmpty else {
            throw ConfigError.missingRequiredVariable(variable)
        }
        return value
    }

    private static func parseBaseURL(_ rawValue: String?) throws -> URL {
        let fallback = URL(string: "http://localhost")!
        guard let rawValue else {
            return fallback
        }

        guard
            let url = URL(string: rawValue),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            throw ConfigError.invalidValue(
                variable: "BASE_URL",
                value: rawValue,
                reason: "expected an absolute http(s) URL"
            )
        }
        return url
    }

    private static func parseEnum<Value: RawRepresentable & CaseIterable>(
        _ type: Value.Type,
        variable: String,
        value: String?,
        fallback: Value
    ) throws -> Value where Value.RawValue == String {
        guard let value else {
            return fallback
        }
        let normalized = value.lowercased()
        guard let parsed = Value(rawValue: normalized) else {
            let allowed = Value.allCases.map(\.rawValue).joined(separator: ", ")
            throw ConfigError.invalidValue(
                variable: variable,
                value: value,
                reason: "expected one of: \(allowed)"
            )
        }
        return parsed
    }

    /// Parses booleans the way Go's `strconv.ParseBool` does, so existing Miniflux
    /// `.env` files keep working.
    private static func parseBoolean(
        variable: String,
        value: String?,
        fallback: Bool
    ) throws -> Bool {
        guard let value else {
            return fallback
        }
        switch value {
        case "1", "t", "T", "true", "TRUE", "True":
            return true
        case "0", "f", "F", "false", "FALSE", "False":
            return false
        default:
            throw ConfigError.invalidValue(
                variable: variable,
                value: value,
                reason: "expected a boolean (1/0, true/false)"
            )
        }
    }
}
