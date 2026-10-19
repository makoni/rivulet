import Testing
@testable import RivuletCore

@Suite struct ConfigTests {
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

    /// Loads `environment`, expecting `Config.load` to fail: returns the thrown
    /// `ConfigError`, recording an issue for any other outcome.
    private func configError(
        from environment: [String: String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> ConfigError? {
        do {
            _ = try Config.load(environment: environment)
            Issue.record("expected loading the configuration to fail", sourceLocation: sourceLocation)
            return nil
        } catch let error as ConfigError {
            return error
        } catch {
            Issue.record("unexpected error: \(error)", sourceLocation: sourceLocation)
            return nil
        }
    }

    // MARK: - Defaults

    @Test func loadsDefaults() throws {
        let config = try Config.load(environment: environment())

        #expect(config.listenAddress == ListenAddress(host: "127.0.0.1", port: 8080))
        #expect(config.baseURL.absoluteString == "http://localhost")
        #expect(config.databasePath == "/tmp/rivulet-test.db")
        #expect(config.logLevel == .info)
        #expect(config.logFormat == .text)
        #expect(config.runMigrations)
    }

    @Test func emptyOptionalValuesFallBackToDefaults() throws {
        // Miniflux treats empty values as "unset" (parseStringValue/parseBoolValue).
        let config = try Config.load(environment: environment([
            "LISTEN_ADDR": "",
            "BASE_URL": "",
            "RUN_MIGRATIONS": "",
        ]))

        #expect(config.listenAddress == ListenAddress(host: "127.0.0.1", port: 8080))
        #expect(config.baseURL.absoluteString == "http://localhost")
        #expect(config.logLevel == .info)
        #expect(config.logFormat == .text)
        #expect(config.runMigrations)
    }

    @Test func whitespaceOnlyValuesFallBackToDefaults() throws {
        // Upstream trims values before the empty check (parseLines).
        let config = try Config.load(environment: environment([
            "LISTEN_ADDR": "   ",
            "BASE_URL": "   ",
            "RUN_MIGRATIONS": "   ",
        ]))

        #expect(config.listenAddress == ListenAddress(host: "127.0.0.1", port: 8080))
        #expect(config.baseURL.absoluteString == "http://localhost")
        #expect(config.runMigrations)
    }

    @Test func emptyLogLevelAndFormatAreRejected() {
        // Upstream runs the choices validator before the empty-value fallback.
        for variable in ["LOG_LEVEL", "LOG_FORMAT"] {
            for value in ["", "   "] {
                let payload = configError(from: environment([variable: value]))?.invalidValuePayload
                #expect(
                    payload?.name == variable,
                    "expected \(variable)=\(value.debugDescription) to be rejected"
                )
            }
        }
    }

    @Test func ignoresUnrelatedEnvironmentVariables() throws {
        let config = try Config.load(environment: environment([
            "PATH": "/usr/bin",
            "HOME": "/home/user",
        ]))

        #expect(config.databasePath == "/tmp/rivulet-test.db")
    }

    @Test func loadsOverrides() throws {
        let config = try Config.load(environment: environment([
            "LISTEN_ADDR": "0.0.0.0:9999",
            "BASE_URL": "https://reader.example.com",
            "LOG_LEVEL": "debug",
            "LOG_FORMAT": "json",
            "RUN_MIGRATIONS": "0",
        ]))

        #expect(config.listenAddress == ListenAddress(host: "0.0.0.0", port: 9999))
        #expect(config.baseURL.absoluteString == "https://reader.example.com")
        #expect(config.logLevel == .debug)
        #expect(config.logFormat == .json)
        #expect(!config.runMigrations)
    }

    // MARK: - DATABASE_URL

    @Test func missingDatabaseURLFails() throws {
        let error = try #require(configError(from: [:]))
        #expect(error == .missingRequiredVariable("DATABASE_URL"))
        #expect(String(describing: error).contains("DATABASE_URL"))
    }

    @Test func emptyDatabaseURLFails() throws {
        let error = try #require(configError(from: environment(database: "")))
        #expect(error == .missingRequiredVariable("DATABASE_URL"))
    }

    @Test func databaseURLIsTrimmed() throws {
        let config = try Config.load(environment: environment(database: "  /tmp/rivulet.db  "))
        #expect(config.databasePath == "/tmp/rivulet.db")
    }

    @Test func databaseURLRejectsURLSchemes() {
        for value in ["postgres://user@host/miniflux", "mysql://host/db"] {
            let payload = configError(from: environment(database: value))?.invalidValuePayload
            #expect(payload?.name == "DATABASE_URL", "expected DATABASE_URL=\(value) to be rejected")
            #expect(payload?.reason.contains("file path") == true)
        }
    }

    // MARK: - LISTEN_ADDR

    @Test func listenAddressVariants() throws {
        let cases: [(value: String, host: String, port: Int)] = [
            ("127.0.0.1:8080", "127.0.0.1", 8080),
            ("0.0.0.0:9000", "0.0.0.0", 9000),
            (":9000", "0.0.0.0", 9000),
            ("[::1]:9000", "::1", 9000),
            ("localhost:1234", "localhost", 1234),
            // Miniflux trims list items and drops empty ones; we accept the same input.
            (" 127.0.0.1:8080 ", "127.0.0.1", 8080),
            ("127.0.0.1:8080,", "127.0.0.1", 8080),
        ]

        for testCase in cases {
            let config = try Config.load(environment: environment([
                "LISTEN_ADDR": testCase.value,
            ]))
            #expect(
                config.listenAddress == ListenAddress(host: testCase.host, port: testCase.port),
                "for LISTEN_ADDR=\(testCase.value)"
            )
        }
    }

