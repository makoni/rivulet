// The account a feed command is working for, and the wordings the feed commands write.
//
// The reference has no `add`, `remove` or `list` commands, so this resolution is the port's own:
// the account is the one named by `--user`, read as the account lookup reads a name, and when no
// name is given the single account is used. Failing with no name and several accounts is the port's
// rule, named `multipleAccounts` in `docs/reference-notes.md`.

import RivuletCore

enum FeedCommandAccount {
    /// Names the account the command resolves.
    ///
    /// - Parameters:
    ///   - name: The account as the command read it, empty when none was given.
    ///   - users: The repository the two reads are made through.
    /// - Returns: The row id and the name as the row holds it, and the rule the resolution failed
    ///   on: nil when it answered an account, ``FeedValidationRule/multipleAccounts`` when no name
    ///   is given and there is more than one account, and ``FeedValidationRule/accountNotFound``
    ///   when the named account has no row.
    static func resolve(name: String, users: UserRepository)
        async throws -> (userID: Int, accountName: String, rule: FeedValidationRule?) {
        if !name.isEmpty {
            guard let user = try await users.fetch(username: name), let userID = user.id else {
                return (0, name, .accountNotFound)
            }
            return (userID, user.username, nil)
        }

        // The single account is used only when no name is given, so the pin that names several
        // accounts with none named reads the count, not the first row it found.
        let accounts = try await users.list()
        guard accounts.count == 1, let user = accounts.first, let userID = user.id else {
            return (0, name, .multipleAccounts)
        }
        return (userID, user.username, nil)
    }
}
