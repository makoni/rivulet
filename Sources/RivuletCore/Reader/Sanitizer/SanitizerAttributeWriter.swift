// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (`sanitizeAttributes`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// The attributes an element is written with, the rule `sanitizeAttributes` implements.
///
/// An attribute that is not in the tag's allowlist is read and dropped. A value that holds a URL is
/// resolved through the URL layer and checked against the scheme allowlist, and the tracking
/// parameters are removed from it when it has a query. The attributes the sanitizer adds come after
/// the ones it kept, in the reference's order.
struct SanitizerAttributeWriter {
    /// What the reference answers with for one attribute: keep it, skip it, or refuse the element.
    enum Decision: Equatable {
        case keep(String)
        case skip
        case refuseElement
    }

    private(set) var out = ""
    private var mandatory = MandatoryAttributes()
    private var isAnchorLink = false
    private var isYouTubeEmbed = false

    /// Reads every attribute, then the ones the sanitizer adds. The answer is the reference's
    /// second return value: the point where the caller decides what happens to the element's
    /// content.
    mutating func read(tag: String, attributes: [HTMLAttribute], base: ParsedURL?,
        options: SanitizerOptions) -> Bool {
        let allowed = SanitizerAllowlists.attributes(for: tag)

        for attribute in attributes {
            guard allowed.contains(attribute.name) else { continue }

            switch decide(tag: tag, name: attribute.name, value: attribute.value, base: base,
                options: options) {
            case .skip:
                continue
            case .refuseElement:
                return false
            case .keep(let value):
                mandatory.track(attribute.name)
                write(key: attribute.name, value: value)
            }
        }

        guard mandatory.isComplete(for: tag) else { return false }

        if !isAnchorLink { appendAddedAttributes(for: tag, options: options) }
        return true
    }

    private mutating func decide(tag: String, name: String, value: String, base: ParsedURL?,
        options: SanitizerOptions) -> Decision {
        let validated = validate(tag: tag, name: name, value: value, base: base)
        if validated == .skip { return .skip }
        guard SanitizerRules.isExternalResourceAttribute(name) else { return validated }

        if tag == "iframe" {
            let domain = URLRules.domainWithoutWWW(value)
            guard SanitizerAllowlists.isAllowedIFrameDomain(domain, options: options) else {
                return .refuseElement
            }
            if domain == "youtube.com" || domain == "youtube-nocookie.com" { isYouTubeEmbed = true }
            return .keep(rewriteIframeURL(value, options: options))
        }

        if tag == "img" && name == "src" && SanitizerAllowlists.isValidDataAttribute(value) {
            return .keep(value)
        }

        if tag == "a" && name == "href" && value.hasPrefix("#") {
            isAnchorLink = true
            return .keep(value)
        }

        if SanitizerAllowlists.isBlockedResource(value) { return .refuseElement }

        guard let absolute = try? URLResolution.resolveToAbsolute(parsedBase: base, relative: value),
            URISchemeAllowlist.hasValidScheme(absolute) else { return .skip }

        // The reference runs the cleaner only when there is a query to clean, which is the common
        // case for an image.
        if absolute.contains("?") {
            if let parsed = try? ParsedURL.parse(absolute),
                let cleaned = try? TrackingParameters.remove(base: base, feed: base, input: parsed) {
                return .keep(cleaned)
            }
        }
        return .keep(absolute)
    }

    /// The per-tag validators, the rules the reference runs before the URL branch. A value that
    /// fails one is not written.
    private func validate(tag: String, name: String, value: String, base: ParsedURL?) -> Decision {
        switch tag {
        case "math" where name == "xmlns":
            return .keep("http://www.w3.org/1998/Math/MathML")
        case "img":
            if name == "fetchpriority" && !SanitizerRules.isValidFetchPriorityValue(value) { return .skip }
            if name == "decoding" && !SanitizerRules.isValidDecodingValue(value) { return .skip }
            if (name == "width" || name == "height") && !SanitizerRules.isPositiveInteger(value) {
                return .skip
            }
            if name == "srcset" {
                let sanitized = SrcSetParser.sanitized(base: base, value: value)
                return sanitized.isEmpty ? .skip : .keep(sanitized)
            }
        case "source" where name == "srcset":
            let sanitized = SrcSetParser.sanitized(base: base, value: value)
            return sanitized.isEmpty ? .skip : .keep(sanitized)
        default:
            break
        }

        return .keep(value)
    }

    /// The rewrite the reference applies to an allowed iframe source: the embed prefix for YouTube,
    /// the do-not-track parameter for the Vimeo player.
    private func rewriteIframeURL(_ link: String, options: SanitizerOptions) -> String {
        guard let parsed = try? ParsedURL.parse(link) else { return link }

        let domain = parsed.hostName.hasPrefix("www.") ? String(parsed.hostName.dropFirst(4)) : parsed.hostName
        switch domain {
        case "youtube.com":
            guard parsed.path.hasPrefix("/embed/") else { return link }
            let embedPath = String(parsed.path.dropFirst("/embed/".count))
            guard !parsed.rawQuery.isEmpty else { return options.youTubeEmbedURLPrefix + embedPath }
            return options.youTubeEmbedURLPrefix + embedPath + "?" + parsed.rawQuery
        case "player.vimeo.com":
            guard parsed.path.hasPrefix("/video/") else { return link }
            return link + (parsed.rawQuery.isEmpty ? "?dnt=1" : "&dnt=1")
        default:
            return link
        }
    }

    private mutating func appendAddedAttributes(for tag: String, options: SanitizerOptions) {
        switch tag {
        case "a":
            write(key: "rel", value: "noopener noreferrer")
            write(key: "referrerpolicy", value: "no-referrer")
            if options.openLinksInNewTab { write(key: "target", value: "_blank") }
        case "video", "audio":
            writeFlag("controls")
        case "iframe":
            write(key: "sandbox",
                value: "allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox")
            write(key: "loading", value: "lazy")
            // The reference writes it for a YouTube embed, which is where the player configuration
            // error the referrerpolicy avoids comes from.
            if isYouTubeEmbed { write(key: "referrerpolicy", value: "strict-origin-when-cross-origin") }
        case "img":
            write(key: "loading", value: "lazy")
        default:
            break
        }
    }

    private mutating func write(key: String, value: String) {
        if !out.isEmpty { out += " " }
        out += key + "=\"" + HTMLEscape.escapeString(value) + "\""
    }

    private mutating func writeFlag(_ flag: String) {
        if !out.isEmpty { out += " " }
        out += flag
    }
}
