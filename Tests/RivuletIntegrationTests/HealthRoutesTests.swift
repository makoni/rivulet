import Foundation
import Vapor
import Testing
import RivuletApp
import RivuletCore

@Suite struct HealthRoutesTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    @Test func bootedApplicationServesHealthzOverARealSocket() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Config.load(environment: ["DATABASE_URL": directory.path("rivulet.db")])
        let rivulet = try await ApplicationFactory.make(config: config)

        do {
            // The factory wires the configured LISTEN_ADDR into the server.
            #expect(rivulet.application.http.server.configuration.hostname == config.listenAddress.host)
            #expect(rivulet.application.http.server.configuration.port == config.listenAddress.port)

            try await rivulet.storage.prepare()
            try await rivulet.application.asyncBoot()

            // Deterministic sockets: bind port 0 and use the port the kernel assigns
            // (the configured port above is never really bound by this test).
            try await rivulet.application.server.start(address: .hostname("127.0.0.1", port: 0))
            let address = try #require(rivulet.application.http.server.shared.localAddress)
            #expect(address.hostname == "127.0.0.1")
            let port = try #require(address.port)
            #expect(port != 0, "the kernel must have assigned a port")

            let response = try await rivulet.application.client.get(
                URI(string: "http://127.0.0.1:\(port)/healthz")
            )
            #expect(response.status == .ok)
            let body = try bodyString(of: response)
            #expect(body == "OK")

            // Miniflux registers the probe without a method, so every method answers.
            let post = try await rivulet.application.client.post(
                URI(string: "http://127.0.0.1:\(port)/healthz")
            )
            #expect(post.status == .ok)
            let postBody = try bodyString(of: post)
            #expect(postBody == "OK")

            await rivulet.application.server.shutdown()
        } catch {
            // Only Vapor's `ServeCommand` stops the server for us; a failure after
            // `server.start` must stop it explicitly, or the app shutdown trips
            // `HTTPServer`'s deinit assertion instead of reporting the real failure.
            await rivulet.application.server.shutdown()
            try? await rivulet.shutdown()
            throw error
        }
        try await rivulet.shutdown()
    }

    @Test func healthzIsALivenessProbeThatDoesNotTouchTheDatabase() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        // The parent directory of the database file does not exist, so any database access
        // would fail: /healthz must still answer (upstream parity — it is a liveness probe).
        let config = try Config.load(environment: ["DATABASE_URL": directory.path("missing/rivulet.db")])
        let rivulet = try await ApplicationFactory.make(config: config)

        do {
            // Pin the premise: the database really is unreachable.
            do {
                try await rivulet.storage.prepare()
                Issue.record("the database must be unreachable for this test's premise")
            } catch {}

            try await rivulet.application.asyncBoot()
            try await rivulet.application.server.start(address: .hostname("127.0.0.1", port: 0))
            let address = try #require(rivulet.application.http.server.shared.localAddress)
            let port = try #require(address.port)

            let response = try await rivulet.application.client.get(
                URI(string: "http://127.0.0.1:\(port)/healthz")
            )
            #expect(response.status == .ok)
            let body = try bodyString(of: response)
            #expect(body == "OK")

            await rivulet.application.server.shutdown()
        } catch {
            // See the comment in the test above: stop a started server before the app.
            await rivulet.application.server.shutdown()
            try? await rivulet.shutdown()
            throw error
        }
        try await rivulet.shutdown()
    }

    /// The response body decoded as UTF-8 (the only content our probes produce).
    private func bodyString(of response: ClientResponse) throws -> String {
        let body = try #require(response.body)
        return String(decoding: body.readableBytesView, as: UTF8.self)
    }
}
