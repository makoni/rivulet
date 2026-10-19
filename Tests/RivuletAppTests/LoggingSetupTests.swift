import Logging
import XCTest
@testable import RivuletApp
import RivuletCore

final class LoggingSetupTests: XCTestCase {
    func testTextFormatBuildsAStreamLogHandlerWithTheConfiguredLevel() {
        let handler = LoggingSetup.makeHandler(label: "rivulet.tests", logLevel: .warning, format: .text)

        XCTAssertTrue(handler is StreamLogHandler)
        XCTAssertEqual(handler.logLevel, .warning)
    }

    func testJSONFormatBuildsAJSONLogHandlerWithTheConfiguredLevel() {
        let handler = LoggingSetup.makeHandler(label: "rivulet.tests", logLevel: .debug, format: .json)

        XCTAssertTrue(handler is JSONLogHandler)
        XCTAssertEqual(handler.logLevel, .debug)
    }

    func testConfigurationLogLevelsMapOntoSwiftLogLevels() {
        XCTAssertEqual(Logger.Level(Config.LogLevel.debug), .debug)
        XCTAssertEqual(Logger.Level(Config.LogLevel.info), .info)
        XCTAssertEqual(Logger.Level(Config.LogLevel.warning), .warning)
        XCTAssertEqual(Logger.Level(Config.LogLevel.error), .error)
    }
}
