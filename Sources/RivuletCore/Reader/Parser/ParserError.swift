// Ported from Miniflux internal/reader/parser (Apache-2.0); adapted for Swift/SQLite. The
// failure is the reference's sentinel `ErrFeedFormatNotDetected`
// (`internal/reader/parser/parser.go:17`).

/// The failure the parser reports for a document it cannot decide on.
///
/// The reference has one error on this path, the sentinel, and reports it for any document its
/// detection answers `unknown` for. The port models it as one case with no payload, so a pin
/// can compare the case and not the wording: the wording is the reference's own data in the
/// corpus the test reads, and a pin that reads it could not fail on it.
enum ParserError: Error, Equatable, Sendable {
    /// A document the scan decided on no format: no root with a name the switch reads, and
    /// nothing the JSON rule could read to the end of the buffer.
    case feedFormatNotDetected
}
