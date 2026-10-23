// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/encoding/encoding.go (Apache-2.0); adapted for
// Swift/SQLite, because the reference reaches these encodings through golang.org/x/text.

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
        return convert(data, from: input, handle: handle)
    }

    /// Runs the converter until it has consumed everything, replacing what it rejects.
    ///
    /// `iconv` reports one error per stop rather than per maximal subpart, so a corrupt span can
    /// yield a different number of U+FFFD than the reference; that is the recorded platform
    /// difference in `docs/parity.md`, and valid text is unaffected.
    private static func convert(
        _ data: Data,
        from input: UnsafeMutablePointer<CChar>,
        handle: UnsafeMutableRawPointer
    ) -> String? {
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        let replacement = Array("\u{FFFD}".utf8)
        var output = [UInt8]()
        output.reserveCapacity(data.count)

        var source: UnsafeMutablePointer<CChar>? = input
        var sourceLeft = data.count

        while sourceLeft > 0 {
            let consumedBefore = sourceLeft
            // The window the converter can write into during this call, from the buffer start.
            var destination: UnsafeMutablePointer<CChar>? = buffer
            var destinationLeft = bufferSize
            let result = iconv(handle, &source, &sourceLeft, &destination, &destinationLeft)
            flush(buffer, into: &output, count: bufferSize - destinationLeft)
            if result != -1 {
                break
            }
            switch errno {
            case EILSEQ:
                // An invalid sequence: replace the byte `iconv` stopped at, then step over it,
                // because glibc does not advance the input pointer on this error.
                output.append(contentsOf: replacement)
                source = source?.advanced(by: 1)
                sourceLeft -= 1
            case EINVAL:
                // An incomplete sequence at the end of the input.
                output.append(contentsOf: replacement)
                sourceLeft = 0
            case E2BIG:
                // The output buffer is full: the flush above took it and the next call refills it.
                break
            default:
                return nil
            }
            if sourceLeft == consumedBefore {
                // No progress: refuse to spin instead of trusting the converter.
                return nil
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func flush(
        _ buffer: UnsafeMutablePointer<CChar>,
        into output: inout [UInt8],
        count: Int
    ) {
        guard count > 0 else { return }
        output.append(contentsOf: UnsafeBufferPointer(start: buffer, count: count)
            .map { UInt8(bitPattern: $0) })
    }
}
#endif
