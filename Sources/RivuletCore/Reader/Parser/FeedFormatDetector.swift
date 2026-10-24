// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/parser/format.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// Feed-format detection, ported from the reference's `DetectFeedFormat`.
///
/// JSON is decided by the first character that is not whitespace, before any XML token is read. The
/// XML path reads through the same reader the parser uses, so the charset rule applies to it, and a
/// failure ends the scan rather than failing the call: the reference ignores the error and breaks,
/// so the answer is `unknown`. Roots are matched on their local name alone, which is why `rdf:RDF`
/// is a root with the local name `RDF`.
enum FeedFormatDetector {
    private static let maxTokensToConsider = 50

    static func detect(_ data: Data) -> DetectedFormat {
        if isJSON(data) { return DetectedFormat(format: .json, version: nil) }

        // A document that cannot be prepared cannot be tokenized either, and the reference reports
        // no failure here, so the answer stays `unknown`.
        guard let bytes = try? XMLReader.prepared(data) else { return DetectedFormat(format: .unknown) }
        let tokenizer = XMLTokenizer(bytes)

        var processedTokens = 0
        while processedTokens < Self.maxTokensToConsider {
            guard let token = try? tokenizer.nextToken() else { break }
            processedTokens += 1
            guard case .startElement(let name, let attributes) = token else { continue }
            switch name.local {
            case "rss": return DetectedFormat(format: .rss)
            case "feed": return DetectedFormat(format: .atom, version: atomVersion(attributes))
            case "RDF": return DetectedFormat(format: .rdf)
            default: continue
            }
        }
        return DetectedFormat(format: .unknown)
    }

    /// Port of `detectJSONFormat`: the first character that is not whitespace decides, and the end
    /// of the document without one does not. Go reads the buffer as runes, so the two bytes above
    /// ASCII that are whitespace — U+0085 and U+00A0 — count here too, while other bytes above
    /// ASCII do not.
    private static func isJSON(_ data: Data) -> Bool {
        for byte in data where !isWhitespace(byte) {
            return byte == UInt8(ascii: "{")
        }
        return false
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        if byte >= 0x80 { return byte == 0x85 || byte == 0xA0 }
        return Character(Unicode.Scalar(byte)).isWhitespace
    }

    /// The Atom version the reference reports for an Atom root: `0.3` when its `version` attribute
    /// says so, otherwise `1.0`.
    private static func atomVersion(_ attributes: [XMLAttribute]) -> String {
        for attribute in attributes where attribute.name.local == "version" && attribute.value == "0.3" {
            return "0.3"
        }
        return "1.0"
    }
}