    @Test func listenAddressInvalidValues() {
        let invalidValues = [
            "127.0.0.1",               // missing port
            "127.0.0.1:0",             // port out of range
            "127.0.0.1:65536",         // port out of range
            "127.0.0.1:abc",           // non-numeric port
            "127.0.0.1:8080 :8081",    // multiple listeners
            "127.0.0.1:8080,127.0.0.1:8081",
            "::1",                     // IPv6 without brackets
            "2001:db8::1",             // IPv6 without brackets
            "[::1]",                   // IPv6 without port
            "[]:8080",                 // empty IPv6 host
        ]

        for value in invalidValues {
            let payload = configError(from: environment(["LISTEN_ADDR": value]))?.invalidValuePayload
            #expect(payload?.name == "LISTEN_ADDR", "expected LISTEN_ADDR=\(value) to be rejected")
        }
    }

    // MARK: - BASE_URL

    @Test func baseURLMustBeAbsoluteHTTP() {
        let invalidValues = ["localhost", "ftp://example.com", "/relative", "example.com/reader"]
        for value in invalidValues {
            #expect(throws: ConfigError.self, "expected BASE_URL=\(value) to be rejected") {
                try Config.load(environment: environment(["BASE_URL": value]))
            }
        }

        #expect(throws: Never.self) {
            try Config.load(environment: environment(["BASE_URL": "https://reader.example.com/rivulet"]))
        }
    }

    @Test func baseURLTrailingSlashIsTrimmed() throws {
        // Miniflux trims the value and strips a single trailing slash (strings.TrimSuffix).
        let cases = [
            ("https://example.com/", "https://example.com"),
            ("https://example.com/app/", "https://example.com/app"),
            ("https://example.com/app//", "https://example.com/app/"),
            (" https://example.com/ ", "https://example.com"),
        ]

        for (value, expected) in cases {
            let config = try Config.load(environment: environment(["BASE_URL": value]))
            #expect(config.baseURL.absoluteString == expected, "for BASE_URL=\(value)")
        }
    }

    // MARK: - LOG_LEVEL / LOG_FORMAT / RUN_MIGRATIONS

    @Test func logLevelIsCaseInsensitiveAndTrimmed() throws {
        let config = try Config.load(environment: environment(["LOG_LEVEL": " INFO "]))
        #expect(config.logLevel == .info)
    }

    @Test func invalidLogLevelFails() {
        let payload = configError(from: environment(["LOG_LEVEL": "bogus"]))?.invalidValuePayload
        #expect(payload?.name == "LOG_LEVEL")
        #expect(payload?.value == "bogus")
        #expect(payload?.reason.contains("debug") == true)
    }

    @Test func invalidLogFormatFails() {
        let payload = configError(from: environment(["LOG_FORMAT": "yaml"]))?.invalidValuePayload
        #expect(payload?.name == "LOG_FORMAT")
        #expect(payload?.value == "yaml")
    }

    @Test func runMigrationsBooleanVariants() throws {
        // Miniflux parseBoolValue: case-insensitive 1/yes/true/on and 0/no/false/off.
        let truthy = ["1", "yes", "true", "on", "TRUE", "Yes", "ON", " yes "]
        for value in truthy {
            let config = try Config.load(environment: environment(["RUN_MIGRATIONS": value]))
            #expect(config.runMigrations, "for RUN_MIGRATIONS=\(value)")
        }

        let falsy = ["0", "no", "false", "off", "FALSE", "No", "OFF", " off "]
        for value in falsy {
            let config = try Config.load(environment: environment(["RUN_MIGRATIONS": value]))
            #expect(!config.runMigrations, "for RUN_MIGRATIONS=\(value)")
        }
    }

    @Test func invalidRunMigrationsFails() {
        // `t`/`f` are Go strconv values that Miniflux rejects.
        for value in ["t", "f", "maybe"] {
            let payload = configError(from: environment(["RUN_MIGRATIONS": value]))?.invalidValuePayload
            #expect(payload?.name == "RUN_MIGRATIONS", "expected RUN_MIGRATIONS=\(value) to be rejected")
            #expect(payload?.reason.contains("on/off") == true)
        }
    }
}

/// The `.invalidValue` payload when this error is that case (`nil` otherwise).
private extension ConfigError {
    var invalidValuePayload: (name: String, value: String, reason: String)? {
        guard case .invalidValue(let name, let value, let reason) = self else {
            return nil
        }
        return (name, value, reason)
    }
}
