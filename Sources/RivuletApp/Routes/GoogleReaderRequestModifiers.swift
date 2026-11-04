// Ported from Miniflux internal/googlereader/request_modifier.go, with the parameter names from
// internal/googlereader/parameters.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore

/// The stream filter the Google Reader router builds for one request.
///
/// Upstream reads it in `parseStreamFilterFromRequest`: the order first, then the three stream
/// lists, then the page size, the continuation value and the two times. Every stream value is read
/// through `getStream`, so the first value that matches no prefix ends the read, and the error
/// names the list it was read from — which `GoogleReaderRequestModifiersTests` pins. The page size
/// is the value the read answers; the clamp to `EntryQuery.maximumLimit` is a separate rule, pinned
/// by `EntryQueryTests`.
///
/// What this read cannot show: `WithOffset`'s branch that keeps only a positive offset, because the
/// parameter read already answers the default for a negative value; and that this read uses the URL
/// query rather than the merged form, so a POST body carrying `n` is not read here, which the suite
/// that sends the request pins.
struct GoogleReaderRequestModifiers {
    /// The names `internal/googlereader/parameters.go` declares for the query read.
    enum Parameter: String {
        case streamID = "s"
        case streamExcludes = "xt"
        case streamFilters = "it"
        case maxItems = "n"
        case streamOrder = "r"
        case startTime = "ot"
        case stopTime = "nt"
        case continuation = "c"
    }

    /// The default the order read is given, which is what answers descending.
    private static let defaultOrder = "d"

    let userID: Int
    let streams: [GoogleReaderStream]
    let excludeTargets: [GoogleReaderStream]
    let filterTargets: [GoogleReaderStream]
    let count: Int
    let offset: Int
    let sortDirection: String
    let startTime: Int64
    let stopTime: Int64

    init(query: GoogleReaderQuery, userID: Int) throws {
        // The order is what the reference reads first, and only this single value is ascending.
        self.sortDirection = query.string(named: Parameter.streamOrder.rawValue, default: Self.defaultOrder)
            == "o" ? "asc" : "desc"

        self.streams = try Self.readStreams(query.list(named: Parameter.streamID.rawValue), userID: userID)
        self.excludeTargets = try Self.readStreams(query.list(named: Parameter.streamExcludes.rawValue),
            userID: userID)
        self.filterTargets = try Self.readStreams(query.list(named: Parameter.streamFilters.rawValue),
            userID: userID)

        self.count = query.integer(named: Parameter.maxItems.rawValue, default: 0)
        self.offset = query.integer(named: Parameter.continuation.rawValue, default: 0)
        self.startTime = query.integer64(named: Parameter.startTime.rawValue, default: 0)
        self.stopTime = query.integer64(named: Parameter.stopTime.rawValue, default: 0)
        self.userID = userID
    }

    /// `getItemRefsAndContinuation`: the sum is the answer only while it is below the total, which
    /// is what the JSON shape leaves out. The count is what the page returned, not the page size
    /// asked for.
    static func continuation(returned: Int, offset: Int, total: Int) -> Int {
        returned + offset < total ? returned + offset : 0
    }

    /// `getStreams` for one list, in the order the pairs came in.
    private static func readStreams(_ values: [String], userID: Int) throws -> [GoogleReaderStream] {
        try values.map { try GoogleReaderStream.parse(streamID: $0, userID: userID) }
    }
}
