// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer, which reads through golang.org/x/net/html
// (`parse.go`) (Apache-2.0 / BSD-3-Clause); adapted for Swift/SQLite.

import Foundation

/// The fragment tree the sanitizer renders, the insertion-mode rules `inBodyIM` and `inTableIM`
/// build.
///
/// The port covers the rules the sanitizer can see: the tags that close an open `p`, the void tags
/// popped as soon as they are inserted, the table-only tags that are not elements outside a table,
/// the implied `tbody` and `tr` inside one, the end tags that pop the table modes, the end tags
/// that walk the stack and stop at the first special element, the two end-tag rules that put a node
/// on the tree with nothing in it, and the depth limit the reference refuses.
///
/// Where the subset stops, recorded in `docs/parity.md`: foster parenting, the active formatting
/// elements, the adoption agency, the caption and column-group modes, nested tables, the scope
/// markers, the ancestor loops the start tags run for `li`, `dd` and `dt`, the raw-text
/// leading-newline mode and the foreign-content self-closing pop. None of them changes what the
/// sanitizer writes for a case in the reference corpus, but a real feed can nest content
/// differently here, so the tree is built as if the insertion point were the open element, which is
/// what the modes answer with for the tags in the corpus.
///
/// Comment nodes are not kept, because the renderer answers with nothing for them.
final class HTMLFragmentTree {
    /// The open-element limit `insertOpenElement` enforces, reported as a parse failure once the
    /// stack passes it. `html` and `body` count in the stack, which is what the reference's depth
    /// test pins.
    static let maxOpenElements = 512

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

    struct Failure: Error, Equatable {}

    /// The insertion modes the table rules switch between. `head`, `caption` and the column-group
    /// mode are not modelled; the boundary is the paragraph above.
    private enum Mode {
        case body, table, tableBody, row, cell
    }

    /// The three table scopes `clearStackToContext` answers for. Each scope is cut to its anchor
    /// element.
    private enum Scope {
        case table, tableBody, tableRow
    }

    private let tokenizer: HTMLTokenizer
    private let root = HTMLNode(kind: .document)
    private var open: [HTMLNode] = []
    private var mode = Mode.body

    init(_ tokenizer: HTMLTokenizer) {
        self.tokenizer = tokenizer
    }

    /// Builds the tree and answers with the `body` element the sanitizer renders, which is the node
    /// the reference walks through.
    func build() throws -> HTMLNode {
        let html = try insertElement(name: "html", attributes: [])
        html.appendChild(HTMLNode(kind: .element, name: "head"))

        while let token = tokenizer.next() {
            try process(token)
        }

        guard let body = html.children.first(where: { $0.kind == .element && $0.name == "body" }) else {
            throw Failure()
        }
        return body
    }

    private func process(_ token: HTMLToken) throws {
        switch token.kind {
        case .text:
            addText(token.data)
        case .comment:
            break
        case .endTag:
            try processEndTag(token.name)
        case .startTag, .selfClosingStartTag:
            try processStartTag(token)
        }
    }

    // MARK: - Insertion modes

    private func processStartTag(_ token: HTMLToken) throws {
        let name = token.name

        // `html` and `head` do not put a node on the tree here; the reference adds them before the
        // input is read, and a second one is ignored.
        if name == "html" || name == "head" { return }
        if name == "body" {
            guard elementNamed("body") == nil else { return }
            try insertElement(name: name, attributes: token.attributes)
            return
        }

        if mode == .body {
            try processStartTagInBody(name, attributes: token.attributes)
        } else {
            try processStartTagInTable(name, attributes: token.attributes)
        }
    }

    private func processStartTagInBody(_ name: String, attributes: [HTMLAttribute]) throws {
        if name == "table" {
            try insertElement(name: name, attributes: attributes)
            mode = .table
            return
        }
        if HTMLFragmentTree.tableOnlyTags.contains(name) { return }

        if name == "button" {
            // `case a.Button` closes an open `button` that is in the default scope, and it is the
            // one block-list case that does not pop an open `p`.
            popUntil(.defaultScope, "button")
            try insertElement(name: name, attributes: attributes)
            return
        }

        if HTMLFragmentTree.pClosingTags.contains(name) { popUntil(.buttonScope, "p") }
        try insertElement(name: name, attributes: attributes)
        if HTMLFragmentTree.voidTags.contains(name) { open.removeLast() }
    }

    /// The same token read again in the mode the implied element switched to, which is what
    /// `parseImpliedToken` does: the cell rules in the table mode imply a `tbody`, and the cell
    /// rules in the table-body mode imply a `tr`.
    private func processStartTagInTable(_ name: String, attributes: [HTMLAttribute]) throws {
        switch mode {
        case .body: try insertAtInsertionPoint(name, attributes: attributes)
        case .table: try startTagInTableMode(name, attributes: attributes)
        case .tableBody: try startTagInTableBodyMode(name, attributes: attributes)
        case .row: try startTagInRowMode(name, attributes: attributes)
        case .cell:
            // The cell closes for the names in its own list and the token is read again in the row
            // mode. Anything else is processed by the rules for the body, where the insertion point
            // is the cell itself, because a cell is a special element.
            if Self.cellStartTags.contains(name) {
                open.removeLast()
                mode = .row
                try processStartTagInTable(name, attributes: attributes)
                return
            }
            try insertAtInsertionPoint(name, attributes: attributes)
        }
    }

