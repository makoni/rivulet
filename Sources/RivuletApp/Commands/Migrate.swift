import ConsoleKit
import Fluent
import RivuletCore
import Vapor

extension RivuletCLI {
    /// `rivulet migrate` — creates or updates the database schema.
    ///
    /// Always migrates, even when `RUN_MIGRATIONS=false`: that flag only controls whether
    /// `serve` migrates on start, while this command is an explicit request.
    struct Migrate: AsyncCommand {
        struct Signature: CommandSignature {
            init() {}
        }

        let environment: [String: String]

        var help: String { "Creates or updates the database schema." }

        func run(using context: CommandContext, signature: Signature) async throws {
            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            do {
                try await rivulet.storage.prepare()
                try await Self.runMigrations(on: rivulet.application, console: context.console)
            } catch {
                try? await rivulet.shutdown()
                throw error
            }
            try await rivulet.shutdown()
        }

        private static func runMigrations(on application: Application, console: any Console) async throws {
            try await application.migrator.setupIfNeeded().get()
            let pending = try await application.migrator.previewPrepareBatch().get()
            guard !pending.isEmpty else {
                console.print("The database schema is up to date.")
                return
            }
            try await application.migrator.prepareBatch().get()
            let names = pending.map { $0.0.name }.joined(separator: ", ")
            console.print("Applied \(pending.count) migration(s): \(names).")
        }
    }
}
