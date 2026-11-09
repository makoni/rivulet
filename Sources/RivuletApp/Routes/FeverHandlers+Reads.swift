// Ported from Miniflux internal/fever/handler.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

extension FeverHandlers {
    /// `handleGroups`: the groups in the title order the read builds — not the position order the
    /// listing read has — and the group rows built from the feeds listing, in the order that
    /// listing answers, with the groups in the order their first feed appears in it.
    func groupsDocument(userID: Int) async throws -> Response {
        do {
            let (categories, feeds) = try await storage.withConnection { connection in
                (try await CategoryRepository(connection).listByTitle(userID: userID),
                    try await FeedRepository(connection).listSortedByErrorCountThenTitle(userID: userID))
            }

            let groups = categories.compactMap { category in
                category.id.map { FeverShape.group(id: $0, title: category.title) }
            }
            return GoogleReaderResponse.json(FeverShape.groupsDocument(groups: groups,
                feedsGroups: feedGroups(feeds), lastRefreshed: Self.now()))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `handleFeeds`: the seven fields of the row, with `favicon_id` written as the zero for a feed
    /// that points at no icon row.
    func feedsDocument(userID: Int) async throws -> Response {
        do {
            let feeds = try await storage.withConnection { connection in
                try await FeedRepository(connection).listSortedByErrorCountThenTitle(userID: userID)
            }

            let rows = feeds.compactMap { feed in
                feed.id.map { FeverShape.feed(id: $0, faviconID: feed.iconID ?? 0, title: feed.title,
                    url: feed.url, siteURL: feed.siteURL, lastUpdated: Int64(feed.fetchedAt ?? 0)) }
            }
            return GoogleReaderResponse.json(FeverShape.feedsDocument(feeds: rows,
                feedsGroups: feedGroups(feeds), lastRefreshed: Self.now()))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `handleFavicons`: the join answers one row per feed, so an icon shared by two feeds is
    /// written twice, and the data field is the stored content type and the standard base64 of
    /// the bytes.
    func faviconsDocument(userID: Int) async throws -> Response {
        do {
            let icons = try await storage.withConnection { connection in
                try await IconRepository(connection).listForUser(userID: userID)
            }

            let rows = icons.compactMap { icon in
                icon.id.map { FeverShape.favicon(id: $0, data: icon.dataURL()) }
            }
            return GoogleReaderResponse.json(FeverShape.faviconsDocument(favicons: rows,
                lastRefreshed: Self.now()))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `handleUnreadItems`: the ids the read answers, joined with a comma, and the empty answer
    /// written as the empty string.
    func unreadDocument(userID: Int) async throws -> Response {
        do {
            let ids = try await entryIDs(EntryQuery(userID: userID, statuses: [.unread]))
            return GoogleReaderResponse.json(FeverShape.unreadDocument(ids: joined(ids),
                lastRefreshed: Self.now()))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `handleSavedItems`: the same read with the starred filter.
    func savedDocument(userID: Int) async throws -> Response {
        do {
            let ids = try await entryIDs(EntryQuery(userID: userID, starred: true))
            return GoogleReaderResponse.json(FeverShape.savedDocument(ids: joined(ids),
                lastRefreshed: Self.now()))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// `buildFeedGroups`: one row per category, the ids in the order the listing answers them, and
    /// the rows in the order the categories first appear in that listing. The reference builds a
    /// map, so its order is not fixed; this order is the port's own, and the pins read it.
    private func feedGroups(_ feeds: [Feed]) -> [JSONValue] {
        var order: [Int] = []
        var idsByCategory: [Int: [String]] = [:]
        for feed in feeds {
            guard let feedID = feed.id else { continue }
            if idsByCategory[feed.categoryID] == nil { order.append(feed.categoryID) }
            idsByCategory[feed.categoryID, default: []].append(String(feedID))
        }
        return order.map {
            FeverShape.feedsGroup(groupID: $0, feedIDs: idsByCategory[$0]!.joined(separator: ","))
        }
    }

    /// The read the two id documents are built from, and the join the field carries.
    private func entryIDs(_ query: EntryQuery) async throws -> [Int] {
        try await storage.withConnection { connection in
            try await EntryRepository(connection).listIDs(query)
        }
    }

    private func joined(_ ids: [Int]) -> String {
        ids.map { String($0) }.joined(separator: ",")
    }
}
