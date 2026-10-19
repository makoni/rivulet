import Foundation

/// Rivulet configuration loaded from environment variables.
///
/// Variable names mirror Miniflux where a single value maps cleanly. Parsing follows the
/// upstream semantics (`internal/config/parser.go`): empty values mean "unset" and fall
/// back to the defaults; booleans accept `1/yes/true/on` and `0/no/false/off`
/// (case-insensitive). The deliberate deviations are listed in `docs/architecture.md`
/// (`DATABASE_URL` is required and points to a SQLite file, `RUN_MIGRATIONS` defaults to
/// `true`, `LISTEN_ADDR` accepts a single TCP address).
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
    /// Unknown variables are ignored. Empty values mean "unset" (Miniflux semantics) and
    /// fall back to the defaults; `DATABASE_URL` is the only required variable.
    ///
    /// - Throws: ``ConfigError`` when a required variable is missing or a value is invalid.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Config {
        Config(
            listenAddress: try parseListenAddress(environment["LISTEN_ADDR"]),
            baseURL: try parseBaseURL(environment["BASE_URL"]),
            databasePath: try parseDatabasePath(environment["DATABASE_URL"]),
            logLevel: try parseEnum(
                LogLevel.self,
                variable: "LOG_LEVEL",
                value: environment["LOG_LEVEL"],
                fallback: .info
            ),
            logFormat: try parseEnum(
                LogFormat.self,
                variable: "LOG_FORMAT",
                value: environment["LOG_FORMAT"],
                fallback: .text
            ),
            runMigrations: try parseBoolean(
                variable: "RUN_MIGRATIONS",
                value: environment["RUN_MIGRATIONS"],
                fallback: true
            )
        )
    }

    // MARK: - Parsing helpers

    /// `DATABASE_URL` is required, names a SQLite file and must not carry a URL scheme.
    private static func parseDatabasePath(_ rawValue: String?) throws -> String {
        let value = (rawValue ?? "").trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else {
            throw ConfigError.missingRequiredVariable("DATABASE_URL")
        }
        guard value.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) == nil else {
            throw ConfigError.invalidValue(
                variable: "DATABASE_URL",
                value: value,
                reason: "Rivulet stores data in SQLite, DATABASE_URL must be a file path"
            )
        }
        return value
    }

    /// `LISTEN_ADDR`; the Miniflux default is a single loopback listener.
    private static func parseListenAddress(_ rawValue: String?) throws -> ListenAddress {
        guard let rawValue, !rawValue.isEmpty else {
            return ListenAddress(host: "127.0.0.1", port: 8080)
        }
        return try ListenAddress.parse(rawValue)
    }

    /// `BASE_URL`; http(s) only, a single trailing slash is trimmed like upstream.
    private static func parseBaseURL(_ rawValue: String?) throws -> URL {
        let fallback = URL(string: "http://localhost")!
        guard let rawValue, !rawValue.isEmpty else {
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

        let trimmed = rawValue.hasSuffix("/") ? String(rawValue.dropLast()) : rawValue
        return URL(string: trimmed) ?? url
    }

    /// Parses a case-insensitive choice value; empty means "unset".
    private static func parseEnum<Value: RawRepresentable & CaseIterable>(
        _ type: Value.Type,
        variable: String,
        value: String?,
        fallback: Value
    ) throws -> Value where Value.RawValue == String {
        guard let value, !value.isEmpty else {
            return fallback
        }
        guard let parsed = Value(rawValue: value.lowercased()) else {
            let allowed = Value.allCases.map(\.rawValue).joined(separator: ", ")
            throw ConfigError.invalidValue(
                variable: variable,
                value: value,
                reason: "expected one of: \(allowed)"
            )
        }
        return parsed
    }

    /// Parses booleans the way Miniflux does.
    ///
    /// Ported from Miniflux `internal/config/parser.go` (`parseBoolValue`, Apache-2.0);
    /// adapted for Swift. Empty values fall back to the default.
    private static func parseBoolean(
        variable: String,
        value: String?,
        fallback: Bool
    ) throws -> Bool {
        guard let value, !value.isEmpty else {
            return fallback
        }
        switch value.lowercased() {
        case "1", "yes", "true", "on":
            return true
        case "0", "no", "false", "off":
            return false
        default:
            throw ConfigError.invalidValue(
                variable: variable,
                value: value,
                reason: "expected a boolean (1/0, true/false, yes/no, on/off)"
            )
        }
    }
}
