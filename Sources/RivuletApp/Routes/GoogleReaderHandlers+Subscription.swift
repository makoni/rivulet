// Ported from Miniflux internal/googlereader/handler.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import RivuletCore
import Vapor

/// Split from `GoogleReaderHandlers` to keep each file within the size budget. These handlers read
/// the rules the other files of this path already use — the form read, the stream read, the output
/// check, the URL rule, the validation order and the document shapes — and add the choices that are
/// their own: which endpoints apply the output check, which status each error becomes, the order
/// the guards run in, and which storage value each branch writes. The discovery this path calls is
/// the minimal scan the plan names, recorded in `docs/parity.md`.
extension GoogleReaderHandlers {
    /// `subscriptionListHandler`. The output check is this handler's choice, and the feeds answer
    /// in the order the reference's default sort read builds them.
    func list(query: String, userID: Int, baseURL: URL) async throws -> Response {
        do {
            try GoogleReaderOutput.check(method: .GET, query: query, body: nil)
        } catch {
            return GoogleReaderResponse.badRequest(String(describing: error))
        }

        do {
            let documents = try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let categories = CategoryRepository(connection)
                let icons = IconRepository(connection)

                var documents: [JSONValue] = []
                for feed in try await feeds.listSortedByErrorCountThenTitle(userID: userID) {
                    // The label is the category title, not the feed title, and the link is built
                    // from the configured base rather than from the host the request came in on.
                    // The icon is written only when the row has an external id to write.
                    let label = try await categories.fetch(id: feed.categoryID)?.title ?? ""
                    var iconURL = ""
                    if let iconID = feed.iconID, let icon = try await icons.fetch(id: iconID),
                        !icon.externalID.isEmpty {
                        iconURL = baseURL.absoluteString + "/feed-icon/" + icon.externalID
                    }
                    documents.append(GoogleReaderShape.subscriptionResponse(
                        id: feedPrefix(feed),
                        title: feed.title,
                        categories: [GoogleReaderShape.categoryResponse(
                            id: "user/\(userID)/label/\(label)", label: label, type: "folder")],
                        url: feed.url,
                        htmlURL: feed.siteURL,
                        iconURL: iconURL
                    ))
                }
                return documents
            }

            return GoogleReaderResponse.json(GoogleReaderShape.subscriptionsResponse(
                subscriptions: documents))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `editSubscriptionHandler`. `s` is the whole merged list here, while `a` is the single value
    /// the same read answers, and the branch that writes the tag is the one the presence test opens
    /// — the pin that shows the two halves answer differently is in the suite header's list.
    func edit(form: GoogleReaderForm, userID: Int) async throws -> Response {
        let streams: [GoogleReaderStream]
        do {
            streams = try Self.streams(form.values(named: "s"), userID: userID)
        } catch {
            return GoogleReaderResponse.badRequest(Self.noStreamsMessage)
        }
        guard !streams.isEmpty else {
            return GoogleReaderResponse.badRequest(Self.noStreamsMessage)
        }

        let destination: GoogleReaderStream
        do {
            destination = try GoogleReaderStream.parse(streamID: form.value(named: "a"), userID: userID)
        } catch {
            return GoogleReaderResponse.badRequest(Self.invalidData(named: "a"))
        }

        let title = form.value(named: "t")
        switch form.value(named: "ac") {
        case "subscribe":
            // Every failure of this branch is the 500, including the rule the validation reports,
            // which the port names rather than the reference's string.
            do {
                _ = try await subscribe(feedURL: streams[0].id, category: destination, title: title,
                    userID: userID)
            } catch {
                return GoogleReaderResponse.serverError(String(describing: error))
            }
        case "unsubscribe":
            do {
                try await unsubscribe(streams, userID: userID)
            } catch {
                return GoogleReaderResponse.serverError(String(describing: error))
            }
        case "edit":
            if !title.isEmpty {
                do {
                    try await rename(streams[0], title: title, userID: userID)
                } catch let failure as SubscriptionError {
                    return GoogleReaderResponse.badRequest(failure.description)
                } catch {
                    return GoogleReaderResponse.serverError(String(describing: error))
                }
            }

            if form.has(named: "a") {
                guard destination.type == .label else {
                    return GoogleReaderResponse.badRequest(Self.destinationMessage)
                }
                do {
                    try await move(streams[0], destination: destination, userID: userID)
                } catch let failure as SubscriptionError {
                    return GoogleReaderResponse.badRequest(failure.description)
                } catch {
                    return GoogleReaderResponse.serverError(String(describing: error))
                }
            }
        default:
            return GoogleReaderResponse.badRequest(
                "googlereader: unrecognized action \(form.value(named: "ac"))")
        }

        return GoogleReaderResponse.text("OK")
    }

    /// `quickAddHandler`. The name is read from the merged form, so the query half answers on its
    /// own, and the absolute rule runs before the fetch. The pick is the first value the scan
    /// answered.
    func quickAdd(form: GoogleReaderForm, userID: Int) async throws -> Response {
        let feedURL = form.value(named: "quickadd")
        guard URLRules.isAbsoluteURL(feedURL) else {
            return GoogleReaderResponse.badRequest("googlereader: invalid URL: \(feedURL)")
        }

        let found: [String]
        do {
            found = try await finder.findFeedURLs(from: feedURL)
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }

        guard !found.isEmpty else {
            return GoogleReaderResponse.json(GoogleReaderShape.quickAddResponse(numResults: 0))
        }

        do {
            // The category the form did not name is the value the stream read answers for the empty
            // string, which is the same answer the reference's `getOrCreateCategory` reads for it.
            let none = try GoogleReaderStream.parse(streamID: "", userID: userID)
            let feed = try await subscribe(feedURL: found[0], category: none, title: "", userID: userID)
            return GoogleReaderResponse.json(GoogleReaderShape.quickAddResponse(numResults: 1,
                query: feed.url, streamID: feedPrefix(feed), streamName: feed.title))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    // MARK: - The storage each branch writes

    /// `getOrCreateCategory`: the value the stream read left decides which read runs, and the row
    /// that is not there is created. The reference reads the title twice — `CategoryTitleExists`
    /// and then `CategoryByTitle` — which is the same answer as the one read here.
    private func category(_ categories: CategoryRepository, userID: Int,
        stream: GoogleReaderStream) async throws -> Category? {
        if stream.id.isEmpty { return try await categories.first(userID: userID) }
        if let found = try await categories.byTitle(userID: userID, title: stream.id) { return found }
        return try await categories.create(userID: userID, title: stream.id)
    }

    /// `subscribe`, cut to what this port writes: the rules in the reference's order, the row, and
    /// the title written only when the value is not empty. The reference parses the url inside this
    /// branch, which this port does not — recorded in `docs/parity.md`.
    private func subscribe(feedURL: String, category stream: GoogleReaderStream, title: String,
        userID: Int) async throws -> Feed {
        try await storage.withConnection { connection in
            let feeds = FeedRepository(connection)
            let categories = CategoryRepository(connection)
            guard let resolved = try await category(categories, userID: userID, stream: stream),
                let categoryID = resolved.id else {
                throw SubscriptionError.categoryNotFound
            }

            if let rule = FeedValidation.validate(url: feedURL, categoryID: categoryID,
                urlIsAbsolute: URLRules.isAbsoluteURL(feedURL),
                feedURLExists: try await feeds.feedURLExists(userID: userID, url: feedURL),
                categoryExists: try await categories.categoryExists(userID: userID,
                    categoryID: categoryID)) {
                throw SubscriptionError.rule(rule)
            }

            let feed = try await feeds.create(userID: userID, categoryID: categoryID, url: feedURL)
            if !title.isEmpty { try await feeds.update(feed: feed, title: title, categoryID: nil) }
            return feed
        }
    }

    /// `rename`. The reference's own guard is the empty title, which the handler's title test
    /// answers before the read, so no input reaches it; the suite header names it rather than
    /// pinning it.
    private func rename(_ stream: GoogleReaderStream, title: String, userID: Int) async throws {
        let feedID = try Self.parseFeedID(stream.id)
        try await storage.withConnection { connection in
            let feeds = FeedRepository(connection)
            guard let feed = try await feeds.fetch(userID: userID, id: feedID) else {
                throw SubscriptionError.feedNotFound
            }
            try await feeds.update(feed: feed, title: title, categoryID: nil)
        }
    }

    /// `move`.
    private func move(_ stream: GoogleReaderStream, destination: GoogleReaderStream, userID: Int)
        async throws {
        let feedID = try Self.parseFeedID(stream.id)
        try await storage.withConnection { connection in
            let feeds = FeedRepository(connection)
            let categories = CategoryRepository(connection)
            guard let feed = try await feeds.fetch(userID: userID, id: feedID) else {
                throw SubscriptionError.feedNotFound
            }
            guard let resolved = try await category(categories, userID: userID, stream: destination),
                let categoryID = resolved.id else {
                throw SubscriptionError.categoryNotFound
            }
            try await feeds.update(feed: feed, title: nil, categoryID: categoryID)
        }
    }

    /// `unsubscribe`: the delete runs for every value of the list, and it does not read the row
    /// first.
    private func unsubscribe(_ streams: [GoogleReaderStream], userID: Int) async throws {
        try await storage.withConnection { connection in
            let feeds = FeedRepository(connection)
            for stream in streams {
                try await feeds.delete(id: try Self.parseFeedID(stream.id), userID: userID)
            }
        }
    }

    // MARK: - The wordings this handler writes

    /// `noStreamsMessage` is the answer for both halves of its guard — the list that is empty and
    /// the value the read could not parse — which is why the pins read the two inputs apart.
    static let noStreamsMessage = "googlereader: no valid stream IDs provided"

    /// The wording the move branch writes for a destination that is not a label.
    static let destinationMessage = "destination must be a label"

    /// The three wordings the reference declares as its own sentinels for this path, and the rule
    /// name the validation answers with. The port writes the rule name, which `docs/parity.md`
    /// records.
    enum SubscriptionError: Error, CustomStringConvertible {
        case feedNotFound
        case categoryNotFound
        case rule(FeedValidationRule)

        var description: String {
            switch self {
            case .feedNotFound: return "googlereader: feed not found"
            case .categoryNotFound: return "googlereader: category not found"
            case .rule(let rule): return rule.rawValue
            }
        }
    }

    /// `feedPrefix` + the row id, which is the form the document writes for a feed.
    private func feedPrefix(_ feed: Feed) -> String {
        "feed/\(feed.id ?? 0)"
    }
}
