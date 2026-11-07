import Foundation

/// Writes a gzip stream for the stub feed server, so a fetch test can hand the client a compressed
/// body without adding a compression dependency.
///
/// The body a test declares is written as stored DEFLATE blocks — gzip allows an uncompressed block
/// — which keeps the encoder small. A stored block cannot reach a compression ratio above 1, so a
/// test that needs a body inflating far past the stream it is stored in uses the fixed-Huffman
/// block
/// writer below, which is the only shape that can.
///
/// The output is a valid gzip stream; it is checked against `gunzip` by hand when this encoder
/// changes, because there is no decoder in the suite that could prove it. The fetch test therefore
/// shows that the client reads a fixture built by this encoder, not that the encoder is correct —
/// `docs/testing.md` says the same.
enum GzipStream {
    /// Writes the stream for `data` as stored blocks, so the stream is never smaller than the body.
    static func compress(_ data: Data) -> Data {
        var output = header()

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

        return finish(output, body: data)
    }

    /// Writes the stream for a body that inflates to `1 + 258 * matchCount` bytes of `A`: one
    /// literal, then `matchCount` matches of the longest length at distance 1, which is the shape
    /// that keeps the stream small while the body it answers is large. The stream is about
    /// `13 + 13 * matchCount / 8` bytes, so the ratio it reaches is the body over the stream.
    static func inflating(matchCount: Int) -> Data {
        var writer = BitWriter()
        writer.write(1, bits: 1)              // BFINAL
        writer.write(1, bits: 2)              // BTYPE 01, read from the low bit
        writer.writeCode(literalCode, bits: 8)
        for _ in 0..<matchCount {
            writer.writeCode(lengthCode, bits: 8)
            writer.writeCode(distanceCode, bits: 5)
        }
        writer.writeCode(endOfBlockCode, bits: 7)

        let body = Data(repeating: 0x41, count: 1 + 258 * matchCount)
        var output = header()
        output.append(contentsOf: writer.finish())
        return finish(output, body: body)
    }

    // The canonical codes the fixed table of RFC 1951 gives these symbols, written from the most
    // significant bit: literal `A` (symbol 65, 8 bits), length 258 (symbol 285, 8 bits), distance 1
    // (symbol 0, 5 bits) and the end of the block (symbol 256, 7 bits).
    private static let literalCode = 113
    private static let lengthCode = 197
    private static let distanceCode = 0
    private static let endOfBlockCode = 0

    private static func header() -> Data {
        Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
    }

    private static func finish(_ output: Data, body: Data) -> Data {
        var stream = output
        stream.append(contentsOf: littleEndian(crc32(body)))
        stream.append(contentsOf: littleEndian(UInt32(truncatingIfNeeded: body.count)))
        return stream
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

    /// The bits of a DEFLATE block. Extra bits and the block header are written from the least
    /// significant bit; a canonical code is written from the most significant bit of the code,
    /// which
    /// is why the writer takes them through two paths.
    private struct BitWriter {
        private var pending = 0
        private var count = 0
        private var bytes: [UInt8] = []

        mutating func write(_ value: Int, bits: Int) {
            for index in 0..<bits {
                push((value >> index) & 1)
            }
        }

        mutating func writeCode(_ code: Int, bits: Int) {
            for index in stride(from: bits - 1, through: 0, by: -1) {
                push((code >> index) & 1)
            }
        }

        mutating func finish() -> [UInt8] {
            if count > 0 {
                bytes.append(UInt8(pending))
            }
            return bytes
        }

        private mutating func push(_ bit: Int) {
            pending |= bit << count
            count += 1
            if count == 8 {
                bytes.append(UInt8(pending))
                pending = 0
                count = 0
            }
        }
    }
}
