// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/date/parser.go
// (`parseLocalTimeDates`) and Go's standard library `time/format.go` (`parse`); adapted for
// Swift/SQLite.

import Foundation

/// The fixed zone table the port uses in place of the machine's tzdata.
///
/// Go's `lookupName` asks the machine's local zone, so an abbreviation the local zone does not know
/// gets the documented fallback offset of zero, and the reference's `PST`/`PDT` and `EST`/`EDT`
/// workaround only ever resolves through Los Angeles and New York. The four names here are those
/// two locations' offsets read as fixed values, because a `Location` lookup depends on the instant
/// and on the machine's tzdata, which is not reproducible; the deviation is recorded in
/// `docs/parity.md`.
///
/// A `GMT` name with an hour offset keeps the offset that came with the name, which is what Go does
/// when the name lookup fails; the name itself is longer than three characters in that case.
enum DateZoneTable {
    static func offset(forName name: String) -> Int {
        switch name {
        case "PST":
            return -28_800
        case "PDT":
            return -25_200
        case "EST":
            return -18_000
        case "EDT":
            return -14_400
        case "UTC", "GMT":
            return 0
        default:
            guard name.hasPrefix("GMT"), name.count > 3 else {
                return 0
            }
            // `parseGMT` only lets a signed hour through, so the rest of the name is that number.
            return (Int(name.dropFirst(3)) ?? 0) * 3_600
        }
    }
}
