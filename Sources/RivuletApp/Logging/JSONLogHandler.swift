import Foundation
import Logging

/// A swift-log handler that writes one JSON object per line.
///
/// The record layout is `timestamp` (ISO-8601, UTC), `level`, `label`, `message` and,
/// when present, `error` and `metadata`. Used for `LOG_FORMAT=json`
/// (see ``LoggingSetup``).
public struct JSONLogHandler: LogHandler {
    /// See `LogHandler.logLevel`.
    public var logLevel: Logger.Level

    /// See `LogHandler.metadataProvider`.
    public var metadataProvider: Logger.MetadataProvider?

    /// See `LogHandler.metadata`.
    public var metadata: Logger.Metadata = [:]

    private let label: String
    private let write: @Sendable (String) -> Void

    /// Creates a handler that hands complete lines (including the trailing newline)
    /// to `write`.
    ///
    /// - Parameters:
    ///   - label: Logger label reported in every record.
    ///   - logLevel: Minimum level the handler emits.
    ///   - write: Sink for the finished lines.
    public init(label: String, logLevel: Logger.Level, write: @escaping @Sendable (String) -> Void) {
        self.label = label
        self.logLevel = logLevel
        self.write = write
    }

    /// See `LogHandler.subscript(metadataKey:)`.
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    /// See `LogHandler.log(event:)`.
    public func log(event: LogEvent) {
        let record = Record(
            timestamp: Date().formatted(.iso8601),
            level: event.level.rawValue,
            label: label,
            message: event.message.description,
            error: event.error.map { String(describing: $0) },
            metadata: mergedMetadata(callMetadata: event.metadata)
                .map { JSONValue.object($0.mapValues(JSONValue.init)) }
        )
        guard let data = try? Self.makeEncoder().encode(record),
              let json = String(data: data, encoding: .utf8)
        else {
            // Records hold only strings and JSON-representable metadata values, so this
            // cannot normally happen; keep the failure visible instead of dropping a line.
            write(Self.fallbackLine(label: label) + "\n")
            return
        }
        write(json + "\n")
    }

    /// The emergency line for a record that refused to encode: still this handler's label,
    /// still one JSON object on one line. The static line covers the (unreachable) case of
    /// the emergency record itself failing to encode.
    private static func fallbackLine(label: String) -> String {
        let record = Record(
            timestamp: Date().formatted(.iso8601),
            level: "error",
            label: label,
            message: "could not encode a log record",
            error: nil,
            metadata: nil
        )
        guard let data = try? makeEncoder().encode(record),
              let json = String(data: data, encoding: .utf8)
        else {
            return #"{"level":"error","message":"could not encode a log record"}"#
        }
        return json
    }

    /// Handler, provider and call metadata merged in that order; the call wins on conflicts.
    private func mergedMetadata(callMetadata: Logger.Metadata?) -> Logger.Metadata? {
        var merged = metadata
        if let providerMetadata = metadataProvider?.get() {
            merged.merge(providerMetadata) { _, provider in provider }
        }
        if let callMetadata {
            merged.merge(callMetadata) { _, call in call }
        }
        return merged.isEmpty ? nil : merged
    }

    /// A fresh encoder per record: `JSONEncoder` is not `Sendable` and log lines are not
    /// on a hot path.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// One log line.
    private struct Record: Encodable {
        let timestamp: String
        let level: String
        let label: String
        let message: String
        let error: String?
        let metadata: JSONValue?
    }

    /// A JSON-representable projection of ``Logger/MetadataValue`` (which is not `Codable`).
    private enum JSONValue: Encodable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case array([JSONValue])
        case object([String: JSONValue])

        init(_ value: Logger.MetadataValue) {
            switch value {
            case .string(let string):
                self = .string(string)
            case .stringConvertible(let convertible):
                if let bool = convertible as? Bool {
                    self = .bool(bool)
                } else if let int = convertible as? Int {
                    self = .number(Double(int))
                } else if let double = convertible as? Double {
                    // JSON has no NaN or infinity; keep the record encodable as text.
                    self = double.isFinite ? .number(double) : .string(String(double))
                } else {
                    self = .string(convertible.description)
                }
            case .dictionary(let dictionary):
                self = .object(dictionary.mapValues(JSONValue.init))
            case .array(let array):
                self = .array(array.map(JSONValue.init))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let string): try container.encode(string)
            case .number(let number): try container.encode(number)
            case .bool(let bool): try container.encode(bool)
            case .array(let array): try container.encode(array)
            case .object(let object): try container.encode(object)
            }
        }
    }
}
