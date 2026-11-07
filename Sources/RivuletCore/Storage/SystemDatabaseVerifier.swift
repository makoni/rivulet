import FluentKit
import FluentSQLiteDriver
import Logging
import NIOPosix
import SQLKit

/// The check the commands run on: a connection of its own to the file the path names. The check is
/// the same statement and the same mapping the startup check uses — `PRAGMA quick_check`, the
/// problems as the check observed them, and what prevented it from running reported through the
/// same failure, so page damage and a path that cannot be read are told apart in the runbook — read
/// on a connection the run does not have, because the copy is not the file the run wrote through.
/// The check does not run the storage layer's startup: it reads the file as it is, so it does not
/// decide which journal mode the copy has. The connection is opened for one call and closed before
/// the answer leaves, which is what a check that reads a file it does not own has to do.
public struct SystemDatabaseVerifier: DatabaseVerifier {
    /// Creates the check the run reads.
    public init() {}

    /// The problems the check observed at `path`, empty when it observed none.
    public func problems(at path: String) async throws -> [String] {
        let group = MultiThreadedEventLoopGroup.singleton
        let databases = Databases(threadPool: NIOThreadPool.singleton, on: group)
        let id = DatabaseID(string: "verify")
        databases.use(.sqlite(.file(path)), as: id)
        let connection = databases.database(id, logger: Logger(label: "rivulet.verify"), on: group.next())
        guard let connection else {
            throw StorageError.integrityFailure(for: StorageError.notSQLDatabase)
        }

        do {
            let problems = try await Self.observed(on: connection)
            await databases.shutdownAsync()
            return problems
        } catch {
            // The driver is closed before the failure leaves, so the connection the check opened
            // does not outlive the call that opened it.
            await databases.shutdownAsync()
            throw StorageError.integrityFailure(for: error)
        }
    }

    /// What the check observed on the connection it opened for the path.
    private static func observed(on connection: any Database) async throws -> [String] {
        let rows = try await RawSQL.sql(on: connection).raw("PRAGMA quick_check").all()
        if rows.isEmpty {
            // An empty result is not the clean answer, which is what the storage rule reads it as:
            // `quick_check` reports `ok` on a healthy file, so no row means nothing was observed.
            return ["the check returned no result"]
        }
        let observed = try rows.map { try $0.decode(column: "quick_check", as: String.self) }
        return observed.filter { $0 != "ok" }
    }
}
