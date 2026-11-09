// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`resizeIcon`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// `resizeIcon` of `internal/reader/icon/finder.go` at `c4d54f87`.
///
/// The order is the reference's: the SVG branch runs before the type list, the four types of the
/// switch are the only ones that reach the read, the dimensions are read from the file's own magic,
/// a header the read cannot answer or a pixel array the decoder cannot read leaves the bytes as
/// they were, a side strictly greater than 4096 or a pixel count greater than 4096×4096 is the
/// rejection the search continues past, a file at or under 32×32 is left as it is, and anything
/// else becomes a 32×32 PNG with the content type written as the literal `image/png`.
enum IconResize {
    /// The icon as the search answers it: nothing for a file this read rejects, which is the answer
    /// the reference continues past.
    static func resize(_ candidate: IconCandidate) -> IconCandidate? {
        // The reference minifies an SVG here; this port has no minifier, so the bytes are passed on
        // as they were, which `docs/parity.md` records.
        if candidate.mimeType == "image/svg+xml" { return candidate }

        guard IconResize.readTypes.contains(candidate.mimeType) else { return candidate }

        let bytes = [UInt8](candidate.content)
        guard let dimensions = IconImageHeader.dimensions(of: bytes) else { return candidate }
        guard dimensions.width > 0 && dimensions.height > 0 else { return candidate }

        let pixels = Int64(dimensions.width) * Int64(dimensions.height)
        if dimensions.width > maxDimension || dimensions.height > maxDimension || pixels > maxPixels {
            return nil
        }

        if dimensions.height <= 32 && dimensions.width <= 32 { return candidate }

        let decoded = IconPixelDecode.rows(mimeType: candidate.mimeType, bytes: bytes)
        guard let rows = decoded else { return candidate }

        let scaled = IconScale.bilinear(rows, width: dimensions.width, height: dimensions.height)
        guard let written = IconPNGWriter.png(scaled) else { return candidate }

        return IconCandidate.resized(from: candidate, content: written, mimeType: "image/png")
    }

    private static let maxDimension = 4096
    private static let maxPixels = 4096 * 4096

    private static let readTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]
}
