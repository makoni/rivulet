import Foundation

/// Byte-level decoding of ``CharsetEncoding`` values into UTF-8.
///
/// Ported from the decoders the reference reaches through `golang.org/x/text`, which are all
/// lossy: bytes and sequences that cannot be decoded become U+FFFD instead of failing the
/// document. Every primitive below keeps that property, because a feed with a few corrupt
/// bytes should still parse.
enum CharsetDecoder {
    /// Decodes `data` with `strategy` and returns UTF-8 bytes.
    static func decode(_ data: Data, using strategy: CharsetDecoderStrategy, canonicalName: String) -> Data {
        switch strategy {
        case .identity:
            return data
        case .singleByte(let encoding):
            return Data(decodeSingleByte(data, encoding: encoding).utf8)
        case .multiByte(let encoding):
            return Data(decodeMultiByte(data, encoding: encoding, canonicalName: canonicalName).utf8)
        case .utf16LittleEndian:
            return Data(decodeUTF16(data, littleEndian: true).utf8)
        case .utf16BigEndian:
            return Data(decodeUTF16(data, littleEndian: false).utf8)
        case .userDefined:
            return Data(decodeUserDefined(data).utf8)
        case .replacement:
            // The reference replacement decoder emits one U+FFFD for a non-empty document.
            return data.isEmpty ? Data() : Data("\u{FFFD}".utf8)
        }
    }

    /// Decodes a single-byte encoding byte by byte.
    ///
    /// The platform converter doubles as the WHATWG index: a byte it cannot decode is exactly
    /// a byte the WHATWG index leaves undefined, and both become U+FFFD.
    private static func decodeSingleByte(_ data: Data, encoding: String.Encoding) -> String {
        let table: [Unicode.Scalar?] = (0...255).map { byte in
            let decoded = String(data: Data([UInt8(byte)]), encoding: encoding)
            guard let decoded, decoded.unicodeScalars.count == 1 else { return nil }
            return decoded.unicodeScalars.first
        }
        var scalars = String.UnicodeScalarView()
        for byte in data {
            scalars.append(table[Int(byte)] ?? "\u{FFFD}")
        }
        return String(scalars)
    }

    /// Decodes a multi-byte encoding, falling back to the platform `iconv` and finally to a
    /// windowed rescan for encodings the platform cannot decode at all.
    private static func decodeMultiByte(_ data: Data, encoding: String.Encoding, canonicalName: String) -> String {
        if let text = String(data: data, encoding: encoding) {
            return text
        }
        #if canImport(Glibc)
        if let text = IconvDecoder.decode(data, from: canonicalName) {
            return text
        }
        #endif
        return decodeLeniently(data, encoding: encoding)
    }

    /// Decodes as much of `data` as the platform converter accepts, replacing every byte it
    /// rejects with U+FFFD.
    ///
    /// This is a last resort for platforms without `iconv`: it rescans the data in windows of
    /// up to four bytes, so stateful encodings (ISO-2022-JP) can decode incorrectly after a
    /// rejected escape. On Linux the `iconv` path handles these inputs instead.
    private static func decodeLeniently(_ data: Data, encoding: String.Encoding) -> String {
        var result = ""
        var start = data.startIndex
        while start < data.endIndex {
            let remaining = data.count - data.distance(from: data.startIndex, to: start)
            var matched = false
            for length in stride(from: min(4, remaining), through: 1, by: -1) {
                let end = data.index(start, offsetBy: length)
                if let text = String(data: data[start..<end], encoding: encoding) {
                    result += text
                    start = end
                    matched = true
                    break
                }
            }
            if !matched {
                result += "\u{FFFD}"
                start = data.index(after: start)
            }
        }
        return result
    }

    /// Decodes UTF-16 by hand, so that the platform can neither drop nor normalize a BOM.
    ///
    /// The reference decodes UTF-16 with its `IgnoreBOM` policy, which keeps a leading BOM in
    /// the output; an odd trailing byte or a lone surrogate becomes U+FFFD.
    private static func decodeUTF16(_ data: Data, littleEndian: Bool) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(data.count / 2)
        var index = data.startIndex
        while index < data.endIndex {
            let next = data.index(after: index)
            guard next < data.endIndex else {
                units.append(0xFFFD)
                break
            }
            let first = UInt16(data[index])
            let second = UInt16(data[next])
            units.append(littleEndian ? first | (second << 8) : (first << 8) | second)
            index = data.index(after: next)
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Decodes the WHATWG `x-user-defined` encoding: bytes 0x80-0xFF map to U+F780-U+F7FF.
    private static func decodeUserDefined(_ data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in data {
            if byte < 0x80 {
                scalars.append(Unicode.Scalar(byte))
            } else {
                // 0xF780...0xF7FF is a valid scalar range, so the failable initializer cannot
                // fail here.
                scalars.append(Unicode.Scalar(0xF780 + UInt32(byte) - 0x80)!)
            }
        }
        return String(scalars)
    }
}
