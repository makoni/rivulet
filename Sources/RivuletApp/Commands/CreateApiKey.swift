// The port's own command: Miniflux has no `create-api-key`, so the shape of its line and the
// wording of what a run prints are recorded in `docs/parity.md`; what is traced to the reference is
// what its web form handler does with the values it is given — the rule order, the write, and the
// account the request carries, which here is the account the command resolves, because a command
// line has no session to read one from.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet create-api-key <description>` — one key row, the token, then exit.
    ///
    /// The reference puts a key in the table only through its web form, which this port has no
    /// piece for, so this command is the path the port has. The token is the generator's answer,
    /// and the value the run prints is the value the row holds, because the key is only usable by
    /// whoever reads it at the run.
    ///
    /// The rules run in the reference's order, which `ApiKeyValidationTests` pins, and the account
    /// is the one `--user` names or the single account when none is named, which `FeedCommandTests`
    /// pin as reads. The guard that an empty description is not read against the storage layer at
    /// all is the command's, as upstream's `!= ""` guard is, and no pin here can fail on it: the
    /// answer it prevents is the duplicate read, and `ApiKeyValidationTests` pins only the guard
    /// inside the rule function. The migrations run when `RUN_MIGRATIONS` is on, as the other
    /// commands have them gated.
    struct CreateApiKey: AsyncCommand {
        struct Signature: CommandSignature {
            /// What the key is named. The signature keeps it as a required argument, as ConsoleKit
            /// reads every argument, so the mandatory rule is reached by the empty value the run is
            /// given rather than by an absent argument — which is what the pin runs, and what the
            /// signature parser refuses before the command runs.
            @Argument(name: "description", help: "What the key is named")
            var description: String

            @Option(name: "user", help: "Account to write the row for")
            var user: String?
        }

        let environment: [String: String]

        var help: String {
            "Creates one api key and prints the token, then exits."
        }

        func run(using context: CommandContext, signature: Signature) async throws {
            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            try await rivulet.storage.prepare()
            if config.runMigrations {
                try await rivulet.application.autoMigrate()
            }

            let token: String
            do {
                token = try await store(signature, on: rivulet.storage)
            } catch {
                try? await rivulet.shutdown()
                throw error
            }

            context.console.print("Api key token: \(token)")

            try await rivulet.shutdown()
        }

        /// Resolves the account, applies the rules in the reference's order and writes the row. The
        /// reads and the write run on one checkout.
        private func store(_ signature: Signature, on storage: SQLiteStorage) async throws -> String {
            let description = signature.description

            return try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let keys = ApiKeyRepository(connection)

                let (userID, _, rule) = try await FeedCommandAccount.resolve(
                    name: signature.user ?? "", users: users)
                if let rule { throw CLIError(rule.rawValue) }

                // Upstream guards the duplicate read with `!= ""`, so an empty description never
                // reaches the storage layer; the rule function names the first rule the input fails
                // on, and the pins for the order are `ApiKeyValidationTests`.
                let isDuplicate = description.isEmpty ? false
                    : try await keys.apiKeyExists(userID: userID, description: description)
                if let failed = ApiKeyValidation.validateCreation(description: description,
                    descriptionExists: isDuplicate) {
                    throw CLIError(failed.rawValue)
                }

                let key = try await keys.create(userID: userID, token: ApiKeyToken.generate(),
                    description: description)
                return key.token
            }
        }
    }
}
