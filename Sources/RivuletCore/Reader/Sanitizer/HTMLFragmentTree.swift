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
/// the implied `tbody` and `tr` inside one, the end tags that pop the table modes, the two end-tag
/// rules that put a node on the tree with nothing in it, and the depth limit the reference refuses.
///
/// Where the subset stops, recorded in `docs/parity.md`: foster parenting, the active formatting
/// elements, the adoption agency, the caption and column-group modes, nested tables and the scope
/// markers. No case in the reference corpus changes what the sanitizer writes because of them, so
/// the tree is built as if the insertion point were the open element, which is what the modes
/// answer with for the tags in the corpus.
///
/// Comment nodes are not kept, because the renderer answers with nothing for them.
final class HTMLFragmentTree {
    /// The open-element limit `insertOpenElement` enforces, reported as a parse failure once the
    /// stack passes it. `html` and `body` count in the stack, which is what the reference's depth
    /// test pins.
    static let maxOpenElements = 512

    /// The start tags that close an open `p`, the list `inBodyIM` pops `buttonScope, p` for.
    /// `button` is not in it, which is why the list is not the HTML5 block set.
    static let pClosingTags: Set<String> = [
        "address", "article", "aside", "blockquote", "center", "dd", "details", "dialog", "dir", "div",
        "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "header", "h1", "h2", "h3",
        "h4", "h5", "h6", "hgroup", "hr", "li", "listing", "main", "menu", "nav", "ol", "p", "plaintext",
        "pre", "search", "section", "summary", "table", "ul",
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
    private var finished = false

    init(_ tokenizer: HTMLTokenizer) {
        self.tokenizer = tokenizer
    }

    /// Builds the tree and answers with the `body` element the sanitizer renders, which is the node
    /// the reference walks through.
    func build() throws -> HTMLNode {
        let html = try insertElement(name: "html", attributes: [])
        html.appendChild(HTMLNode(kind: .element, name: "head"))

        while !finished, let token = tokenizer.next() {
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

        if HTMLFragmentTree.pClosingTags.contains(name) { cut(to: "p") }
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
        // The table-only start tags are ignored inside a cell: a cell cannot hold another cell.
        case .cell: break
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
            // The element is popped only when one of the three bodies is open, and the token is
            // then read again in the table mode.
            guard let position = index(of: name) else { return }
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
        // `body` does not pop anything: only the insertion mode changes, so what follows is still
        // added to it. `html` ends the parse outside a table, and is ignored inside one.
        if mode == .body {
            if name == "body" { return }
            if name == "html" {
                finished = true
                return
            }
        } else {
            if name == "html" || name == "body" { return }
            return processEndTagInTable(name)
        }

        if name == "p" {
            // An end tag for p when no p is open inserts an empty one, then closes it.
            if elementNamed("p") == nil { try insertElement(name: "p", attributes: []) }
            cut(to: "p")
            return
        }

        // The end tag for br is read as a start tag.
        if name == "br" {
            try processStartTag(HTMLToken(kind: .startTag, name: "br"))
            return
        }

        guard elementNamed(name) != nil else { return }
        cut(to: name)
    }

    /// The end tags the table modes pop, which is `clearStackToContext` and then one element. The
    /// other end tags are ignored inside a table.
    private func processEndTagInTable(_ name: String) {
        guard HTMLFragmentTree.tableOnlyTags.contains(name) else { return }
        guard let position = index(of: name) else { return }
        open.removeSubrange(position...)

        switch name {
        case "table": mode = .body
        case "tbody", "thead", "tfoot": mode = .table
        case "tr": mode = .tableBody
        case "td", "th": mode = .row
        default: break
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
        // NUL is removed from a text token by the insertion mode, which is the one place the
        // reference does not read it as U+FFFD.
        var cleaned = value.replacingOccurrences(of: "\u{00}", with: "")
        if cleaned.isEmpty { return }

        let parent = open.last ?? root
        if (parent.name == "pre" || parent.name == "listing") && parent.firstChild == nil {
            // A newline at the start of a pre block is ignored.
            if cleaned.hasPrefix("\r") || cleaned.hasPrefix("\n") {
                cleaned = String(cleaned.dropFirst())
                if cleaned.isEmpty { return }
            }
        }

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

    /// The open element is cut to `p`, which is what `popUntil(buttonScope, p)` answers with when
    /// the p is in the scope, and does nothing when it is not.
    private func cut(to name: String) {
        guard let position = index(of: name) else { return }
        open.removeSubrange(position...)
    }

    private func index(of name: String) -> Int? {
        open.lastIndex(where: { $0.name == name })
    }

    private func elementNamed(_ name: String) -> HTMLNode? {
        open.last(where: { $0.name == name })
    }
}