    private func startTagInTableMode(_ name: String, attributes: [HTMLAttribute]) throws {
        switch name {
        case "caption", "col", "colgroup":
            cut(to: .table)
            try insertAtInsertionPoint(name, attributes: attributes)
        case "tbody", "thead", "tfoot":
            cut(to: .table)
            try insertElement(name: name, attributes: attributes)
            mode = .tableBody
        case "td", "th", "tr":
            try insertImplied(name: "tbody", scope: .table, modeAfter: .tableBody)
            try processStartTagInTable(name, attributes: attributes)
        default:
            try insertAtInsertionPoint(name, attributes: attributes)
        }
    }

    private func startTagInTableBodyMode(_ name: String, attributes: [HTMLAttribute]) throws {
        switch name {
        case "tr":
            cut(to: .tableBody)
            try insertElement(name: name, attributes: attributes)
            mode = .row
        case "td", "th":
            try insertImplied(name: "tr", scope: .tableBody, modeAfter: .row)
            try processStartTagInTable(name, attributes: attributes)
        case "caption", "col", "colgroup", "tbody", "tfoot", "thead":
            // The open body is popped only when one of the three is open, and the token is then
            // read again in the table mode.
            guard let position = indexOfTableBody() else { return }
            open.removeSubrange(position...)
            mode = .table
            try processStartTagInTable(name, attributes: attributes)
        default:
            try insertAtInsertionPoint(name, attributes: attributes)
        }
    }

    private func startTagInRowMode(_ name: String, attributes: [HTMLAttribute]) throws {
        switch name {
        case "td", "th":
            cut(to: .tableRow)
            try insertElement(name: name, attributes: attributes)
            mode = .cell
        case "caption", "col", "colgroup", "tbody", "tfoot", "thead", "tr":
            guard elementNamed("tr") != nil else { return }
            open.removeLast()
            mode = .tableBody
            try processStartTagInTable(name, attributes: attributes)
        default:
            try insertAtInsertionPoint(name, attributes: attributes)
        }
    }

    private func insertAtInsertionPoint(_ name: String, attributes: [HTMLAttribute]) throws {
        try insertElement(name: name, attributes: attributes)
        if HTMLFragmentTree.voidTags.contains(name) { open.removeLast() }
    }

    private func processEndTag(_ name: String) throws {
        // `body` does not pop anything, only the insertion mode changes, and `html` is read as
        // `</body>`, which leaves the body open. Both are ignored inside a table.
        if mode == .body {
            if name == "body" || name == "html" { return }
        } else {
            if name == "html" || name == "body" { return }
            // Each table mode has its own list of end tags. A name outside it is processed by the
            // rules for the body, at the insertion point, which is the open table element.
            if processEndTagInTable(name) { return }
        }

        if name == "p" {
            // An end tag for `p` inserts an empty one when the open `p` is not in `buttonScope`,
            // then closes the one that is in the scope.
            if indexOfElementInScope(.buttonScope, "p") == nil {
                try insertElement(name: "p", attributes: [])
            }
            popUntil(.buttonScope, "p")
            return
        }

        // The end tag for br is read as a start tag.
        if name == "br" {
            try processStartTag(HTMLToken(kind: .startTag, name: "br"))
            return
        }

        if name == "li" {
            popUntil(.listItemScope, "li")
            return
        }

        if Self.endTagsInDefaultScope.contains(name) {
            popUntil(.defaultScope, name)
            return
        }

        popOtherEndTag(name)
    }

    /// `inBodyEndTagOther`: the walk stops at the match or at the first special element, which is a
    /// different set from the default-scope stop tags.
    private func popOtherEndTag(_ name: String) {
        for index in open.indices.reversed() {
            if open[index].name == name {
                open.removeSubrange(index...)
                return
            }
            if Self.specialElements.contains(open[index].name) { return }
        }
    }

    /// The end tags each table mode answers for, and the ones it ignores. A name in neither list is
    /// processed by the rules for the body.
    private func processEndTagInTable(_ name: String) -> Bool {
        if ignoredEndTag(name) { return true }
        guard name == "table" || HTMLFragmentTree.tableOnlyTags.contains(name) else { return false }
        guard let position = indexOfOpenElement(name) else { return true }
        open.removeSubrange(position...)

        switch name {
        case "table": mode = .body
        case "tbody", "thead", "tfoot": mode = .table
        case "tr": mode = .tableBody
        case "td", "th": mode = .row
        default: break
        }
        return true
    }

