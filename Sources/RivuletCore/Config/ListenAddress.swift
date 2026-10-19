import Foundation

/// A host and port pair the HTTP server listens on.
///
/// Mirrors Miniflux's `LISTEN_ADDR` for the single-address case: `127.0.0.1:8080`,
/// `:8080` (all interfaces), `[::1]:8080`. Upstream accepts a comma-separated list
/// (Unix socket paths included); Rivulet serves one TCP address and rejects lists
/// explicitly — see `docs/architecture.md`.
public struct ListenAddress: Equatable, Sendable, CustomStringConvertible {
    /// Bind host (`0.0.0.0` for all interfaces).
    public let host: String

    /// TCP port (`1...65535`).
    public let port: Int

    /// Creates an address.
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    /// `host:port`, with brackets around IPv6 hosts.
    public var description: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// Parses a `host:port` string as used by `LISTEN_ADDR`.
    ///
    /// Adapted from Miniflux `internal/config/parser.go` (`parseStringListValue`,
    /// Apache-2.0): one item; the comma-separated list form is rejected.
    static func parse(_ rawValue: String) throws -> ListenAddress {
        // Upstream reads a comma-separated list, trimming items and dropping empty ones;
        // Rivulet serves exactly one TCP address and rejects real lists.
        let items = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let value = items.first else {
            throw ConfigError.invalidValue(
                variable: "LISTEN_ADDR",
                value: rawValue,
                reason: "expected host:port"
            )
        }

        guard items.count == 1, !value.contains(" ") else {
            throw ConfigError.invalidValue(
                variable: "LISTEN_ADDR",
                value: rawValue,
                reason: "multiple listen addresses are not supported, provide a single host:port"
            )
        }

        guard let colon = value.lastIndex(of: ":") else {
            throw ConfigError.invalidValue(
                variable: "LISTEN_ADDR",
                value: rawValue,
                reason: "expected host:port"
            )
        }

        var host = String(value[value.startIndex..<colon])
        let portString = String(value[value.index(after: colon)...])

        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
            guard !host.isEmpty else {
                throw ConfigError.invalidValue(
                    variable: "LISTEN_ADDR",
                    value: rawValue,
                    reason: "empty IPv6 host"
                )
            }
        } else if host.contains(":") {
            throw ConfigError.invalidValue(
                variable: "LISTEN_ADDR",
                value: rawValue,
                reason: "IPv6 addresses must be bracketed, e.g. [::1]:8080"
            )
        } else if host.isEmpty {
            host = "0.0.0.0"
        }

        guard let port = Int(portString), (1...65535).contains(port) else {
            throw ConfigError.invalidValue(
                variable: "LISTEN_ADDR",
                value: rawValue,
                reason: "expected a port between 1 and 65535"
            )
        }

        return ListenAddress(host: host, port: port)
    }
}
