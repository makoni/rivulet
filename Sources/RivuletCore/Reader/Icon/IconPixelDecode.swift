// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`resizeIcon`, the decode switch)
// (Apache-2.0); adapted for Swift/SQLite over tayloraswift/swift-png and tayloraswift/swift-jpeg.

import Foundation
import JPEG
import PNG

/// The pixels the reference's switch decodes, read for the content type as it was declared.
///
/// The switch chooses by the name the response carried, not by the file's own magic, so a file
/// whose bytes are a format the decoder here does not have answers nothing, and the resize leaves
/// the bytes as they were. This port has no decoder for GIF or WebP, which `docs/parity.md`
/// records: the reference decodes both, so for a file of either that is above 32×32 the two answers
/// part.
enum IconPixelDecode {
    /// Rows of pixels, each row three values per pixel.
    static func rows(mimeType: String, bytes: [UInt8]) -> [[UInt8]]? {
        switch mimeType {
        case "image/png": return pngRows(bytes)
        case "image/jpeg": return jpegRows(bytes)
        default: return nil
        }
    }

    private static func pngRows(_ bytes: [UInt8]) -> [[UInt8]]? {
        var source = BytestreamSource(bytes)
        guard let image = try? PNG.Image.decompress(stream: &source) else { return nil }
        let pixels = image.unpack(as: PNG.RGBA<UInt8>.self)
        return rowsOf(pixels.map { [$0.r, $0.g, $0.b] }, width: image.size.x, height: image.size.y)
    }

    private static func jpegRows(_ bytes: [UInt8]) -> [[UInt8]]? {
        var source = BytestreamSource(bytes)
        guard let image = try? JPEG.Data.Rectangular<JPEG.Common>.decompress(stream: &source, cosite: false)
        else { return nil }
        let pixels = image.unpack(as: JPEG.RGB.self)
        return rowsOf(pixels.map { [$0.r, $0.g, $0.b] }, width: image.size.x, height: image.size.y)
    }

    private static func rowsOf(_ pixels: [[UInt8]], width: Int, height: Int) -> [[UInt8]]? {
        guard width > 0 && height > 0, pixels.count == width * height else { return nil }
        var rows: [[UInt8]] = []
        for row in 0 ..< height {
            rows.append(Array(pixels[row * width ..< (row + 1) * width].flatMap { $0 }))
        }
        return rows
    }

    /// The source shape both libraries read through, over the bytes the response body was.
    private struct BytestreamSource: PNG.BytestreamSource, JPEG.Bytestream.Source {
        private let bytes: [UInt8]
        private var position = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func read(count: Int) -> [UInt8]? {
            guard position + count <= bytes.count else { return nil }
            defer { position += count }
            return Array(bytes[position ..< position + count])
        }
    }
}
