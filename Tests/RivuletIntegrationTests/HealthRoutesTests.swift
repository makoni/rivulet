import Foundation
import Vapor
import XCTest
import RivuletApp
import RivuletCore

final class HealthRoutesTests: XCTestCase {
    override func setUp() {
        TestLogging.bootstrapOnce()
    }

    func testBootedApplicationServesHealthzOverARealSocket() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Config.load(environment: ["DATABASE_URL": directory.path("rivulet.db")])
        let rivulet = try await ApplicationFactory.make(config: config)

        do {
            // The factory wires the configured LISTEN_ADDR into the server.
            XCTAssertEqual(rivulet.application.http.server.configuration.hostname, config.listenAddress.host)
            XCTAssertEqual(rivulet.application.http.server.configuration.port, config.listenAddress.port)

            try await rivulet.storage.prepare()
            try await rivulet.application.asyncBoot()

            // Deterministic sockets: bind port 0 and use the port the kernel assigns
            // (the configured port above is never really bound by this test).
            try await rivulet.application.server.start(address: .hostname("127.0.0.1", port: 0))
            let address = try XCTUnwrap(rivulet.application.http.server.shared.localAddress)
            XCTAssertEqual(address.hostname, "127.0.0.1")
            let port = try XCTUnwrap(address.port)
            XCTAssertNotEqual(port, 0, "the kernel must have assigned a port")

            let response = try await rivulet.application.client.get(
                URI(string: "http://127.0.0.1:\(port)/healthz")
            )
            XCTAssertEqual(response.status, .ok)
            XCTAssertEqual(try bodyString(of: response), "OK")

            await rivulet.application.server.shutdown()
        } catch {
            try? await rivulet.shutdown()
            throw error
        }
        try await rivulet.shutdown()
    }

    func testHealthzIsALivenessProbeThatDoesNotTouchTheDatabase() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        // The parent directory of the database file does not exist, so any database access
        // would fail: /healthz must still answer (upstream parity — it is a liveness probe).
        let config = try Config.load(environment: ["DATABASE_URL": directory.path("missing/rivulet.db")])
        let rivulet = try await ApplicationFactory.make(config: config)

        do {
            try await rivulet.application.asyncBoot()
            try await rivulet.application.server.start(address: .hostname("127.0.0.1", port: 0))
            let address = try XCTUnwrap(rivulet.application.http.server.shared.localAddress)
            let port = try XCTUnwrap(address.port)

            let response = try await rivulet.application.client.get(
                URI(string: "http://127.0.0.1:\(port)/healthz")
            )
            XCTAssertEqual(response.status, .ok)
            XCTAssertEqual(try bodyString(of: response), "OK")

            await rivulet.application.server.shutdown()
        } catch {
            try? await rivulet.shutdown()
            throw error
        }
        try await rivulet.shutdown()
    }

    /// The response body decoded as UTF-8 (the only content our probes produce).
    private func bodyString(of response: ClientResponse) throws -> String {
        let body = try XCTUnwrap(response.body)
        return String(decoding: body.readableBytesView, as: UTF8.self)
    }
}
