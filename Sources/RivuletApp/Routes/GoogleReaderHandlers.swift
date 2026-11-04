// Ported from Miniflux internal/googlereader/handler.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The handler answers this path writes.
///
/// The handlers apply the pure rules landed in PR #42 and PR #43: the form read, the query read,
/// the stream read, the tag read, the output read, and the document shapes. What this file adds is
/// the handler's own choices: which endpoints apply the output check, which error becomes 400 and
/// 500, and which storage values each handler writes.
struct GoogleReaderHandlers: Sendable {
    private let storage: SQLiteStorage

    init(storage: SQLiteStorage) {
        self.storage = storage
    }

    /// `editTagHandler`. The handler reads `a` and `r` from `PostForm`, but the item ids from the
    /// merged `r.Form`. The storage values are what the tag read writes for each branch.
    func editTag(form: GoogleReaderForm, userID: Int) async throws -> Response {
        let adds: [GoogleReaderStream]
        let removes: [GoogleReaderStream]
        let itemIDs: [Int]

        do {
            adds = try Self.streams(form.postValues(named: "a"), userID: userID)
            removes = try Self.streams(form.postValues(named: "r"), userID: userID)
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }

        if adds.isEmpty && removes.isEmpty {
            return GoogleReaderResponse.serverError(Self.emptyTagsMessage)
        }

        let tags: [GoogleReaderStreamType: Bool]
        do {
            tags = try GoogleReaderTags.simplify(adds: adds, removes: removes)
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }

        do {
            itemIDs = try Self.itemIDs(from: form.values(named: "i"))
        } catch {
            return GoogleReaderResponse.badRequest(String(describing: error))
        }

        do {
            try await writeUserState(userID: userID, tags: tags, entryIDs: itemIDs)
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }

        return GoogleReaderResponse.text("OK")
    }

