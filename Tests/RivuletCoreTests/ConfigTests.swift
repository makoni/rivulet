import XCTest
@testable import RivuletCore

final class ConfigTests: XCTestCase {
    // MARK: - Helpers

    private func environment(
        database: String? = "/tmp/rivulet-test.db",
        _ overrides: [String: String] = [:]
    ) -> [String: String] {
        var env = overrides
        if let database {
            env["DATABASE_URL"] = database
        }
        return env
    }

    // MARK: - Defaults

    func testLoadsDefaults() throws {
        let config = try Config.load(environment: environment())

        XCTAssertEqual(config.listenAddress, ListenAddress(host: "127.0.0.1", port: 8080))
        XCTAssertEqual(config.baseURL.absoluteString, "http://localhost")
        XCTAssertEqual(config.databasePath, "/tmp/rivulet-test.db")
        XCTAssertEqual(config.logLevel, .info)
        XCTAssertEqual(config.logFormat, .text)
        XCTAssertTrue(config.runMigrations)
    }

    func testIgnoresUnrelatedEnvironmentVariables() throws {
        let config = try Config.load(environment: environment([
            "PATH": "/usr/bin",
            "HOME": "/home/user",
        ]))

        XCTAssertEqual(config.databasePath, "/tmp/rivulet-test.db")
    }

    func testLoadsOverrides() throws {
        let config = try Config.load(environment: environment([
            "LISTEN_ADDR": "0.0.0.0:9999",
            "BASE_URL": "https://reader.example.com",
            "LOG_LEVEL": "debug",
            "LOG_FORMAT": "json",
            "RUN_MIGRATIONS": "0",
        ]))

        XCTAssertEqual(config.listenAddress, ListenAddress(host: "0.0.0.0", port: 9999))
        XCTAssertEqual(config.baseURL.absoluteString, "https://reader.example.com")
        XCTAssertEqual(config.logLevel, .debug)
        XCTAssertEqual(config.logFormat, .json)
        XCTAssertFalse(config.runMigrations)
    }

    // MARK: - DATABASE_URL

    func testMissingDatabaseURLFails() {
        XCTAssertThrowsError(try Config.load(environment: [:])) { error in
            XCTAssertEqual(error as? ConfigError, .missingRequiredVariable("DATABASE_URL"))
            XCTAssertTrue(String(describing: error).contains("DATABASE_URL"))
        }
    }

    func testEmptyDatabaseURLFails() {
        XCTAssertThrowsError(try Config.load(environment: environment(database: ""))) { error in
            XCTAssertEqual(error as? ConfigError, .missingRequiredVariable("DATABASE_URL"))
        }
    }

    func testDatabaseURLRejectsURLSchemes() {
        XCTAssertThrowsError(
            try Config.load(environment: environment(database: "postgres://user@host/miniflux"))
        ) { error in
            guard case .invalidValue("DATABASE_URL", _, let reason)? = error as? ConfigError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("file path"))
        }
    }

    // MARK: - LISTEN_ADDR

    func testListenAddressVariants() throws {
        let cases: [(value: String, host: String, port: Int)] = [
            ("127.0.0.1:8080", "127.0.0.1", 8080),
            ("0.0.0.0:9000", "0.0.0.0", 9000),
            (":9000", "0.0.0.0", 9000),
            ("[::1]:9000", "::1", 9000),
            ("localhost:1234", "localhost", 1234),
        ]

        for testCase in cases {
            let config = try Config.load(environment: environment([
                "LISTEN_ADDR": testCase.value,
            ]))
            XCTAssertEqual(
                config.listenAddress,
                ListenAddress(host: testCase.host, port: testCase.port),
                "for LISTEN_ADDR=\(testCase.value)"
            )
        }
    }

    func testListenAddressInvalidValues() {
        let invalidValues = [
            "127.0.0.1",               // missing port
            "127.0.0.1:0",             // port out of range
            "127.0.0.1:65536",         // port out of range
            "127.0.0.1:abc",           // non-numeric port
            "",                        // empty
            "127.0.0.1:8080 :8081",    // multiple listeners
            "127.0.0.1:8080 127.0.0.1:8081",
        ]

        for value in invalidValues {
            XCTAssertThrowsError(
                try Config.load(environment: environment(["LISTEN_ADDR": value])),
                "expected LISTEN_ADDR=\(value) to be rejected"
            ) { error in
                guard case .invalidValue("LISTEN_ADDR", _, _)? = error as? ConfigError else {
                    return XCTFail("unexpected error for \(value): \(error)")
                }
            }
        }
    }

    // MARK: - BASE_URL

    func testBaseURLMustBeAbsoluteHTTP() {
        let invalidValues = ["localhost", "ftp://example.com", "/relative", "example.com/reader"]
        for value in invalidValues {
            XCTAssertThrowsError(
                try Config.load(environment: environment(["BASE_URL": value])),
                "expected BASE_URL=\(value) to be rejected"
            )
        }

        XCTAssertNoThrow(try Config.load(environment: environment(["BASE_URL": "https://reader.example.com/rivulet"])))
    }

    // MARK: - LOG_LEVEL / LOG_FORMAT / RUN_MIGRATIONS

    func testLogLevelIsCaseInsensitive() throws {
        let config = try Config.load(environment: environment(["LOG_LEVEL": "INFO"]))
        XCTAssertEqual(config.logLevel, .info)
    }

    func testInvalidLogLevelFails() {
        XCTAssertThrowsError(try Config.load(environment: environment(["LOG_LEVEL": "bogus"]))) { error in
            guard case .invalidValue("LOG_LEVEL", "bogus", let reason)? = error as? ConfigError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("debug"))
        }
    }

    func testInvalidLogFormatFails() {
        XCTAssertThrowsError(try Config.load(environment: environment(["LOG_FORMAT": "yaml"]))) { error in
            guard case .invalidValue("LOG_FORMAT", "yaml", _)? = error as? ConfigError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRunMigrationsBooleanVariants() throws {
        let truthy = ["1", "t", "T", "true", "TRUE", "True"]
        for value in truthy {
            XCTAssertTrue(try Config.load(environment: environment(["RUN_MIGRATIONS": value])).runMigrations)
        }

        let falsy = ["0", "f", "F", "false", "FALSE", "False"]
        for value in falsy {
            XCTAssertFalse(try Config.load(environment: environment(["RUN_MIGRATIONS": value])).runMigrations)
        }
    }

    func testInvalidRunMigrationsFails() {
        XCTAssertThrowsError(try Config.load(environment: environment(["RUN_MIGRATIONS": "yes"]))) { error in
            guard case .invalidValue("RUN_MIGRATIONS", "yes", _)? = error as? ConfigError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
