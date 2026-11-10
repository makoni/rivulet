// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/opml (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// What the OPML read answers when the document is not the document the model names.
///
/// The reference's wording around these is its own (`opml: unable to parse document`,
/// `opml: invalid miniflux attribute %q`); this port names the shape, the attribute and the rule,
/// and the command that reports them writes the rule name, as the write handlers of this port write
/// it.
enum OPMLError: Error, Equatable, Sendable {
    /// A root the model does not name. The reference reports the mismatch even with `Strict =
    /// false`, which `docs/reference-notes.md` records with the rule.
    case rootShape(rootLocal: String)

    /// A document the tolerant read itself cannot read, handed through as the reader answers it.
    case documentNotReadable(XMLError)

    /// A miniflux bool attribute whose value is outside the set the parse rule accepts; the error
    /// names the attribute the rule was reading.
    case invalidMinifluxAttribute(name: String)

    /// A subscription the validation rules fail on, named with the rule and the url as the record
    /// holds it, which is what the reference's `opml: invalid feed settings for %q` names.
    case invalidFeedSettings(rule: FeedValidationRule, feedURL: String)
}
