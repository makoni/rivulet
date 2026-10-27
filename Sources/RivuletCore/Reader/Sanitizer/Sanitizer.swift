// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (`SanitizeHTML` and `filterAndRenderHTML`)
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The HTML sanitizer: it reads the input through the tokenizer subset and the fragment tree, and
/// writes the allowed tags and attributes the way the reference builds its output string.
///
/// The output is built here rather than by rendering a parsed tree, because the reference does the
/// same: it writes the element name and the attributes it decided to keep itself, so attribute
/// order, name lowercasing and entity decoding are the tokenizer's and this writer's, not a
/// library's. The rules for which tags and attributes survive are in `SanitizerAllowlists` and
/// `SanitizerAttributeWriter`.
enum Sanitizer {
    static func sanitize(baseURL: String, rawHTML: String, options: SanitizerOptions) -> String {
        // The input is wrapped in body tags so the fragment builder sees a document, which is what
        // the reference does before it parses.
        let input = "<body>" + rawHTML + "</body>"

        let body: HTMLNode
        do {
            body = try HTMLFragmentTree(HTMLTokenizer(input)).build()
        } catch {
            return ""
        }

        let base = try? ParsedURL.parse(baseURL)
        var out = ""
        for child in body.children {
            render(&out, node: child, base: base, options: options)
        }
        return out
    }

    private static func render(_ out: inout String, node: HTMLNode, base: ParsedURL?,
        options: SanitizerOptions) {
        switch node.kind {
        case .document:
            // The reference keeps a comment node in the tree and writes nothing for it, which is
            // why the builder does not record comments at all.
            return
        case .text:
            out += HTMLEscape.escapeString(node.text)
        case .element:
            renderElement(&out, node: node, base: base, options: options)
        }
    }

    private static func renderElement(_ out: inout String, node: HTMLNode, base: ParsedURL?,
        options: SanitizerOptions) {
        let tag = node.name
        if shouldIgnoreTag(node: node, tag: tag) { return }

        guard SanitizerAllowlists.isAllowedTag(tag) else {
            // The tag is not allowed, but its content still is.
            renderChildren(&out, node: node, base: base, options: options)
            return
        }

        var writer = SanitizerAttributeWriter()
        guard writer.read(tag: tag, attributes: node.attributes, base: base, options: options) else {
            if tag == "iframe" {
                // A blocked iframe does not render its content.
                return
            }
            renderChildren(&out, node: node, base: base, options: options)
            return
        }

        out += "<" + tag
        if !writer.out.isEmpty { out += " " + writer.out }
        out += ">"

        if SanitizerRules.isSelfContainedTag(tag) { return }
        // An iframe is not allowed to have child nodes.
        if tag != "iframe" { renderChildren(&out, node: node, base: base, options: options) }
        out += "</" + tag + ">"
    }

    private static func renderChildren(_ out: inout String, node: HTMLNode, base: ParsedURL?,
        options: SanitizerOptions) {
        for child in node.children {
            render(&out, node: child, base: base, options: options)
        }
    }

    private static func shouldIgnoreTag(node: HTMLNode, tag: String) -> Bool {
        if SanitizerRules.isPixelTracker(tag, attributes: node.attributes) { return true }
        if SanitizerRules.isBlockedTag(tag) { return true }
        return SanitizerRules.isHidden(node)
    }
}