    /// `userInfoHandler`. This handler does not apply the output check. The id is the row the
    /// transport read found, and the name is the stored account name, not the token name.
    func userInfo(userID: Int) async throws -> Response {
        do {
            let user = try await storage.withConnection { connection in
                try await UserRepository(connection).fetch(id: userID)
            }
            guard let user, let rowID = user.id else {
                return GoogleReaderResponse.notFound()
            }
            let userIDText = String(rowID)
            return GoogleReaderResponse.json(GoogleReaderShape.userInfoResponse(
                userID: userIDText,
                userName: user.username,
                userProfileID: userIDText,
                userEmail: user.username
            ))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `tagListHandler`. The output check is this handler's choice, and the categories answer in
    /// the reference's `Categories` order: title alone.
    func tagList(query: String, userID: Int) async throws -> Response {
        do {
            try GoogleReaderOutput.check(method: .GET, query: query, body: nil)
        } catch {
            return GoogleReaderResponse.badRequest(String(describing: error))
        }

        do {
            let categories = try await storage.withConnection { connection in
                try await CategoryRepository(connection).listByTitle(userID: userID)
            }

            var tags = [GoogleReaderShape.categoryResponse(
                id: "user/\(userID)/state/com.google/starred"
            )]
            tags.append(contentsOf: categories.map {
                GoogleReaderShape.categoryResponse(id: "user/\(userID)/label/\($0.title)",
                    label: $0.title, type: "folder")
            })

            return GoogleReaderResponse.json(GoogleReaderShape.tagsResponse(tags: tags))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `streamItemIDsHandler`. The output check runs before the filter read, and the handler answer
    /// for the read error is 500. The branch switch is what chooses the storage filters.
    func streamItemIDs(query: String, userID: Int) async throws -> Response {
        do {
            try GoogleReaderOutput.check(method: .GET, query: query, body: nil)
        } catch {
            return GoogleReaderResponse.badRequest(String(describing: error))
        }

        do {
            let modifiers = try GoogleReaderRequestModifiers(query: GoogleReaderQuery(query: query),
                userID: userID)

            if modifiers.streams.count != 1 {
                return GoogleReaderResponse.serverError("googlereader: only one stream type expected")
            }

            let stream = modifiers.streams[0]
            var entryQuery = Self.baseQuery(modifiers)
            switch stream.type {
            case .readingList:
                entryQuery.statuses = Self.readingListStatuses(modifiers.excludeTargets)
            case .starred:
                entryQuery.starred = true
            case .read:
                entryQuery.statuses = [.read]
            case .feed:
                // `WithFeedID` adds its condition only for a positive value, so a parsed 0 or a
                // negative value leaves the filter unset and answers the user's entries. This is
                // the caller the query's own convention names: the value is mapped before it is
                // given.
                let feedID = try Self.parseFeedID(stream.id)
                if feedID > 0 {
                    entryQuery.feedID = feedID
                }
                entryQuery.excludeStatus = Self.feedExcludedStatus(modifiers.excludeTargets)
            default:
                return GoogleReaderResponse.serverError(
                    "googlereader: unknown stream type \(stream.type.rawValue)"
                )
            }
            return try await streamResponse(modifiers: modifiers, query: entryQuery)
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    // MARK: - Handler rules

    private static func streams(_ values: [String], userID: Int) throws -> [GoogleReaderStream] {
        try values.map { try GoogleReaderStream.parse(streamID: $0, userID: userID) }
    }

    private static func itemIDs(from values: [String]) throws -> [Int] {
        guard !values.isEmpty else {
            throw ItemIDReadError.noItems
        }
        return try values.map { value in
            do {
                return Int(try GoogleReaderItemID.parse(value))
            } catch {
                throw ItemIDReadError.parse(input: value, reason: String(describing: error))
            }
        }
    }

    /// What the feed branch does with the value the stream read left after the prefix: the
    /// reference's `strconv.ParseInt`, not the stream read's text answer.
    private static func parseFeedID(_ value: String) throws -> Int {
        let signed = value.hasPrefix("-") || value.hasPrefix("+")
        let digits = value.dropFirst(signed ? 1 : 0)
        guard !digits.isEmpty, digits.allSatisfy(isDigit) else {
            throw IntegerParseError.invalidSyntax(value)
        }
        guard let parsed = Int(value) else {
            throw IntegerParseError.outOfRange(value)
        }
        return parsed
    }

    /// The part every branch handler builds the same way: the page size, the continuation value,
    /// and the order, which is the default column with the direction the read answered. The two
    /// times are read on every branch, and only a positive one is applied.
    private static func baseQuery(_ modifiers: GoogleReaderRequestModifiers) -> EntryQuery {
        var query = EntryQuery(
            userID: modifiers.userID,
            sort: EntrySort(field: .publishedAt, direction: sortDirection(modifiers.sortDirection)),
            limit: modifiers.count,
            offset: modifiers.offset
        )
        if modifiers.startTime > 0 {
            query.publishedAfter = Int(modifiers.startTime)
        }
        if modifiers.stopTime > 0 {
            query.publishedBefore = Int(modifiers.stopTime)
        }
        return query
    }

    private static func sortDirection(_ value: String) -> EntrySort.Direction {
        value == "asc" ? .ascending : .descending
    }

    /// What the reading-list branch adds for the exclude list: the name says the status to keep is
    /// the other one, and a target of another type adds nothing.
    private static func readingListStatuses(_ targets: [GoogleReaderStream]) -> [EntryStatus] {
        targets.compactMap { $0.type == .read ? .unread : nil }
    }

    /// The same list read by the feed branch, which excludes the status the name itself says. A
    /// target of another type leaves nothing.
    private static func feedExcludedStatus(_ targets: [GoogleReaderStream]) -> EntryStatus? {
        targets.compactMap { $0.type == .read ? EntryStatus.read : nil }.first
    }

    private func streamResponse(modifiers: GoogleReaderRequestModifiers, query: EntryQuery)
        async throws -> Response {
        try await storage.withConnection { connection in
            let entries = EntryRepository(connection)
            let returned = try await entries.listIDs(query)
            let total = try await entries.count(query)
            let continuation = GoogleReaderRequestModifiers.continuation(returned: returned.count,
                offset: modifiers.offset, total: total)
            let refs = returned.map { GoogleReaderShape.itemRef(id: String($0)) }
            return GoogleReaderResponse.json(GoogleReaderShape.streamIDResponse(itemRefs: refs,
                continuation: continuation))
        }
    }

    private func writeUserState(userID: Int, tags: [GoogleReaderStreamType: Bool], entryIDs: [Int])
        async throws {
        try await storage.withConnection { connection in
            let entries = EntryRepository(connection)
            let listed = try await entries.list(EntryQuery(userID: userID, entryIDs: entryIDs))

            var readIDs: [Int] = []
            var unreadIDs: [Int] = []
            var starredIDs: [Int] = []
            var unstarredIDs: [Int] = []

            for entry in listed {
                guard let id = entry.id else { continue }

                if let read = tags[.read] {
                    if read && entry.status == .unread {
                        readIDs.append(id)
                    } else if !read && entry.status == .read {
                        unreadIDs.append(id)
                    }
                }

                if let starred = tags[.starred] {
                    if starred && !entry.starred {
                        starredIDs.append(id)
                    } else if !starred && entry.starred {
                        unstarredIDs.append(id)
                    }
                }
            }

            if !readIDs.isEmpty {
                try await entries.setStatus(userID: userID, entryIDs: readIDs, status: .read)
            }
            if !unreadIDs.isEmpty {
                try await entries.setStatus(userID: userID, entryIDs: unreadIDs, status: .unread)
            }
            if !unstarredIDs.isEmpty {
                try await entries.setStarred(userID: userID, entryIDs: unstarredIDs, starred: false)
            }
            if !starredIDs.isEmpty {
                try await entries.setStarred(userID: userID, entryIDs: starredIDs, starred: true)
            }
        }
    }

    private static func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }

    private static let emptyTagsMessage = "googlreader: add or/and remove tags should be supplied"

    private enum ItemIDReadError: Error, CustomStringConvertible, Sendable {
        case noItems
        case parse(input: String, reason: String)

        var description: String {
            switch self {
            case .noItems:
                return "googlereader: no items requested"
            case .parse(let input, let reason):
                return "googlereader: failed to parse item ID \(input): \(reason)"
            }
        }
    }

    private enum IntegerParseError: Error, CustomStringConvertible, Sendable {
        case invalidSyntax(String)
        case outOfRange(String)

        var description: String {
            switch self {
            case .invalidSyntax(let value):
                return "strconv.ParseInt: parsing \"\(value)\": invalid syntax"
            case .outOfRange(let value):
                return "strconv.ParseInt: parsing \"\(value)\": value out of range"
            }
        }
    }
}
