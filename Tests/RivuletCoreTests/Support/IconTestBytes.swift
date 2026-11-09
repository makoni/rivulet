import Foundation

/// The bytes the icon resize reads, built so a pin can name a rule about the header read.
///
/// `pngHeaderOnly` is what the upstream test writes with `mustMinimalPNG`: the config read answers
/// these dimensions, while the pixel decode has no image data to read. The other builders answer a
/// file the pixel decode can read, so a pin that says a guard runs before the decode can fail on a
/// patch that moves it after.
enum IconTestBytes {
    /// PNG signature, IHDR and IEND, with no IDAT.
    static func pngHeaderOnly(width: Int, height: Int) -> Data {
        chunks([pngSignature, chunk("IHDR", big32(width) + big32(height) + [8, 2, 0, 0, 0]),
                chunk("IEND", [])])
    }

    /// A PNG the pixel decode can read: IHDR, one IDAT with a stored block and a filter byte of 0
    /// for each row, then IEND.
    static func pngDecodable(width: Int, height: Int) -> Data {
        var raw: [UInt8] = []
        for _ in 0 ..< height {
            raw.append(0)
            raw.append(contentsOf: [UInt8](repeating: 7, count: width * 3))
        }
        return chunks([pngSignature, chunk("IHDR", big32(width) + big32(height) + [8, 2, 0, 0, 0]),
                       chunk("IDAT", storedBlock(raw)), chunk("IEND", [])])
    }

    /// GIF89a with these logical screen dimensions, 13 bytes, which is what `gif.DecodeConfig`
    /// reads. The pin that names the guard for a file too short for its own header writes one byte
    /// less.
    static func gif(width: Int, height: Int, length: Int = 13) -> Data {
        var bytes: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
                              UInt8(width & 0xFF), UInt8(width >> 8),
                              UInt8(height & 0xFF), UInt8(height >> 8), 0, 0, 0]
        if length < bytes.count { bytes = Array(bytes[0 ..< length]) }
        return Data(bytes)
    }

    /// JPEG with these frame dimensions and no scan data, the frame segment written as `processSOF`
    /// reads it, so the config read answers the dimensions and the pixel decode has nothing to
    /// read. The marker, the precision, the count byte and the length are arguments because the pin
    /// that names the shape rules writes one of them wrong, and the padding keeps the declared
    /// length inside the file, so the rule a pin names is the answer rather than the bounds guard.
    /// The table segment is an argument too: the pin that names the segment walk needs a segment
    /// before the frame one, while the pins that name the shape rules read the frame as the first
    /// segment, so a patch that changes the walk cannot change their answer and each probe fires
    /// alone.
    static func jpeg(marker: UInt8 = 0xC0, precision: UInt8 = 8, count: UInt8 = 1, length: Int? = nil,
                     width: Int, height: Int, tableSegment: Bool = false) -> Data {
        let data: [UInt8] = [precision, UInt8(height >> 8), UInt8(height & 0xFF),
                             UInt8(width >> 8), UInt8(width & 0xFF), count]
            + [UInt8](repeating: 1, count: 3 * Int(count))
        // The length names the bytes after itself, which is what `processSOF` is given.
        let declared = length ?? 8 + 3 * Int(count)
        let frame: [UInt8] = [0xFF, marker, UInt8(declared >> 8), UInt8(declared & 0xFF)]
            + data + [UInt8](repeating: 0, count: max(0, declared - 2 - data.count))
        var bytes = [0xFF, 0xD8] + (tableSegment ? [0xFF, 0xC4, 0x00, 0x02] : []) + frame
        // Kept past the length of the longest magic, so the probe that fixes that length reads only
        // the rule it names and stops here. The end-of-image marker is what closes the file.
        while bytes.count < 20 { bytes.append(0) }
        return Data(bytes + [0xFF, 0xD9])
    }

    /// A WebP whose chunk is the lossy one: three frame-tag bytes, the sync code, then the two
    /// 14-bit dimensions, which this shape answers as they are stored.
    static func webpVP8(width: Int, height: Int, keyFrame: Bool = true) -> Data {
        let tag = keyFrame ? UInt8(0x00) : UInt8(0x01)
        return Data(riff("VP8 ", [tag, 0x01, 0x00, 0x9D, 0x01, 0x2A,
                           UInt8(width & 0xFF), UInt8(width >> 8),
                           UInt8(height & 0xFF), UInt8(height >> 8)]))
    }

    /// A WebP whose chunk is the packed one, which stores the canvas as two 14-bit values.
    static func webpVP8L(width: Int, height: Int) -> Data {
        let value = UInt32(width - 1) | UInt32(height - 1) << 14
        return Data(riff("VP8L", [0x2F] + big32(Int(value))))
    }

    /// A WebP whose chunk is the extended one, which stores the canvas as the value minus one.
    static func webpVP8X(width: Int, height: Int) -> Data {
        Data(riff("VP8X", [0, 0, 0, 0] + small32(width - 1) + small32(height - 1)))
    }

    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    private static func chunks(_ parts: [[UInt8]]) -> Data {
        Data(parts.flatMap { $0 })
    }

    private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let name = [UInt8](type.utf8)
        return big32(data.count) + name + data + big32(Int(crc32(name + data)))
    }

    private static func storedBlock(_ raw: [UInt8]) -> [UInt8] {
        var block: [UInt8] = [0x78, 0x01, 0x01]
        block += [UInt8(raw.count & 0xFF), UInt8(raw.count >> 8)]
        let inverted = ~UInt16(raw.count)
        block += [UInt8(inverted & 0xFF), UInt8(inverted >> 8)]
        block += raw
        block += big32(Int(adler32(raw)))
        return block
    }

    private static func riff(_ fourCC: String, _ data: [UInt8]) -> [UInt8] {
        let size = 4 + data.count
        var bytes: [UInt8] = [0x52, 0x49, 0x46, 0x46]
        bytes += little32(size)
        bytes += [UInt8](Data("WEBP".utf8)) + [UInt8](Data(fourCC.utf8)) + little32(size) + data
        return bytes
    }

    private static func big32(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func little32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF)]
    }

    private static func small32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF)]
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var value = UInt32(0xFFFF_FFFF)
        for byte in bytes {
            value ^= UInt32(byte)
            for _ in 0 ..< 8 {
                value = (value & 1 == 1) ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
        }
        return value ^ 0xFFFF_FFFF
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a = UInt32(1), b = UInt32(0)
        for byte in bytes {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return (b << 16) | a
    }
}
