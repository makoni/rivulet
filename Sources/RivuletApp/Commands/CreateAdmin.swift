// Ported from Miniflux internal/cli/create_admin.go (Apache-2.0); adapted for Swift/SQLite.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet create-admin` — the first account, then exit.
    ///
    /// Reads the username as plain console input and the password as the secure input, and trims
    /// both before using them, which is what `askCredentials` does. Two things the reference does
    /// here are not ported: the check that the input is an interactive terminal, because this port
    /// reads through the console seam where a captured console has no terminal to test, and the
    /// environment path (`ADMIN_USERNAME` and `ADMIN_PASSWORD` with `CREATE_ADMIN`), which belongs
    /// to the daemon branch and arrives with `serve` in stage 6.
    ///
    /// The order is the reference's: the existence read first, so a name that already has a row is
    /// skipped whatever its characters are, then the rules, then the write. The hash is the
    /// hasher's at the reference cost, and the row is written with the default "All" category,
    /// which is the storage layer's rule. A validation failure ends the command with nothing
    /// written, which is what `printErrorAndExit` does there. The reference reports both outcomes
    /// through `slog`; `RivuletCore` has no logging layer, so the reports here go to the console
    /// and their wording is the port's own — `CreateAdminTests` reads the outcome and the name
    /// carried on the line, not the sentence. The migrations run when `RUN_MIGRATIONS` is on, as
    /// `serve` has them gated.
    struct CreateAdmin: AsyncCommand {
        struct Signature: CommandSignature {
            init() {}
        }

        let environment: [String: String]

        var help: String {
            "Creates the admin account and its default category, then exits."
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
            let username = read(console, prompt: "Username: ", secure: false)
            let password = read(console, prompt: "Password: ", secure: true)
            let hasher = BcryptHasher()

            do {
                try await rivulet.storage.withConnection { connection in
                    let users = UserRepository(connection)

                    // The existence read runs before the rules, as the reference's create-admin has
                    // it, so a stored name is skipped even when the rules would reject it.
                    if try await users.userExists(username: username) {
                        console.print("Skipping: a user named \(username) already exists.")
                        return
                    }

                    if let rule = UserValidation.validateCreation(username: username,
                        password: password, userExists: false) {
                        throw CLIError(message(for: rule))
                    }

                    let user = try await users.create(username: username,
                        passwordHash: try hasher.hash(password), isAdmin: true)
                    console.print("Created admin user \(user.username).")
                }
            } catch {
                try? await rivulet.shutdown()
                throw error
            }

            try await rivulet.shutdown()
        }

        /// Reads one line and trims it, as `askCredentials` does. The class is Swift's
        /// `whitespaces`, which is not Go's `TrimSpace`: the two differ on `U+0085`, and the line
        /// ending is already gone by the time a console read returns, so the difference is not
        /// reachable here. The prompt wording is the port's own; the flag says which path the read
        /// takes, and `CreateAdminTests` reads that flag.
        private func read(_ console: any Console, prompt: String, secure: Bool) -> String {
            console.print(prompt, newLine: false)
            return console.input(isSecure: secure).trimmingCharacters(in: .whitespaces)
        }

        /// The wording the port prints for a rule; the reference's locale strings are not ported.
        private func message(for rule: UserValidationRule) -> String {
            switch rule {
            case .mandatoryFields:
                return "The username is required."
            case .alreadyExists:
                return "A user with that username already exists."
            case .invalidUsername:
                return "The username has a character the reference's class does not admit."
            case .passwordMinLength:
                return "The password must be at least \(UserValidation.passwordMinimumBytes) bytes."
            }
        }
    }
}
