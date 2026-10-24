// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/date/parser.go
// (Apache-2.0); adapted for Swift/SQLite.

/// A parsed date, as Go's `time.Time` reports it after `time.Parse`: the instant, the fractional
/// part, and the zone the parse resolved to.
///
/// The instant is seconds from the Unix epoch, so a layout without a date (which Go reads as year
/// 0) still has an exact value here, without a `Calendar` involved. `zoneName` and
/// `zoneOffsetSeconds` are what Go's `Zone()` would report, with the fixed table described in
/// `docs/parity.md` in place of the machine's local zone.
struct ParsedDate: Equatable, Sendable {
    var epochSeconds: Int64
    var nanoseconds: Int64
    var zoneName: String
    var zoneOffsetSeconds: Int
}
