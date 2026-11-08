// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/subscription/finder.go (`findSubscriptionsFromWebPage`)
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The bytes go through the charset layer, which answers unchanged for a document that is already
/// valid UTF-8, and then through the same HTML subset the sanitizer uses, so the scan sees what the
/// reference's `goquery` document sees for the cases here: a `link` inside a raw-text element is
/// text, not an element. The scan reads tokens rather than a tree, so a token is matched whatever
/// the tree would do with it — outside foreign content the reference's tree does not acknowledge
/// the self-closing flag, and `link` is a void element, so the pins assert the scan accepts that
/// token kind. The reference resolves each href against the URL it reached, which after its
/// canonical step may be another URL; here the scan is given the base, and a value the parse cannot
/// read is skipped rather than failing the document. The set is keyed by the resolved value, so two
/// spellings that resolve to one value answer once, and the value is the first one the scan read.
enum SubscriptionDocumentLinks {
    /// The feed hrefs the document offers, in the order the tokens arrive.
    static func feedURLs(document: Data, contentType: String?, documentURL: String) -> [String] {
        let decoded = String(decoding: FeedCharset.decode(document, contentType: contentType),
            as: UTF8.self)
        let tokenizer = HTMLTokenizer(decoded)
        var read: Set<String> = []
        var urls: [String] = []

        while let token = tokenizer.next() {
            guard token.kind == .startTag || token.kind == .selfClosingStartTag,
                token.name == "link" else {
                continue
            }

            // The selector asks for the `type` attribute to be there, which a link with only a
            // relation is not; the two tests are the rules in `SubscriptionLinkRules`.
            guard let type = attribute("type", in: token),
                SubscriptionLinkRules.isAlternateLink(rel: attribute("rel", in: token) ?? ""),
                SubscriptionLinkRules.format(forType: type,
                    href: attribute("href", in: token) ?? "") != nil else {
                continue
            }

            // Without a value there is no subscription, and the value is the attribute as the
            // document holds it — not trimmed, which is what the reference compares too.
            guard let href = attribute("href", in: token), !href.isEmpty else { continue }

            guard let absolute = try? URLResolution.resolveToAbsolute(base: documentURL,
                relative: href) else {
                continue
            }
            if read.contains(absolute) { continue }
            read.insert(absolute)
            urls.append(absolute)
        }

        return urls
    }

    /// The value of an attribute, or `nil` when the element does not have it — the selector branch
    /// that asks for `[type]` is a test for the attribute being present.
    private static func attribute(_ name: String, in token: HTMLToken) -> String? {
        token.attributes.first { $0.name == name }?.value
    }
}
