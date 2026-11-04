// Ported from Miniflux internal/ui/integration_update.go (Apache-2.0); adapted for Swift/SQLite and
// for the console path, which is the port's own: the reference has this path only as its web form.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet integration-credentials` — set one account's credential pairs, then exit.
    ///
    /// The reference reaches these values through its web form, so the prompts and the order they
    /// are asked in are the port's own; what is ported is what that handler does with the values it
    /// is given. The prompts follow the order the handler reads its rules in — the Fever pair
    /// first, then the Google Reader pair — so the reads and the checks line up.
    ///
    /// A read that comes back blank keeps what the row already holds, which is what the reference
    /// does for the two password fields. On the name side upstream writes what was submitted, so a
    /// blank field clears the stored name there; this port keeps the value instead, because a
    /// command line reads blank as "not given", and the duplicate check sees the kept name where
    /// the reference's guard would skip an empty field — recorded in `docs/parity.md`. The values
    /// stored are the derived ones: the Fever pair as the digest of `name:password`, the Google
    /// Reader pair as the hash at the reference cost, and the names as read without the lowercase
    /// the account name gets. The rules are checked before anything is written, and the wording of
    /// a failure is the port's own, because upstream reports through its session flash. The
    /// migrations run when `RUN_MIGRATIONS` is on, as the other commands have them gated.
    struct IntegrationCredentials: AsyncCommand {
        struct Signature: CommandSignature {
            init() {}
        }

        let environment: [String: String]

        var help: String {
            "Sets one account's Google Reader and Fever credentials and prints the Fever api_key."
        }

        func run(using context: CommandContext, signature: Signature) async throws {
            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            try await rivulet.storage.prepare()
            if config.runMigrations {
                try await rivulet.application.autoMigrate()
            }

            let console = context.console
            let values = Values(account: read(console, prompt: "Account: ", secure: false),
                feverName: read(console, prompt: "Fever username: ", secure: false),
                feverPassword: read(console, prompt: "Fever password: ", secure: true),
                googleReaderName: read(console, prompt: "Google Reader username: ", secure: false),
                googleReaderPassword: read(console, prompt: "Google Reader password: ", secure: true))

            do {
                try await rivulet.storage.withConnection { connection in
                    try await store(values, users: UserRepository(connection), console: console)
                }
            } catch {
                try? await rivulet.shutdown()
                throw error
            }

            try await rivulet.shutdown()
        }

        /// What one run read: the account name and the two credential pairs, each already trimmed.
        private struct Values: Sendable {
            let account: String
            let feverName: String
            let feverPassword: String
            let googleReaderName: String
            let googleReaderPassword: String
        }

        /// The write, in the reference's order: find the row, check the names, derive, store,
        /// print.
        private func store(_ values: Values, users: UserRepository, console: any Console) async throws {
            let user = try await users.fetch(username: values.account)
            guard let user else {
                throw CLIError("There is no account named \(values.account).")
            }
            let id = try user.requireID()

            // A blank read keeps what the row holds, which is the rule the pins read on both sides.
            let fever = values.feverName.isEmpty ? user.feverUsername : values.feverName
            let googleReader = values.googleReaderName.isEmpty ? user.googleReaderUsername
                : values.googleReaderName

            if let rule = try await checkDuplicates(fever, googleReader, userID: id, users) {
                throw CLIError(message(for: rule))
            }

            // Upstream refreshes a stored value only when a password was given, so a blank read
            // leaves the stored value as it was.
            let feverToken = values.feverPassword.isEmpty ? user.feverToken
                : FeverToken.derive(username: fever ?? "", password: values.feverPassword)
            let googleReaderHash = values.googleReaderPassword.isEmpty ? user.googleReaderPasswordHash
                : try BcryptHasher().hash(values.googleReaderPassword)

            try await users.updateIntegration(user, feverUsername: fever, feverToken: feverToken,
                googleReaderUsername: googleReader, googleReaderPasswordHash: googleReaderHash)
            console.print("Fever api_key: \(feverToken ?? "")")
        }

        /// The two checks, in the order the reference reads them.
        ///
        /// Upstream guards each check with `!= ""`, so a blank name is not read against the storage
        /// layer at all; the rule function names the first rule the input fails on, and the pins
        /// for the order are `IntegrationValidationTests`.
        private func checkDuplicates(_ fever: String?, _ googleReader: String?, userID: Int,
            _ users: UserRepository) async throws -> IntegrationValidationRule? {
            let feverIsDuplicate = hasName(fever)
                ? try await users.hasDuplicateFeverUsername(userID: userID, feverUsername: fever ?? "")
                : false
            let googleReaderIsDuplicate = hasName(googleReader)
                ? try await users.hasDuplicateGoogleReaderUsername(
                    userID: userID, googleReaderUsername: googleReader ?? "")
                : false
            return IntegrationValidation.validate(feverUsername: fever ?? "",
                feverNameIsDuplicate: feverIsDuplicate,
                googleReaderUsername: googleReader ?? "",
                googleReaderNameIsDuplicate: googleReaderIsDuplicate)
        }

        /// Whether a name reaches the storage layer at all, which is upstream's `!= ""` guard.
        private func hasName(_ name: String?) -> Bool {
            name.map { !$0.isEmpty } ?? false
        }

        /// Reads one line and trims it, as `askCredentials` does. The prompt wording is the port's
        /// own; the flag says which path the read takes, and `IntegrationCredentialsTests` reads
        /// that flag.
        private func read(_ console: any Console, prompt: String, secure: Bool) -> String {
            console.print(prompt, newLine: false)
            return console.input(isSecure: secure).trimmingCharacters(in: .whitespaces)
        }

        /// The wording the port prints for a rule; the reference's locale strings are not ported.
        private func message(for rule: IntegrationValidationRule) -> String {
            switch rule {
            case .duplicateFeverUsername:
                return "Another account already uses that Fever username."
            case .duplicateGoogleReaderUsername:
                return "Another account already uses that Google Reader username."
            }
        }
    }
}
