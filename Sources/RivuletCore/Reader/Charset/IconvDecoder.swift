#if canImport(Glibc)
import Foundation
import Glibc

/// Lossy decoding through the platform `iconv`.
///
/// Foundation on Linux cannot decode some legacy encodings at all — EUC-JP returns `nil` for
/// every input — while the reference decodes them through `golang.org/x/text`. `iconv` ships
/// with the platform on Linux, so it fills that gap; bytes it rejects become U+FFFD, which
/// keeps a document with a few corrupt bytes decodable.
enum IconvDecoder {
    /// Decodes `data` from the IANA name `name` to a string.
    ///
    /// - Returns: `nil` when the platform has no converter for `name`. A converter that
    ///   exists always produces a string, because every rejected byte is replaced.
    static func decode(_ data: Data, from name: String) -> String? {
        guard let handle = name.withCString({ iconv_open("UTF-8", $0) }),
              handle != UnsafeMutableRawPointer(bitPattern: -1) else {
            return nil
        }
        defer { iconv_close(handle) }
        guard !data.isEmpty else { return "" }

        let input = UnsafeMutablePointer<CChar>.allocate(capacity: data.count)
        defer { input.deallocate() }
        for (offset, byte) in data.enumerated() {
            input[offset] = CChar(bitPattern: byte)
        }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        let replacement = Array("\u{FFFD}".utf8)
        var output = [UInt8]()
        output.reserveCapacity(data.count)

        var source: UnsafeMutablePointer<CChar>? = input
        var sourceLeft = data.count
        while sourceLeft > 0 {
            let sourceLeftBefore = sourceLeft
            var destination: UnsafeMutablePointer<CChar>? = buffer
            var destinationLeft = bufferSize
            let result = iconv(handle, &source, &sourceLeft, &destination, &destinationLeft)
            output.append(contentsOf: UnsafeBufferPointer(start: buffer, count: bufferSize - destinationLeft).map {
                UInt8(bitPattern: $0)
            })
            if result == -1 {
                switch errno {
                case EILSEQ:
                    // An invalid sequence: drop one byte, exactly like a lossy decoder.
                    output.append(contentsOf: replacement)
                    source = source?.advanced(by: 1)
                    sourceLeft -= 1
                case EINVAL:
                    // An incomplete sequence at the end of the input.
                    output.append(contentsOf: replacement)
                    sourceLeft = 0
                case E2BIG:
                    // The output buffer is full; the next iteration flushes it.
                    continue
                default:
                    return nil
                }
            } else if sourceLeft == sourceLeftBefore {
                // No progress: refuse to spin instead of trusting the converter.
                return nil
            }
        }
        return String(decoding: output, as: UTF8.self)
    }
}
#endif
