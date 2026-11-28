// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer, which reads through golang.org/x/net/html
// (`parse.go`) (Apache-2.0 / BSD-3-Clause); adapted for Swift/SQLite.

/// The tag sets the insertion-mode rules of ``HTMLFragmentTree`` read.
extension HTMLFragmentTree {
    /// The start tags that close an open `p`: the list `inBodyIM` pops `buttonScope, p` for, plus
    /// the tags that have their own case and pop `p` first (`hr`, `li`, `dd`, `dt`, `listing`,
    /// `plaintext`, `xmp`). `button` is not in the list, which is why it is not the HTML5 block
    /// set, and `table` is not in it either: its own case pops `p` only when the parser is not in
    /// quirks mode, and `p.quirks` is always true on the reference's path, because `initialIM`
    /// answers with the input wrapped in `<body>` and no doctype is read before it.
    static let pClosingTags: Set<String> = [
        "address", "article", "aside", "blockquote", "center", "dd", "details", "dialog", "dir", "div",
        "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "header", "h1", "h2", "h3",
        "h4", "h5", "h6", "hgroup", "hr", "li", "listing", "main", "menu", "nav", "ol", "p", "plaintext",
        "pre", "search", "section", "summary", "ul", "xmp",
    ]

    /// The tags the reference pops from the open stack as soon as it inserts them.
    static let voidTags: Set<String> = [
        "area", "base", "basefont", "bgsound", "br", "col", "embed", "frame", "hr", "img", "input",
        "keygen", "link", "meta", "param", "source", "track", "wbr",
    ]

    /// The table-only tags: outside a table they are not elements at all. Only `table`, `caption`,
    /// `thead`, `tfoot`, `tr`, `th` and `td` are in the sanitizer allowlist, so an implied `tbody`
    /// is invisible in the output even though it is on the tree.
    static let tableOnlyTags: Set<String> = [
        "caption", "col", "colgroup", "frame", "head", "tbody", "td", "tfoot", "th", "thead", "tr",
    ]

    /// The elements `isSpecialElement` answers true for. The end tag that is not in the block list
    /// walks the stack and stops at the first of these, which is a different set from
    /// `defaultScopeStopTags`: the stop list has `applet`, `caption`, `html`, `table`, `td`, `th`,
    /// `marquee`, `object`, `template` and `select`, while the special list also has `p`, `div`,
    /// `li`, `button`, `pre` and the other block tags. `ol` and `ul` are only in the special list;
    /// they are `listItemScope`'s own stop tags, not default ones.
    static let specialElements: Set<String> = [
        "address", "applet", "area", "article", "aside", "base", "basefont", "bgsound", "blockquote",
        "body", "br", "button", "caption", "center", "col", "colgroup", "dd", "details", "dir", "div",
        "dl", "dt", "embed", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset",
        "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html", "iframe", "img",
        "input", "keygen", "li", "link", "listing", "main", "marquee", "menu", "meta", "nav",
        "noembed", "noframes", "noscript", "object", "ol", "p", "param", "plaintext", "pre", "script",
        "section", "select", "source", "style", "summary", "table", "tbody", "td", "template",
        "textarea", "tfoot", "th", "thead", "title", "tr", "track", "ul", "wbr", "xmp",
    ]

    /// The end tags `inBodyIM` answers with `popUntil(defaultScope, ...)`: the block list, the own
    /// cases for `dd`, `dt` and the six headings, and the three that clear the formatting list,
    /// which is not ported. `p`, `li` and `br` have their own rules, and everything else uses the
    /// special-element walk, which stops at the first special element. A void element is not in the
    /// list, because it is popped as soon as it is inserted.
    static let endTagsInDefaultScope: Set<String> = [
        "address", "article", "aside", "blockquote", "button", "center", "dd", "details", "dialog",
        "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "header", "h1", "h2",
        "h3", "h4", "h5", "h6", "hgroup", "listing", "main", "menu", "nav", "ol", "pre", "search",
        "section", "select", "summary", "ul", "applet", "marquee", "object",
    ]

    /// The names `inCellIM` handles before it falls through: it closes the open cell and reads the
    /// token again in the row mode.
    static let cellStartTags: Set<String> = [
        "caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr",
    ]

    /// The names `inCaptionIM` handles before it falls through: it closes the open caption and
    /// reads the token again in the table mode. This is the cell list without `th`, and both
    /// sides of it are pinned: `th` pins a name the list does not have, and `tr` pins one it
    /// has, because a name in the list moves the token after it out of the caption.
    static let captionStartTags: Set<String> = [
        "caption", "col", "colgroup", "tbody", "td", "tfoot", "thead", "tr",
    ]

    /// The names `inBodyIM` answers with `addFormattingElement`, which is the one place the
    /// reference reorders the attributes it puts on a node: by name, then by value for a tie. The
    /// port has no namespace, which is the first key `attrCompare` reads, so the name and the value
    /// are the whole comparison. `a` is the only one of them with attributes in the sanitizer's
    /// allowlist, so that is where the order shows in the output.
    static let formattingElementTags: Set<String> = [
        "a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u",
    ]

    /// The stop tags `defaultScopeStopTags` holds for the HTML namespace.
    static let defaultScopeStopTags: Set<String> = [
        "applet", "caption", "html", "table", "td", "th", "marquee", "object", "template", "select",
    ]
}
