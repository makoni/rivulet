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

        let lines = captured.lines
        XCTAssertEqual(lines.count, 1)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(try XCTUnwrap(lines.first).utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["level"] as? String, "warning")
    }

    func testEscapesControlCharactersIntoASingleValidLine() throws {
        let captured = CapturedLines()
        let logger = Logger(label: "rivulet.tests") { _ in
            JSONLogHandler(label: "rivulet.tests", logLevel: .trace, write: captured.append)
        }
        let message = "quote:\" backslash:\\ newline:\n tab:\t emoji:🎉"

        logger.info(Logger.Message(stringLiteral: message))

        let lines = captured.lines
        XCTAssertEqual(lines.count, 1, "a message with newlines must stay on one line")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(try XCTUnwrap(lines.first).utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["message"] as? String, message)
    }

    // MARK: - Helpers

    private func parseSingleLine(from captured: CapturedLines) throws -> [String: Any] {
        let lines = captured.lines
        XCTAssertEqual(lines.count, 1)
        let line = try XCTUnwrap(lines.first)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            "not a JSON object: \(line)"
        )
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
