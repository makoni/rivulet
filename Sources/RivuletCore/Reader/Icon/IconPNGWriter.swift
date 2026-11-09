// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`resizeIcon`, the encode step)
// (Apache-2.0); adapted for Swift/SQLite over tayloraswift/swift-png.

import Foundation
import PNG

/// The document the resize writes: the encoder the reference's own branch uses, over the rows the
/// scale produced.
enum IconPNGWriter {
    /// The bytes as the encoder writes them, or nothing for a file it cannot write.
    static func png(_ rows: [[UInt8]]) -> Data? {
        var pixels: [PNG.RGBA<UInt8>] = []
        for row in rows {
            var index = 0
            while index + 2 < row.count {
                pixels.append(PNG.RGBA(row[index], row[index + 1], row[index + 2], 255))
                index += 3
            }
        }
        let layout = PNG.Layout(format: .rgba8(palette: [], fill: nil))
        var sink = BytestreamDestination()
        let image = PNG.Image(packing: pixels, size: (32, 32), layout: layout)
        guard (try? image.compress(stream: &sink)) != nil else { return nil }
        return Data(sink.bytes)
    }

    private struct BytestreamDestination: PNG.BytestreamDestination {
        var bytes: [UInt8] = []

        mutating func write(_ buffer: [UInt8]) -> Void? {
            bytes.append(contentsOf: buffer)
            return ()
        }
    }
}
