import Foundation
import Logging
import Synchronization
import XCTest
import RivuletApp

final class JSONLogHandlerTests: XCTestCase {
    func testWritesTheCoreFieldsAsOneJSONObject() throws {
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }

        logger.info("feed refreshed")

        let object = try XCTUnwrap(parseSingleLine(from: captured))
        XCTAssertEqual(object["level"] as? String, "info")
        XCTAssertEqual(object["label"] as? String, "rivulet.tests")
        XCTAssertEqual(object["message"] as? String, "feed refreshed")

        let timestamp = try XCTUnwrap(object["timestamp"] as? String, "timestamp is required")
        XCTAssertNotNil(
            try? Date.ISO8601FormatStyle().parse(timestamp),
            "timestamp must be ISO-8601: \(timestamp)"
        )
    }

    func testMergesHandlerAndCallMetadataWithTheCallWinning() throws {
        let captured = CapturedLines()
        var handler = JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        handler.metadata["component"] = "reader"
        handler.metadata["feed_id"] = "handler"
        let logger = Logger(label: "rivulet.tests") { _ in handler }

        logger.info("feed refreshed", metadata: ["feed_id": "call"])

        let object = try XCTUnwrap(parseSingleLine(from: captured))
        let metadata = try XCTUnwrap(object["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["component"] as? String, "reader")
        XCTAssertEqual(metadata["feed_id"] as? String, "call")
    }

    func testMergesProviderMetadataOverHandlerAndUnderTheCall() throws {
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
        XCTAssertEqual(objects.count, 2)
        let providerWins = try XCTUnwrap(objects.first?["metadata"] as? [String: Any])
        XCTAssertEqual(providerWins["component"] as? String, "reader")
        XCTAssertEqual(providerWins["provider_key"] as? String, "provider")
        XCTAssertEqual(providerWins["feed_id"] as? String, "provider", "the provider overrides handler metadata")
        let callWins = try XCTUnwrap(objects.last?["metadata"] as? [String: Any])
        XCTAssertEqual(callWins["feed_id"] as? String, "call", "call metadata overrides the provider")
    }

    func testOmitsMetadataWhenThereIsNone() throws {
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }

        logger.info("plain")

        let object = try XCTUnwrap(parseSingleLine(from: captured))
        XCTAssertNil(object["metadata"])
    }

    func testProjectsMetadataValuesIntoJSON() throws {
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

        let object = try XCTUnwrap(parseSingleLine(from: captured))
        let metadata = try XCTUnwrap(object["metadata"] as? [String: Any])
        XCTAssertEqual((metadata["count"] as? NSNumber)?.intValue, 42)
        XCTAssertEqual((metadata["enabled"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual(metadata["tags"] as? [String], ["a", "b"])
        XCTAssertEqual((metadata["nested"] as? [String: Any])?["key"] as? String, "value")
    }

    func testKeepsNonFiniteNumbersEncodableAsText() throws {
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

        let object = try XCTUnwrap(parseSingleLine(from: captured))
        XCTAssertEqual(object["message"] as? String, "stats", "the record must not fall back to the emergency line")
        let metadata = try XCTUnwrap(object["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["ratio"] as? String, "nan")
        XCTAssertEqual(metadata["limit"] as? String, "inf")
    }

    func testIncludesTheErrorDescription() throws {
        struct Failure: Error, CustomStringConvertible {
            var description: String { "boom" }
        }
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }

        logger.error("refresh failed", error: Failure())

        let object = try XCTUnwrap(parseSingleLine(from: captured))
        XCTAssertEqual(object["error"] as? String, "boom")
    }

    func testDropsRecordsBelowTheConfiguredLevel() throws {
        let captured = CapturedLines()
        let handler = JSONLogHandler(label: "rivulet.tests", logLevel: .warning, write: captured.append)
        let logger = Logger(label: "rivulet.tests") { _ in handler }

        logger.info("filtered")
        logger.warning("kept")

        let objects = try parsedLines(from: captured)
        XCTAssertEqual(objects.count, 1)
        XCTAssertEqual(objects.first?["level"] as? String, "warning")
    }

    func testEscapesControlCharactersIntoASingleValidLine() throws {
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }
        let message = "quote:\" backslash:\\ newline:\n tab:\t emoji:🎉"

        logger.info(Logger.Message(stringLiteral: message))

        let objects = try parsedLines(from: captured)
        XCTAssertEqual(objects.count, 1, "a message with newlines must stay on one line")
        XCTAssertEqual(objects.first?["message"] as? String, message)
    }

    // MARK: - Helpers

    /// Decodes the single captured write.
    private func parseSingleLine(from captured: CapturedLines) throws -> [String: Any] {
        let objects = try parsedLines(from: captured)
        XCTAssertEqual(objects.count, 1)
        return try XCTUnwrap(objects.first)
    }

    /// Decodes every captured write, pinning the wire contract: each write is one JSON
    /// object terminated by a newline.
    private func parsedLines(from captured: CapturedLines) throws -> [[String: Any]] {
        try captured.lines.map { write in
            XCTAssertTrue(write.hasSuffix("\n"), "each write must end with a newline: \(write.debugDescription)")
            let line = String(write.dropLast())
            XCTAssertFalse(line.contains("\n"), "one JSON object per line: \(write.debugDescription)")
            return try XCTUnwrap(
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
