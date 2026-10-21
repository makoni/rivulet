import Testing
@testable import RivuletCore

/// Fetcher options read from the environment. Parsing follows the upstream semantics
/// (`internal/config/options.go`): trimmed keys and values, an empty value falls back to the
/// default, booleans accept the same words, and the numeric validators are `>= 1`.
@Suite struct FetcherOptionsTests {
    @Test func defaultsMatchTheReference() throws {
        let options = try FetcherOptions.load(environment: ["DATABASE_URL": "/tmp/rivulet-test.db"])

        // Reference defaults: 20 seconds, 15 MiB, Go's redirect limit of 10.
        #expect(options.timeout == .seconds(20))
        #expect(options.maxBodySize == 15 * 1024 * 1024)
        #expect(options.maxRedirects == 10)
        #expect(options.acceptHeader == FetcherOptions.defaultAcceptHeader)
        #expect(options.decompression)
        #expect(!options.ignoreHTTPCache)
        #expect(!options.allowPrivateNetworks)
        #expect(options.proxyURL == nil)
    }

    @Test func userAgentFallsBackToRivuletsOwnValue() throws {
        let options = try FetcherOptions.load(environment: ["HTTP_CLIENT_USER_AGENT": "  "])
        #expect(options.userAgent == FetcherOptions.defaultUserAgent)

        let custom = try FetcherOptions.load(environment: ["HTTP_CLIENT_USER_AGENT": " Custom Client/2.0 "])
        #expect(custom.userAgent == "Custom Client/2.0")
    }

    @Test func numericOptionsAreTrimmedAndValidated() throws {
        let parsed = try FetcherOptions.load(environment: [
            "HTTP_CLIENT_TIMEOUT": " 45 ",
            "HTTP_CLIENT_MAX_BODY_SIZE": "25",
        ])
        #expect(parsed.timeout == .seconds(45))
        #expect(parsed.maxBodySize == 25 * 1024 * 1024)

        // Upstream validators: both options must be at least 1.
        #expect(throws: ConfigError.invalidValue(
            variable: "HTTP_CLIENT_TIMEOUT",
            value: "0",
            reason: "must be at least 1"
        )) {
            try FetcherOptions.load(environment: ["HTTP_CLIENT_TIMEOUT": "0"])
        }
        #expect(throws: ConfigError.invalidValue(
            variable: "HTTP_CLIENT_MAX_BODY_SIZE",
            value: "0",
            reason: "must be at least 1"
        )) {
            try FetcherOptions.load(environment: ["HTTP_CLIENT_MAX_BODY_SIZE": "0"])
        }
        #expect(throws: ConfigError.self) {
            try FetcherOptions.load(environment: ["HTTP_CLIENT_TIMEOUT": "twenty"])
        }
    }

    @Test func booleansAcceptTheUpstreamWords() throws {
        for trueValue in ["1", "yes", "true", "on", "TRUE"] {
            let options = try FetcherOptions.load(
                environment: ["FETCHER_ALLOW_PRIVATE_NETWORKS": trueValue]
            )
            #expect(options.allowPrivateNetworks, Comment("\(trueValue)"))
        }
        for falseValue in ["0", "no", "false", "off", "OFF"] {
            let options = try FetcherOptions.load(
                environment: ["FETCHER_IGNORE_HTTP_CACHE": falseValue]
            )
            #expect(!options.ignoreHTTPCache, Comment("\(falseValue)"))
        }
        #expect(throws: ConfigError.self) {
            try FetcherOptions.load(environment: ["FETCHER_ALLOW_PRIVATE_NETWORKS": "maybe"])
        }
    }

    @Test func proxyIsOptional() throws {
        let empty = try FetcherOptions.load(environment: ["FETCHER_PROXY": "  "])
        #expect(empty.proxyURL == nil)

        let set = try FetcherOptions.load(environment: ["FETCHER_PROXY": " http://proxy.internal:3128 "])
        #expect(set.proxyURL == "http://proxy.internal:3128")
    }

    @Test func configCarriesTheFetcherOptions() throws {
        let config = try Config.load(environment: [
            "DATABASE_URL": "/tmp/rivulet-test.db",
            "HTTP_CLIENT_TIMEOUT": "30",
        ])
        #expect(config.fetcher.timeout == .seconds(30))
        #expect(config.fetcher.maxBodySize == 15 * 1024 * 1024)
    }
}
