// Ported from Miniflux internal/http/request/params.go's `RouteInt64Param` (Apache-2.0); adapted for
// Swift/SQLite.

/// The path segment this path reads as a number.
enum RestV1RouteParam {
    /// `RouteInt64Param`: a segment the read fails on answers 0, which is what the handler's guard
    /// reads. The read admits an optional sign and the digits, and nothing else, so a segment with a
    /// space, a prefix, or a letter after the digits answers 0.
    static func integer(_ segment: String) -> Int {
        Int(segment) ?? 0
    }
}