    /// The names the current table mode ignores, which are the ones its own switch lists.
    private func ignoredEndTag(_ name: String) -> Bool {
        switch mode {
        case .table:
            return ["caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr"]
                .contains(name)
        case .tableBody:
            return ["caption", "col", "colgroup", "td", "th", "tr"].contains(name)
        case .row:
            return ["caption", "col", "colgroup", "td", "th"].contains(name)
        case .cell:
            return ["caption", "col", "colgroup"].contains(name)
        case .body:
            return false
        }
    }

    // MARK: - Nodes

    @discardableResult
    private func insertElement(name: String, attributes: [HTMLAttribute]) throws -> HTMLNode {
        let node = HTMLNode(kind: .element, name: name)
        node.attributes = attributes
        (open.last ?? root).appendChild(node)
        open.append(node)
        if open.count > Self.maxOpenElements { throw Failure() }
        return node
    }

    private func addText(_ value: String) {
        let parent = open.last ?? root

        // The leading-newline rule reads the token data as it was read, before the NUL is removed,
        // so a block that starts with a NUL keeps its newline. NUL is removed after the check,
        // which is the one place the reference does not read it as U+FFFD.
        var data = value
        if (parent.name == "pre" || parent.name == "listing") && parent.firstChild == nil {
            if data.hasPrefix("\r") { data = String(data.dropFirst()) }
            if data.hasPrefix("\n") { data = String(data.dropFirst()) }
        }

        let cleaned = data.replacingOccurrences(of: "\u{00}", with: "")
        if cleaned.isEmpty { return }

        let node = HTMLNode(kind: .text)
        node.text = cleaned
        parent.appendChild(node)
    }

    // MARK: - Stack rules

    private func insertImplied(name: String, scope: Scope, modeAfter newMode: Mode) throws {
        cut(to: scope)
        try insertElement(name: name, attributes: [])
        mode = newMode
    }

    /// `clearStackToContext`: the stack is cut to the anchor of the scope. The reference also
    /// anchors on `html` and the markers, which cannot be reached from inside a table.
    private func cut(to scope: Scope) {
        let anchors: [String]
        switch scope {
        case .table: anchors = ["table"]
        case .tableBody: anchors = ["tbody", "thead", "tfoot"]
        case .tableRow: anchors = ["tr"]
        }
        guard let position = open.lastIndex(where: { anchors.contains($0.name) }) else { return }
        open.removeSubrange((position + 1)...)
    }

    /// `popUntil(scope, name)`: the stack is cut to the element only when it is in the scope, which
    /// is what `indexOfElementInScope` answers with.
    private func popUntil(_ scope: ElementScope, _ name: String) {
        guard let position = indexOfElementInScope(scope, name) else { return }
        open.removeSubrange(position...)
    }

    /// `indexOfElementInScope`: the walk from the top stops at the scope's own stop tags, and at
    /// the shared `defaultScopeStopTags`, whatever the scope. An element that is both a match and a
    /// stop tag is found first, because the match is checked before the stop tags.
    private func indexOfElementInScope(_ scope: ElementScope, _ name: String) -> Int? {
        for index in open.indices.reversed() {
            let element = open[index].name
            if element == name { return index }
            if scope.ownStopTags.contains(element) { return nil }
            if Self.defaultScopeStopTags.contains(element) { return nil }
        }
        return nil
    }

    /// `indexOfOpenElement`: a plain search of the open stack. The table scopes stop at `html` and
    /// the table itself, which is the anchor the port already cuts to, so no stop tag can be
    /// reached above the match inside a table.
    private func indexOfOpenElement(_ name: String) -> Int? {
        open.lastIndex(where: { $0.name == name })
    }

    private func indexOfTableBody() -> Int? {
        open.lastIndex(where: { $0.name == "tbody" || $0.name == "thead" || $0.name == "tfoot" })
    }

    private func elementNamed(_ name: String) -> HTMLNode? {
        open.last(where: { $0.name == name })
    }

    /// The scopes the port answers with: `defaultScope` has no stop tags of its own, `buttonScope`
    /// stops at `button`, `listItemScope` stops at `ol` and `ul`. The table scopes are the anchors
    /// `clearStackToContext` uses, and the ancestor loop that could use `listItemScope` for a start
    /// tag is part of the subset boundary; the scope is still what `</li>` answers with.
    private enum ElementScope {
        case defaultScope, buttonScope, listItemScope

        var ownStopTags: Set<String> {
            switch self {
            case .defaultScope: return []
            case .buttonScope: return ["button"]
            case .listItemScope: return ["ol", "ul"]
            }
        }
    }

    /// The stop tags `defaultScopeStopTags` holds for the HTML namespace.
    static let defaultScopeStopTags: Set<String> = [
        "applet", "caption", "html", "table", "td", "th", "marquee", "object", "template", "select",
    ]
}
