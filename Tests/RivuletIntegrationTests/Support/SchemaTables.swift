import Foundation
import SQLKit
import Testing
import RivuletApp
@testable import RivuletCore

/// The tables a database file holds, read through an application built for that file.
///
/// CLI pins use this on both sides of the migration flag: the same read after a run with the flag
/// on and after a run with the flag off, so what the pin reports is the gate rather than a schema
/// the test built itself.
func tables(at path: String) async throws -> [String] {
    let config = try Config.load(environment: ["DATABASE_URL": path])
    let rivulet = try await ApplicationFactory.make(config: config)
    do {
        let sql = try #require(rivulet.application.db(.sqlite) as? any SQLDatabase)
        let rows = try await sql.raw("SELECT name FROM sqlite_master WHERE type = 'table'").all()
        let names = try rows.map { try $0.decode(column: "name", as: String.self) }
        try await rivulet.shutdown()
        return names
    } catch {
        try? await rivulet.shutdown()
        throw error
    }
}
