// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`image.DecodeConfig` dispatch)
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The dimensions `image.DecodeConfig` answers for an icon.
///
/// The read matches the magic, not the content type the response carried, so a file whose bytes are
/// one of the four formats is read here even when the name says another one. Each magic is compared
/// at the length of its own magic — Go's `sniff` peeks that many bytes, so a file shorter than the
/// magic is nothing to read, and a file long enough to match but too short for the header its own
/// format reads is the error the read reports. The WebP magic names the bytes up to the chunk name,
/// so all three chunk names reach the read, and each answers its own shape: the lossy one as a
/// 14-bit pair after its frame header, the packed one as two 14-bit values, and the extended one as
/// the stored canvas plus one.
enum IconImageHeader {
    /// The dimensions as the read answers them, or nothing for a file it cannot match.
    static func dimensions(of bytes: [UInt8]) -> (width: Int, height: Int)? {
        switch magic(of: bytes) {
        case .png: return png(bytes)
        case .gif: return gif(bytes)
        case .jpeg: return jpeg(bytes)
        case .webp: return webp(bytes)
        case nil: return nil
        }
    }

    private enum Format {
        case png, gif, jpeg, webp
    }

    /// The magics the reference registers, each compared at the length of its own magic.
    private static func magic(of bytes: [UInt8]) -> Format? {
        if has(bytes, pngSignature) { return .png }
        if has(bytes, [0xFF, 0xD8]) { return .jpeg }
        if has(bytes, [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
            has(bytes, [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) { return .gif }
        if has(bytes, [0x52, 0x49, 0x46, 0x46]) && has(bytes, [0x57, 0x45, 0x42, 0x50], at: 8) &&
            has(bytes, [0x56, 0x50, 0x38], at: 12) { return .webp }
        return nil
    }

    /// The IHDR fields, which must be the first chunk of the file and 13 bytes long.
    private static func png(_ bytes: [UInt8]) -> (width: Int, height: Int)? {
        guard bytes.count >= 29, chunk(bytes, at: 12, names: "IHDR"), big32(bytes, 8) == 13 else { return nil }
        return (Int(big32(bytes, 16)), Int(big32(bytes, 20)))
    }

    /// The logical screen size, which `gif.DecodeConfig` answers without reading the frames.
    private static func gif(_ bytes: [UInt8]) -> (width: Int, height: Int)? {
        guard bytes.count >= 10 else { return nil }
        return (Int(little16(bytes, 6)), Int(little16(bytes, 8)))
    }

    /// The segments are walked until one of them names a start-of-frame, which is precision and
    /// then the two dimensions, each 16-bit and read as the segment length is read: big-endian.
    private static func jpeg(_ bytes: [UInt8]) -> (width: Int, height: Int)? {
        var position = 2
        while position + 1 < bytes.count {
            guard bytes[position] == 0xFF else { return nil }
            let marker = bytes[position + 1]
            position += 2
            if marker >= 0xD0 && marker <= 0xD9 { continue }
            guard position + 1 < bytes.count else { return nil }
            let length = Int(big16(bytes, position))
            if (marker >= 0xC0 && marker <= 0xCF) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC {
                guard length >= 6, position + 7 <= bytes.count else { return nil }
                // The segment data is precision and then the two dimensions, height first, which is
                // the order `processSOF` reads them in.
                return (Int(big16(bytes, position + 5)), Int(big16(bytes, position + 3)))
            }
            position += length
        }
        return nil
    }

    /// The chunk name chooses the shape. The chunk data begins after the container header and the
    /// four-byte chunk name, which is 20 bytes into the file.
    private static func webp(_ bytes: [UInt8]) -> (width: Int, height: Int)? {
        guard bytes.count >= 16 else { return nil }
        if chunk(bytes, at: 12, names: "VP8L") { return vp8l(bytes) }
        if chunk(bytes, at: 12, names: "VP8X") {
            guard bytes.count >= 30 else { return nil }
            return (Int(small24(bytes, 24)) + 1, Int(small24(bytes, 27)) + 1)
        }
        // The frame header: three bytes of frame tag, then the sync code, then the two 14-bit
        // dimensions. A frame that is not a key frame has no header, so the read answers zero,
        // which is the value the reference's dimension guard reads.
        guard bytes.count >= 23 else { return nil }
        if bytes[20] & 1 != 0 { return (0, 0) }
        guard bytes.count >= 30, Array(bytes[23 ..< 26]) == [0x9D, 0x01, 0x2A] else { return nil }
        return (Int(little16(bytes, 26)) & 0x3FFF, Int(little16(bytes, 28)) & 0x3FFF)
    }

    /// The packed header: the magic byte, then two 14-bit values read from the low end of the word.
    private static func vp8l(_ bytes: [UInt8]) -> (width: Int, height: Int)? {
        guard bytes.count >= 25, bytes[20] == 0x2F else { return nil }
        let value = big32(bytes, 21)
        return (Int(value & 0x3FFF) + 1, Int((value >> 14) & 0x3FFF) + 1)
    }

    private static func has(_ bytes: [UInt8], _ magic: [UInt8], at start: Int = 0) -> Bool {
        guard bytes.count >= start + magic.count else { return false }
        for (index, byte) in magic.enumerated() where bytes[start + index] != byte {
            return false
        }
        return true
    }

    private static func chunk(_ bytes: [UInt8], at start: Int, names name: String) -> Bool {
        [UInt8](bytes[start ..< start + 4]) == [UInt8](name.utf8)
    }

    private static func big32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
    }

    private static func big16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
    }

    private static func little16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func small24(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16
    }

    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
}
