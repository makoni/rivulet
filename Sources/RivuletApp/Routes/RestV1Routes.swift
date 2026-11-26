// Ported from Miniflux internal/api/api.go's mux (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The route this path answers on.
public enum RestV1Routes {
    ///Registers the route on the application.  `RestV1Auth` is the wrapper the reference's chain
    ///puts on every route of this path, so it is applied per route rather than as application
    ///middleware that would cover `/healthz` too.  The reference's mux has one pattern per path
    ///with the method written on it, and this stage registers the paths its scope has: the account
    ///path, the five category paths, the eight feed paths, the five entry paths and the one
    ///integrations path the consumer declares. The answer for
    ///another method and the answer for a path no pattern registers are recorded in
    ///`docs/parity.md`, and the pin for this prefix reads the router's answer for a path with no
    ///pattern.
    public static func register(on application: Application, storage: SQLiteStorage,
        hasher: BcryptHasher, runner: FeedRefreshRunner) {
        let auth = RestV1Auth(storage: storage, hasher: hasher)
        let handlers = RestV1Handlers(storage: storage, runner: runner)

        application.grouped("v1").get("me", use: auth.withAuth { request, userID in
            try await handlers.me(request: request, userID: userID)
        })

        // The six category paths the consumer declares. The reference's mux has no GET pattern for
        // `GET /v1/categories/{categoryID}`, so no route is registered for it here either: the answer
        // for that path is the router's, which is what the pin for it reads.
        application.grouped("v1").get("categories", use: auth.withAuth { request, userID in
            try await handlers.categories(request: request, userID: userID)
        })
        application.grouped("v1").post("categories", use: auth.withAuth { request, userID in
            try await handlers.createCategory(request: request, userID: userID)
        })
        application.grouped("v1").put("categories", ":categoryID", use: auth.withAuth { request, userID in
            try await handlers.updateCategory(request: request, userID: userID)
        })
        application.grouped("v1").delete("categories", ":categoryID", use: auth.withAuth { request, userID in
            try await handlers.removeCategory(request: request, userID: userID)
        })
        application.grouped("v1").get("categories", ":categoryID", "feeds", use: auth.withAuth { request, userID in
            try await handlers.categoryFeeds(request: request, userID: userID)
        })

        // The eight feed paths the consumer declares, one pattern per path with the method written on
        // it, as the reference's mux has them.
        application.grouped("v1").get("feeds", use: auth.withAuth { request, userID in
            try await handlers.feeds(request: request, userID: userID)
        })
        application.grouped("v1").post("feeds", use: auth.withAuth { request, userID in
            try await handlers.createFeed(request: request, userID: userID)
        })
        application.grouped("v1").get("feeds", ":feedID", use: auth.withAuth { request, userID in
            try await handlers.feed(request: request, userID: userID)
        })
        application.grouped("v1").put("feeds", ":feedID", use: auth.withAuth { request, userID in
            try await handlers.updateFeed(request: request, userID: userID)
        })
        application.grouped("v1").delete("feeds", ":feedID", use: auth.withAuth { request, userID in
            try await handlers.removeFeed(request: request, userID: userID)
        })
        application.grouped("v1").get("feeds", ":feedID", "icon", use: auth.withAuth { request, userID in
            try await handlers.feedIcon(request: request, userID: userID)
        })
        application.grouped("v1").put("feeds", ":feedID", "refresh", use: auth.withAuth { request, userID in
            try await handlers.refreshFeed(request: request, userID: userID)
        })
        application.grouped("v1").put("feeds", ":feedID", "mark-all-as-read",
            use: auth.withAuth { request, userID in
                try await handlers.markFeedAsRead(request: request, userID: userID)
            })

        // The five entry paths the consumer declares, in the order the reference's mux has them.
        application.grouped("v1").get("feeds", ":feedID", "entries", use: auth.withAuth { request, userID in
            try await handlers.feedEntries(request: request, userID: userID)
        })
        application.grouped("v1").get("entries", use: auth.withAuth { request, userID in
            try await handlers.entries(request: request, userID: userID)
        })
        application.grouped("v1").put("entries", use: auth.withAuth { request, userID in
            try await handlers.updateEntries(request: request, userID: userID)
        })
        application.grouped("v1").get("entries", ":entryID", use: auth.withAuth { request, userID in
            try await handlers.entry(request: request, userID: userID)
        })
        application.grouped("v1").put("entries", ":entryID", "bookmark",
            use: auth.withAuth { request, userID in
                try await handlers.toggleStarred(request: request, userID: userID)
            })

        // The one integrations path the consumer declares.
        application.grouped("v1").get("integrations", "status", use: auth.withAuth { request, userID in
            try await handlers.integrationsStatus(request: request, userID: userID)
        })
    }
}
