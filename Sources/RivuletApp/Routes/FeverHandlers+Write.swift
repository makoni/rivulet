// Ported from Miniflux internal/fever/handler.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

extension FeverHandlers {
    /// `handleWriteItems`: the guard reads the value the integer read answers, so a value it cannot
    /// read is the zero and the handler ends before the response builder runs. The switch has no
    /// default case, so a state name it does not have writes nothing.
    func writeItem(form: FeverForm, userID: Int) async throws -> Response {
        let entryID = form.integer64(named: "id")
        guard entryID > 0 else { return Self.guarded() }

        do {
            // Upstream reads the row through its query builder, scoped to the account; here that is
            // the same read, and the guard runs after it, so a row the read does not find
            // writes nothing.
            let entry = try await storage.withConnection { connection in
                try await EntryRepository(connection)
                    .list(EntryQuery(userID: userID, entryIDs: [Int(entryID)])).first
            }
            guard let entry, let rowID = entry.id else {
                return answer()
            }

            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                switch form.value(named: "as") {
                case "read": try await entries.setStatus(userID: userID, entryIDs: [rowID], status: .read)
                case "unread": try await entries.setStatus(userID: userID, entryIDs: [rowID], status: .unread)
                case "saved", "unsaved": try await entries.toggleStarred(userID: userID, entryID: rowID)
                default: break
                }
            }
            return answer()
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `handleWriteFeeds`: the state name is not read on this branch, and the comparison against
    /// the instant is strictly before. The guard reads the value the integer read answers.
    func writeFeed(form: FeverForm, userID: Int) async throws -> Response {
        let feedID = form.integer64(named: "id")
        guard feedID > 0 else { return Self.guarded() }

        do {
            try await storage.withConnection { connection in
                try await EntryRepository(connection).markFeedAsRead(userID: userID, feedID: Int(feedID),
                    before: Int(form.integer64(named: "before")))
            }
            return answer()
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `handleWriteGroups`: the three branches of the guard — below zero writes nothing, the zero
    /// is the user-wide write whatever the instant names, and a value marks the rows of that
    /// category before the instant.
    func writeGroup(form: FeverForm, userID: Int) async throws -> Response {
        let groupID = form.integer64(named: "id")
        guard groupID >= 0 else { return Self.guarded() }

        do {
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                if groupID == 0 {
                    try await entries.markAllAsRead(userID: userID)
                } else {
                    try await entries.markCategoryAsRead(userID: userID, categoryID: Int(groupID),
                        before: Int(form.integer64(named: "before")))
                }
            }
            return answer()
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// The answer every write branch ends with, which is also the answer for a row the read does
    /// not find: the base document, with the flag the transport read passed.
    private func answer() -> Response {
        GoogleReaderResponse.json(FeverShape.baseDocument(authenticated: 1, lastRefreshed: Self.now()))
    }
}
