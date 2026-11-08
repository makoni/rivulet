import Fluent
import FluentSQLiteDriver
import RivuletCore
import Vapor

/// Builds the Vapor application around a ``Config``.
public enum ApplicationFactory {
    /// Builds an application: the server address from `LISTEN_ADDR`, the SQLite database,
    /// the schema migrations and the HTTP routes.
    ///
    /// The application is not started and the storage is not prepared: commands prepare
    /// the storage (`journal_mode=WAL` first), run or skip migrations, boot and serve.
    ///
    /// - Parameter config: The loaded configuration.
    /// - Throws: Errors from building the Vapor application.
    public static func make(config: Config) async throws -> RivuletApplication {
        let application = try await Application.make(.production)

        application.http.server.configuration.hostname = config.listenAddress.host
        application.http.server.configuration.port = config.listenAddress.port

        application.databases.use(.sqlite(.file(config.databasePath)), as: .sqlite)
        application.migrations.add(SchemaV1())
        HealthRoutes.register(on: application)

        let storage = SQLiteStorage(database: application.db(.sqlite), path: config.databasePath)
        // The fetcher belongs to the application, so the routes that read a document through it and
        // the refresh path that runs through it are the same one, and the teardown closes it once.
        let fetcher = Fetcher(options: config.fetcher)
        GoogleReaderRoutes.register(on: application, storage: storage, hasher: BcryptHasher(),
            baseURL: config.baseURL,
            finder: SubscriptionFinder(fetcher: fetcher, options: config.fetcher))
        return RivuletApplication(application: application, storage: storage, fetcher: fetcher)
    }
}
