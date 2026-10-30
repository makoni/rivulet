// Ported from Miniflux internal/reader/parser (Apache-2.0); adapted for Swift/SQLite.

/// The decision the switch in `ParseFeed` makes for one document: which format's parser the
/// reference calls, and with what, or no route at all for a document the detection decided on
/// no format, which is what ``ParserError/feedFormatNotDetected`` is reported for.
///
/// The Atom branch is the one that reads the version: `atom.Parse` calls the parser for Atom
/// 0.3 when the version says `0.3` and the one for Atom 1.0 for anything else
/// (`internal/reader/atom/parser.go:16-27`). The reference reports no version for the other
/// formats, so only the Atom route carries one.
enum FeedFormatRoute: Equatable, Sendable {
    case atom(version: String)
    case rss
    case rdf
    case json
    case none
}
