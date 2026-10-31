// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`findIconURLsFromHTMLDocument`)
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The `link` elements a document offers as the feed icon, in document order.
///
/// The bytes are read through the charset layer, which answers unchanged for a document that is
/// already valid UTF-8, and then through the same HTML subset the sanitizer uses, so the scan
/// sees what the reference's `goquery` document sees: a `link` inside a raw-text element is
/// text, not an element, and a self-closing element in foreign content is an element. The
/// reference resolves each href against the document URL and skips the one its parse cannot
/// read, which is the case this scan answers by continuing rather than by failing the document.
enum IconDocumentLinks {
    /// The icon hrefs the document offers, in the order the tokens arrive.
    static func iconURLs(document: Data, contentType: String?, documentURL: String) -> [String] {
        let decoded = String(decoding: FeedCharset.decode(document, contentType: contentType),
            as: UTF8.self)
        let tokenizer = HTMLTokenizer(decoded)
        var urls: [String] = []

        while let token = tokenizer.next() {
            guard token.kind == .startTag || token.kind == .selfClosingStartTag,
                token.name == "link" else {
                continue
            }
            guard let rel = attribute("rel", in: token), IconLinkRules.isIconLink(rel: rel) else {
                continue
            }
            guard let href = attribute("href", in: token), !UnicodeSpace.trim(href).isEmpty else {
                continue
            }

            let value = UnicodeSpace.trim(href)
            guard let absolute = try? URLResolution.resolveToAbsolute(base: documentURL,
                relative: value) else {
                continue
            }
            urls.append(absolute)
        }

        return urls
    }

    /// The value of an attribute, or `nil` when the element does not have it — the selector
    /// branch that asks for `[href]` is a test for the attribute being present.
    private static func attribute(_ name: String, in token: HTMLToken) -> String? {
        token.attributes.first { $0.name == name }?.value
    }
}
