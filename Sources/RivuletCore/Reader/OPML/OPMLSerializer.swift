// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/opml/serializer.go (Apache-2.0); adapted for Swift/SQLite.
// The reference writes through `encoding/xml`'s encoder; this file reproduces the bytes that
// encoder answers for this model, rule by rule, as read from the reference at commit `c4d54f87`.

import Foundation

/// The OPML write: the bytes the reference's encoder answers for the document shape.
enum OPMLSerializer {
    /// The header line as the constant `encoding/xml` carries at the pinned toolchain, read as the
    /// serializer writes it; the newline before the root line is the element-layout rule.
    static let headerLine = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"

    /// The indent the encoder is configured with.
    static let indentUnit = "    "

    /// The three constants the build rule sets, and the zone the port answers.
    static let buildVersion = "2.0"
    static let buildNamespace = "https://miniflux.app/opml"
    static let buildHeaderTitle = "Miniflux"
    static let portZoneName = "UTC"

    /// Writes the document, applying the build rule to the records and the zone rule to the date.
    static func serialize(_ subscriptions: [OPMLSubscription], now: Date) -> String {
        serialize(OPMLDocumentShape(version: buildVersion, namespace: buildNamespace,
            headerTitle: buildHeaderTitle, dateCreated: dateField(now),
            groups: groups(from: subscriptions)), zoneName: portZoneName)
    }

    /// Writes a shape as it stands: the head fields are written when the shape carries them, the
    /// version is written whatever it holds, and the categories are written in the byte order.
    static func serialize(_ shape: OPMLDocumentShape, zoneName: String = portZoneName) -> String {
        // The root is written at column 0 and the document ends at the root close with no trailing
        // newline; the newline before the root line comes from the element-layout rule, not from
        // the header constant.
        let rootAttributes = attr(name: "version", value: shape.version, alwaysWritten: true)
            + attr(name: "xmlns:miniflux", value: shape.namespace, alwaysWritten: false)
        return headerLine
            + block(depth: 0, name: "opml", attributes: rootAttributes,
                children: headAndBody(shape, zoneName: zoneName))
    }

    /// One element with its children, as the encoder lays them out: the close tag goes to the same
    /// line as the open tag only when the element wrote nothing; otherwise it goes to its own line
    /// at the element's own indent.
    private static func block(depth: Int, name: String, attributes: String, children: String) -> String {
        let open = "\n" + line(depth) + "<" + name + attributes + ">"
        return children.isEmpty ? open + "</" + name + ">"
            : open + children + "\n" + line(depth) + "</" + name + ">"
    }

    private static func headAndBody(_ shape: OPMLDocumentShape, zoneName: String) -> String {
        let headChildren = headField("title", shape.headerTitle, depth: 2)
            + headField("dateCreated", shape.dateCreated, depth: 2)
            + headField("ownerName", shape.ownerName, depth: 2)
        return block(depth: 1, name: "head", attributes: "", children: headChildren)
            + block(depth: 1, name: "body", attributes: "", children: bodyChildren(shape))
    }

    /// The grouping rule orders the categories as bytes; inside one category the records keep the
    /// order they arrived in.
    private static func bodyChildren(_ shape: OPMLDocumentShape) -> String {
        var out = ""
        for group in sortedGroups(shape.groups) {
            // The category outline is not a subscription: its `text` is the name, and the writer
            // answers the empty value for its type.
            let children = group.subscriptions.map { record in
                block(depth: 3, name: "outline", attributes: outlineAttributes(OutlineValue(
                    title: record.title, text: record.title, subscription: record)), children: "")
            }.joined()
            out += block(depth: 2, name: "outline", attributes: outlineAttributes(
                OutlineValue(text: group.name)), children: children)
        }
        return out
    }

    /// The order the encoder writes the fields of an outline: the format fields, then the miniflux
    /// names in the order the model declares them, then `type`, which the outline writer adds after
    /// all of them and answers the empty value for a category outline.
    private static let fieldOrder: [(name: String, alwaysWritten: Bool)] = [
        ("title", false), ("text", true), ("xmlUrl", false), ("htmlUrl", false),
        ("description", false),
        ("miniflux:scraperRules", false), ("miniflux:rewriteRules", false),
        ("miniflux:urlRewriteRules", false), ("miniflux:blocklistRules", false),
        ("miniflux:keeplistRules", false), ("miniflux:blockFilterEntryRules", false),
        ("miniflux:keepFilterEntryRules", false), ("miniflux:userAgent", false),
        ("miniflux:crawler", false), ("miniflux:ignoreHTTPCache", false),
        ("miniflux:fetchViaProxy", false), ("miniflux:disabled", false),
        ("miniflux:noMediaPlayer", false), ("miniflux:hideGlobally", false),
        ("miniflux:allowSelfSignedCertificates", false), ("miniflux:disableHTTP2", false),
        ("miniflux:ignoreEntryUpdates", false), ("type", false),
    ]

    /// One outline as the build holds it: only a subscription carries the settings and the type.
    private struct OutlineValue {
        var title: String = ""
        var text: String
        var subscription: OPMLSubscription?
    }

