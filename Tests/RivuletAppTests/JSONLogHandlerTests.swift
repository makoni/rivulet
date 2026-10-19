import Foundation
import Logging
import Synchronization
import Testing
import RivuletApp

@Suite struct JSONLogHandlerTests {
    @Test func writesTheCoreFieldsAsOneJSONObject() throws {
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }

        logger.info("feed refreshed")

        let object = try parseSingleLine(from: captured)
        #expect(object["level"] as? String == "info")
        #expect(object["label"] as? String == "rivulet.tests")
        #expect(object["message"] as? String == "feed refreshed")

        let timestamp = try #require(object["timestamp"] as? String, "timestamp is required")
        #expect(
            (try? Date.ISO8601FormatStyle().parse(timestamp)) != nil,
            "timestamp must be ISO-8601: \(timestamp)"
        )
    }

    @Test func mergesHandlerAndCallMetadataWithTheCallWinning() throws {
        let captured = CapturedLines()
        var handler = JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        handler.metadata["component"] = "reader"
        handler.metadata["feed_id"] = "handler"
        let logger = Logger(label: "rivulet.tests") { _ in handler }

        logger.info("feed refreshed", metadata: ["feed_id": "call"])

        let object = try parseSingleLine(from: captured)
        let metadata = try #require(object["metadata"] as? [String: Any])
        #expect(metadata["component"] as? String == "reader")
        #expect(metadata["feed_id"] as? String == "call")
    }

    @Test func mergesProviderMetadataOverHandlerAndUnderTheCall() throws {
        let captured = CapturedLines()
        var handler = JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        handler.metadata["component"] = "reader"
        handler.metadata["feed_id"] = "handler"
        handler.metadataProvider = Logger.MetadataProvider {
            ["provider_key": "provider", "feed_id": "provider"]
        }
        let logger = Logger(label: "rivulet.tests") { _ in handler }

        logger.info("without call metadata")
        logger.info("with call metadata", metadata: ["feed_id": "call"])

        let objects = try parsedLines(from: captured)
        #expect(objects.count == 2)
        let providerWins = try #require(objects.first?["metadata"] as? [String: Any])
        #expect(providerWins["component"] as? String == "reader")
        #expect(providerWins["provider_key"] as? String == "provider")
        #expect(providerWins["feed_id"] as? String == "provider", "the provider overrides handler metadata")
        let callWins = try #require(objects.last?["metadata"] as? [String: Any])
        #expect(callWins["feed_id"] as? String == "call", "call metadata overrides the provider")
    }

    @Test func omitsMetadataWhenThereIsNone() throws {
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }

        logger.info("plain")

        let object = try parseSingleLine(from: captured)
        #expect(object["metadata"] == nil)
    }

    @Test func projectsMetadataValuesIntoJSON() throws {
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }

        logger.info(
            "mixed",
            metadata: [
                "count": .stringConvertible(42),
                "enabled": .stringConvertible(true),
                "tags": .array([.string("a"), .string("b")]),
                "nested": .dictionary(["key": .string("value")]),
            ]
        )

        let object = try parseSingleLine(from: captured)
        let metadata = try #require(object["metadata"] as? [String: Any])
        #expect((metadata["count"] as? NSNumber)?.intValue == 42)
        #expect((metadata["enabled"] as? NSNumber)?.boolValue == true)
        #expect(metadata["tags"] as? [String] == ["a", "b"])
        #expect((metadata["nested"] as? [String: Any])?["key"] as? String == "value")
    }

    @Test func keepsNonFiniteNumbersEncodableAsText() throws {
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }

        logger.info(
            "stats",
            metadata: [
                "ratio": .stringConvertible(Double.nan),
                "limit": .stringConvertible(Double.infinity),
            ]
        )

        let object = try parseSingleLine(from: captured)
        #expect(object["message"] as? String == "stats", "the record must not fall back to the emergency line")
        let metadata = try #require(object["metadata"] as? [String: Any])
        #expect(metadata["ratio"] as? String == "nan")
        #expect(metadata["limit"] as? String == "inf")
    }

    @Test func includesTheErrorDescription() throws {
        struct Failure: Error, CustomStringConvertible {
            var description: String { "boom" }
        }
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }

        logger.error("refresh failed", error: Failure())

        let object = try parseSingleLine(from: captured)
        #expect(object["error"] as? String == "boom")
    }

    @Test func dropsRecordsBelowTheConfiguredLevel() throws {
        let captured = CapturedLines()
        let handler = JSONLogHandler(label: "rivulet.tests", logLevel: .warning, write: captured.append)
        let logger = Logger(label: "rivulet.tests") { _ in handler }

        logger.info("filtered")
        logger.warning("kept")

        let objects = try parsedLines(from: captured)
        #expect(objects.count == 1)
        #expect(objects.first?["level"] as? String == "warning")
    }

    @Test func escapesControlCharactersIntoASingleValidLine() throws {
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }
        let message = "quote:\" backslash:\\ newline:\n tab:\t emoji:🎉"

        logger.info(Logger.Message(stringLiteral: message))

        let objects = try parsedLines(from: captured)
        #expect(objects.count == 1, "a message with newlines must stay on one line")
        #expect(objects.first?["message"] as? String == message)
    }

    // MARK: - Helpers

    /// Decodes the single captured write.
    private func parseSingleLine(from captured: CapturedLines) throws -> [String: Any] {
        let objects = try parsedLines(from: captured)
        #expect(objects.count == 1)
        return try #require(objects.first)
    }

    /// Decodes every captured write, pinning the wire contract: each write is one JSON
    /// object terminated by a newline.
    private func parsedLines(from captured: CapturedLines) throws -> [[String: Any]] {
        try captured.lines.map { write in
            #expect(write.hasSuffix("\n"), "each write must end with a newline: \(write.debugDescription)")
            let line = String(write.dropLast())
            #expect(!line.contains("\n"), "one JSON object per line: \(write.debugDescription)")
            return try #require(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                "not a JSON object: \(line)"
            )
        }
    }
}

/// Collects the lines a handler writes, thread-safe because `LogHandler.write` is `@Sendable`.
private final class CapturedLines: Sendable {
    private let storage = Mutex<[String]>([])

    func append(_ line: String) {
        storage.withLock { $0.append(line) }
    }

    var lines: [String] {
        storage.withLock { $0 }
    }
}
