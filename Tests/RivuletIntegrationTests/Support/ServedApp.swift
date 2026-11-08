import Foundation
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// Boots the real application on an ephemeral port with the schema migrated and runs `body` with
/// the storage, the application and the base URL of the socket it answers on.
///
/// The environment the pins name is added to the one this helper always sets, because a pin that
/// reads the application's own fetcher has to name the target rule for the stub server it answers
/// on — the value the configuration reads, not a seam this helper stands in for.
///
/// The server is stopped before the application on both paths: only `ServeCommand` stops it for the
/// happy path, and a started server that is not stopped trips `HTTPServer`'s deinit assertion
/// instead of reporting the real failure. The per-test temporary directory is removed here, so the
/// teardown rule of `docs/testing.md` stays in one place.
func withServedApp(environment: [String: String] = [:],
    _ body: (SQLiteStorage, Application, String) async throws -> Void) async throws {
    let directory = try TemporaryDirectory()
    let config = try Config.load(environment: environment.merging(
        ["DATABASE_URL": directory.path("rivulet.db")]) { $1 })
    let rivulet = try await ApplicationFactory.make(config: config)
    do {
        try await rivulet.storage.prepare()
        try await rivulet.application.autoMigrate()
        try await rivulet.application.asyncBoot()
        try await rivulet.application.server.start(address: .hostname("127.0.0.1", port: 0))
        let address = try #require(rivulet.application.http.server.shared.localAddress)
        let port = try #require(address.port)
        try await body(rivulet.storage, rivulet.application, "http://127.0.0.1:\(port)")
    } catch {
        await rivulet.application.server.shutdown()
        try? await rivulet.shutdown()
        directory.remove()
        throw error
    }
    await rivulet.application.server.shutdown()
    try await rivulet.shutdown()
    directory.remove()
}
