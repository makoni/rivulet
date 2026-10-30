// Ported from Miniflux internal/reader/parser/parser.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The parser's path: the decision format detection makes, and the adapter the switch routes
/// to.
///
/// The switch is the one `ParseFeed` makes (`internal/reader/parser/parser.go:22-33`), with the
/// reference's sentinel as the answer for a document the detection decided on no format. The
/// decision is kept apart from the routing so a test can read it without running an adapter,
/// which is what the corpus the tests read pins. The time is a parameter rather than a clock
/// read, because the adapters that take it are pinned against values the reference produced
/// with the clock fixed.
enum FeedParser {
    /// The decision the switch makes for one document: which format's parser the reference
    /// would call.
    static func route(_ data: Data) -> FeedFormatRoute {
        let detected = FeedFormatDetector.detect(data)
        switch detected.format {
        case .atom: return .atom(version: detected.version ?? "")
        case .rss: return .rss
        case .rdf: return .rdf
        case .json: return .json
        case .unknown: return .none
        }
    }

    /// A document read through the parser's path: the decision, and the adapter it routes to.
    static func parse(baseURL: String, data: Data, now: ParsedDate) throws -> ParsedFeed {
        switch route(data) {
        case .atom(let version):
            if version == "0.3" {
                return try Atom03Adapter.parse(baseURL: baseURL, data: data, now: now)
            }
            return try Atom10Adapter.parse(baseURL: baseURL, data: data, now: now)
        case .rss: return try RSSAdapter.parse(baseURL: baseURL, data: data, now: now)
        case .rdf: return try RDFAdapter.parse(baseURL: baseURL, data: data, now: now)
        case .json: return try JSONFeedAdapter.parse(baseURL: baseURL, data: data, now: now)
        case .none: throw ParserError.feedFormatNotDetected
        }
    }
}
