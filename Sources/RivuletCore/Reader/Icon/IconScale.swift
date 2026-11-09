// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`resizeIcon`, the scale step)
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The scale the resize runs, read as the port names it.
///
/// The reference scales with `draw.BiLinear`, which answers its own values for the pixels between
/// the samples; this port samples the same two neighbours but rounds its own way, so the bytes of
/// the document it writes are not the bytes the reference writes. That is recorded in
/// `docs/parity.md`, and the pins read the dimensions and the content type of the document rather
/// than its pixels.
enum IconScale {
    /// The 32×32 rows the destination holds.
    static func bilinear(_ rows: [[UInt8]], width: Int, height: Int) -> [[UInt8]] {
        guard width > 0, height > 0 else { return [] }
        var scaled: [[UInt8]] = []
        for y in 0 ..< 32 {
            var row: [UInt8] = []
            for x in 0 ..< 32 {
                row.append(contentsOf: sample(rows, width: width, height: height, x: x, y: y))
            }
            scaled.append(row)
        }
        return scaled
    }

    /// The four neighbours of the point this pixel stands for, weighted as the bilinear rule reads
    /// them, and rounded to a whole value.
    private static func sample(_ rows: [[UInt8]], width: Int, height: Int, x: Int, y: Int) -> [UInt8] {
        let sx = (Double(x) + 0.5) * Double(width) / 32.0, sy = (Double(y) + 0.5) * Double(height) / 32.0
        let x0 = min(max(Int(floor(sx)), 0), width - 1), y0 = min(max(Int(floor(sy)), 0), height - 1)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = sx - floor(sx), fy = sy - floor(sy)
        var values: [UInt8] = []
        for channel in 0 ..< 3 {
            let top = Double(rows[y0][x0 * 3 + channel]) * (1 - fx) + Double(rows[y0][x1 * 3 + channel]) * fx
            let bottom = Double(rows[y1][x0 * 3 + channel]) * (1 - fx) + Double(rows[y1][x1 * 3 + channel]) * fx
            values.append(UInt8((top * (1 - fy) + bottom * fy).rounded()))
        }
        return values
    }
}
