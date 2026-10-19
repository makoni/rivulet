import Foundation

/// A host and port pair the HTTP server listens on.
///
/// Mirrors Miniflux's `LISTEN_ADDR`: `127.0.0.1:8080`, `:8080` (all interfaces),
/// `[::1]:8080`. The upstream value is a whitespace-separated list; Rivulet currently
/// serves a single address and rejects lists explicitly.
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

    public var description: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// Parses a `host:port` string as used by `LISTEN_ADDR`.
    static func parse(_ rawValue: String) throws -> ListenAddress {
        let value = rawValue.trimmingCharacters(in: .whitespaces)

        guard !value.contains(" "), !value.contains(",") else {
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
        }
        if host.isEmpty {
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
