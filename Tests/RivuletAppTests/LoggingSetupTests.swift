import Logging
import Testing
@testable import RivuletApp
import RivuletCore

@Suite struct LoggingSetupTests {
    @Test func textFormatBuildsAStreamLogHandlerWithTheConfiguredLevel() {
        let handler = LoggingSetup.makeHandler(label: "rivulet.tests", logLevel: .warning, format: .text)

        #expect(handler is StreamLogHandler)
        #expect(handler.logLevel == .warning)
    }

    @Test func jsonFormatBuildsAJSONLogHandlerWithTheConfiguredLevel() {
        let handler = LoggingSetup.makeHandler(label: "rivulet.tests", logLevel: .debug, format: .json)

        #expect(handler is JSONLogHandler)
        #expect(handler.logLevel == .debug)
    }

    @Test func configurationLogLevelsMapOntoSwiftLogLevels() {
        #expect(Logger.Level(Config.LogLevel.debug) == .debug)
        #expect(Logger.Level(Config.LogLevel.info) == .info)
        #expect(Logger.Level(Config.LogLevel.warning) == .warning)
        #expect(Logger.Level(Config.LogLevel.error) == .error)
    }
}