    private static func outlineAttributes(_ value: OutlineValue) -> String {
        fieldOrder.reduce("") { out, field in
            let written = fieldValue(field.name, value)
            return written.isEmpty && !field.alwaysWritten ? out
                : out + " " + field.name + "=\"" + escape(written) + "\""
        }
    }

    private static func fieldValue(_ field: String, _ value: OutlineValue) -> String {
        let record = value.subscription
        switch field {
        case "title": return value.title
        case "text": return value.text
        case "type": return record != nil ? "rss" : ""
        default: return setting(field, record)
        }
    }

    private static func setting(_ field: String, _ record: OPMLSubscription?) -> String {
        guard let record else { return "" }
        switch field {
        case "xmlUrl": return record.feedURL
        case "htmlUrl": return record.siteURL
        case "description": return record.description
        case "miniflux:scraperRules": return record.scraperRules
        case "miniflux:rewriteRules": return record.rewriteRules
        case "miniflux:urlRewriteRules": return record.urlRewriteRules
        case "miniflux:blocklistRules": return record.blocklistRules
        case "miniflux:keeplistRules": return record.keeplistRules
        case "miniflux:blockFilterEntryRules": return record.blockFilterEntryRules
        case "miniflux:keepFilterEntryRules": return record.keepFilterEntryRules
        case "miniflux:userAgent": return record.userAgent
        case "miniflux:crawler": return record.crawler ? "true" : ""
        case "miniflux:ignoreHTTPCache": return record.ignoreHTTPCache ? "true" : ""
        case "miniflux:fetchViaProxy": return record.fetchViaProxy ? "true" : ""
        case "miniflux:disabled": return record.disabled ? "true" : ""
        case "miniflux:noMediaPlayer": return record.noMediaPlayer ? "true" : ""
        case "miniflux:hideGlobally": return record.hideGlobally ? "true" : ""
        case "miniflux:allowSelfSignedCertificates": return record.allowSelfSignedCertificates ? "true" : ""
        case "miniflux:disableHTTP2": return record.disableHTTP2 ? "true" : ""
        case "miniflux:ignoreEntryUpdates": return record.ignoreEntryUpdates ? "true" : ""
        default: return ""
        }
    }

    /// The grouping rule: one group per category name, keeping the order the records arrived in
    /// inside each.
    private static func groups(from records: [OPMLSubscription]) -> [OPMLGroup] {
        var groups: [OPMLGroup] = []
        for record in records {
            if let index = groups.firstIndex(where: { $0.name == record.categoryName }) {
                groups[index].subscriptions.append(record)
            } else {
                groups.append(OPMLGroup(name: record.categoryName, subscriptions: [record]))
            }
        }
        return groups
    }

    private static func sortedGroups(_ groups: [OPMLGroup]) -> [OPMLGroup] {
        groups.sorted { first, second in first.name < second.name }
    }

    private static func headField(_ name: String, _ value: String, depth: Int) -> String {
        value.isEmpty ? ""
            : "\n" + line(depth) + "<" + name + ">" + escape(value) + "</" + name + ">"
    }

    /// The escape set `EscapeString` applies to a value and to a string field's character data
    /// alike: the five markup characters, the tab, the newline and the carriage return as named
    /// references, and a scalar outside the character range as the replacement character, which is
    /// what makes the newline round-trip. The reference's other escape path, `EscapeText`, reads
    /// the same set with the newline left as written, and this path never goes through it.
    static func escape(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "&#34;"
            case "'": out += "&#39;"
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\t": out += "&#x9;"
            case "\n": out += "&#xA;"
            case "\r": out += "&#xD;"
            default: out += inCharacterRange(scalar) ? String(scalar) : "\u{FFFD}"
            }
        }
        return out
    }

    /// `isInCharacterRange`: the three the switch names, the ranges the function lists, and nothing
    /// else, so a control character outside those three answers the replacement character.
    private static func inCharacterRange(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
            || scalar.value >= 0x20 && scalar.value <= 0xD7FF
            || scalar.value >= 0xE000 && scalar.value <= 0xFFFD
            || scalar.value >= 0x10000 && scalar.value <= 0x10FFFF
    }

    private static func attr(name: String, value: String, alwaysWritten: Bool) -> String {
        value.isEmpty && !alwaysWritten ? "" : " " + name + "=\"" + escape(value) + "\""
    }

    private static func line(_ depth: Int) -> String {
        String(repeating: indentUnit, count: depth)
    }

    /// The format the reference reads its layout through, applied to the time given, read against
    /// UTC, with the zone name the port answers.
    static func dateField(_ date: Date, zoneName: String = portZoneName) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second],
            from: date)
        let weekday = weekdayNames[(parts.weekday ?? 1) - 1]
        let month = monthNames[(parts.month ?? 1) - 1]
        return String(format: "%@, %02d %@ %04d %02d:%02d:%02d %@", weekday, parts.day ?? 0, month,
            parts.year ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, zoneName)
    }

    private static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
        "Oct", "Nov", "Dec"]
}
