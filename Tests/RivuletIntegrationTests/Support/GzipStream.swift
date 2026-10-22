import Foundation

/// Writes a gzip stream for the stub feed server, so a fetch test can hand the client a
/// compressed body without adding a compression dependency.
///
/// Stored DEFLATE blocks are used — gzip allows an uncompressed block — which keeps the encoder
/// small. The output is a valid gzip stream; it is checked against `gunzip` by hand when this encoder
/// changes, because there is no decoder in the suite that could prove it. The fetch test therefore
/// shows that the client decompresses a fixture built by this encoder, not that the encoder is
/// correct — `docs/testing.md` says the same. A stored block cannot reach a compression ratio above 1,
/// so the ratio guard the fetcher sets is not exercised here either.
enum GzipStream {
    /// Writes the stream for `data`.
    static func compress(_ data: Data) -> Data {
        var output = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])

        var offset = 0
        while true {
            let length = min(data.count - offset, 65_535)
            let isLast = offset + length == data.count
            // BFINAL in the low bit, BTYPE 00 (stored) above it.
            output.append(isLast ? 0x01 : 0x00)
            output.append(UInt8(length & 0xFF))
            output.append(UInt8(length >> 8))
            let complement = (~UInt32(length)) & 0xFFFF
            output.append(UInt8(complement & 0xFF))
            output.append(UInt8(complement >> 8))
            if length > 0 {
                output.append(contentsOf: data[offset..<offset + length])
            }
            offset += length
            if isLast {
                break
            }
        }

        output.append(contentsOf: littleEndian(crc32(data)))
        output.append(contentsOf: littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return output
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }

    private static func crc32(_ data: Data) -> UInt32 {
        let table: [UInt32] = (0..<256).map { value in
            var code = UInt32(value)
            for _ in 0..<8 {
                code = (code & 1 != 0) ? (0xEDB8_8320 ^ (code >> 1)) : (code >> 1)
            }
            return code
        }

        var crc = UInt32(0xFFFF_FFFF)
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
