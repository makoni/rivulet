// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/opml/handler.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import FluentKit

/// The import and export paths the OPML records go through.
///
/// The import applies the steps in the reference's order for each record: the duplicate answer, the
/// category resolution, the rules, the row. The reference validates and creates per record, so a
/// record that fails a rule stops the run with the earlier writes standing, which `OPMLImportTests`
/// pins. The category resolution is the reference's three halves — the empty name reads the
/// smallest title, the named title is compared as given, and a name the account has no row for is
/// created — pinned as reads by `CategoryRepositoryTests`. The settings a row carries are the
/// fields this port's schema has; the reference's rules that read the others are not ported, so the
/// records carry the rest as data only, which the suite headers name. The export is the listing
/// order the reference's query builder answers, with the category title read through the join, and
/// the bytes the serializer writes.
public struct OPMLHandler: Sendable {
    private let storage: SQLiteStorage

    /// Creates the handler around the storage the reads and the writes run through.
    public init(_ storage: SQLiteStorage) {
        self.storage = storage
    }

    /// Reads the records and writes them, in the order the reference applies them per record.
    ///
    /// - Throws: `OPMLError` for the shape, the attribute set and the rule the first record fails
    ///   on, and the storage failures the reference wraps as `opml: unable to create this feed`.
    public func importFeeds(userID: Int, data: Data) async throws {
        let records = try OPMLParser.parse(data)

        try await storage.withConnection { connection in
            let feeds = FeedRepository(connection)
            let categories = CategoryRepository(connection)

            for record in records {
                // The duplicate answer runs before the resolution and the rules, so a record that
                // is already there resolves no category and fails no rule.
                if try await feeds.feedURLExists(userID: userID, url: record.feedURL) { continue }

                let categoryID = try await resolveCategory(userID: userID, name: record.categoryName,
                    categories: categories)

                // The two reads inside the rules always answer true here: a record that reaches
                // them was not a duplicate, and the category the resolution answers exists. Only
                // the guard and the absolute-URL rule can fire, and the guard's url half cannot,
                // because a record by definition carries a url.
                let failed = FeedValidation.validate(url: record.feedURL, categoryID: categoryID,
                    urlIsAbsolute: URLRules.isAbsoluteURL(record.feedURL),
                    feedURLExists: try await feeds.feedURLExists(userID: userID, url: record.feedURL),
                    categoryExists: try await categories.categoryExists(userID: userID,
                        categoryID: categoryID))
                if let failed {
                    throw OPMLError.invalidFeedSettings(rule: failed, feedURL: record.feedURL)
                }

                try await write(record, userID: userID, categoryID: categoryID, feeds: feeds,
                    on: connection)
            }
        }
    }

    /// Builds the document for `userID` and writes it.
    public func exportFeeds(userID: Int, now: Date) async throws -> String {
        try await storage.withConnection { connection in
            let rows = try await FeedRepository(connection)
                .listSortedByErrorCountThenTitle(userID: userID)
            let titles = try await categoryTitles(userID: userID,
                categories: CategoryRepository(connection))

            return OPMLSerializer.serialize(rows.map { row in record(of: row, titles: titles) },
                now: now)
        }
    }

    /// The reference's three halves of the category answer. The port's own half is the answer for a
    /// name with no row at all: the reference answers nil with no guard, while this port answers 0,
    /// which is what the guard's category half fails on.
    private func resolveCategory(userID: Int, name: String, categories: CategoryRepository)
        async throws -> Int {
        if name.isEmpty {
            return try await categories.first(userID: userID)?.id ?? 0
        }

        if let found = try await categories.byTitle(userID: userID, title: name) {
            return found.id ?? 0
        }
        return try await categories.create(userID: userID, title: name).id ?? 0
    }

    /// Writes the row through the pinned create path and then the settings it carries. The
    /// reference writes the settings inside its insert; this port's create path writes the
    /// reference's defaults, so the settings the schema has are applied as the fields of the row.
    private func write(_ record: OPMLSubscription, userID: Int, categoryID: Int,
        feeds: FeedRepository, on connection: any Database) async throws {
        let feed = try await feeds.create(userID: userID, categoryID: categoryID, url: record.feedURL)
        feed.title = record.title
        feed.siteURL = record.siteURL
        feed.feedDescription = record.description
        feed.userAgent = record.userAgent
        feed.ignoreHTTPCache = record.ignoreHTTPCache
        feed.fetchViaProxy = record.fetchViaProxy
        feed.disabled = record.disabled
        try await feed.update(on: connection)
    }

    /// The join the export reads: the title of the row each feed points at.
    private func categoryTitles(userID: Int, categories: CategoryRepository) async throws
        -> [Int: String] {
        var titles: [Int: String] = [:]
        for category in try await categories.list(userID: userID) {
            if let id = category.id { titles[id] = category.title }
        }
        return titles
    }

    private func record(of row: Feed, titles: [Int: String]) -> OPMLSubscription {
        var record = OPMLSubscription()
        record.title = row.title
        record.feedURL = row.url
        record.siteURL = row.siteURL
        record.description = row.feedDescription
        record.categoryName = titles[row.categoryID] ?? ""
        record.userAgent = row.userAgent
        record.ignoreHTTPCache = row.ignoreHTTPCache
        record.fetchViaProxy = row.fetchViaProxy
        record.disabled = row.disabled
        return record
    }
}
