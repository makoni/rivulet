// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/opml/parser.go (`parse`, `getSubscriptionsFromOutlines`)
// (Apache-2.0); adapted for Swift/SQLite: the read walks the tree the tolerant reader builds rather
// than a value layer, so the shape rules are the field matches the model names and the value rules
// are ``OPMLReadRules``.

import Foundation

/// Reads an OPML document into the records the format defines.
enum OPMLParser {
    /// Reads the document and answers the records, in document order.
    ///
    /// - Throws: ``OPMLError`` for the shape, the attribute set and the read failure.
    static func parse(_ data: Data) throws -> [OPMLSubscription] {
        let root: XMLElement
        do {
            root = try XMLReader.read(data)
        } catch let error as XMLError {
            throw OPMLError.documentNotReadable(error)
        }

        // The model names `opml` as its root, which `encoding/xml` checks even in non-strict mode.
        guard root.name.local == "opml" else { throw OPMLError.rootShape(rootLocal: root.name.local) }

        // The field reads `body>outline`: an outline at any other level is not read.
        guard let body = root.child(local: "body") else { return [] }
        return try collect(outlines: body.children, category: "")
    }

    /// One attribute as the read holds it: the value as written for a name the parse rule does not
    /// read, and the value as the parse rule reads it for a bool name.
    private struct ReadField: Sendable {
        let name: String
        let text: String
        let flag: Bool
    }

    private static func collect(outlines: [XMLElement], category: String) throws
        -> [OPMLSubscription] {
        var subscriptions: [OPMLSubscription] = []
        for outline in outlines {
            // The reference reads the miniflux attributes as it decodes every outline, not only the
            // ones the branch answers as a record, so the parse rule runs for every outline that
            // carries one, and an outline that is not a record can still report it.
            let fields = try readFields(of: outline)

            if OPMLReadRules.isSubscription(feedURL: value(of: outline, local: "xmlUrl")) {
                subscriptions.append(record(of: outline, category: category, fields: fields))
            } else if !outline.children.isEmpty {
                // The branch the reference takes for a parent: the category is the parent's title,
                // read through the same chain the record title uses.
                subscriptions.append(contentsOf: try collect(outlines: outline.children,
                    category: OPMLReadRules.title(title: value(of: outline, local: "title"),
                        text: value(of: outline, local: "text"),
                        siteURL: value(of: outline, local: "htmlUrl"),
                        feedURL: value(of: outline, local: "xmlUrl"))))
            }
        }
        return subscriptions
    }

    private static func readFields(of outline: XMLElement) throws -> [ReadField] {
        var fields: [ReadField] = []
        for attribute in outline.attributes {
            // The reference compares the resolved namespace, not the prefix as written, and the set
            // of names, so a name outside it is not read.
            guard attribute.name.namespace == OPMLReadRules.minifluxNamespace,
                OPMLReadRules.isMinifluxName(attribute.name.local) else { continue }

            let isBool = OPMLReadRules.isBoolName(attribute.name.local)
            fields.append(ReadField(name: attribute.name.local, text: attribute.value,
                flag: isBool ? try OPMLReadRules.boolValue(name: attribute.name.local,
                    value: attribute.value) : false))
        }
        return fields
    }

    private static func record(of outline: XMLElement, category: String, fields: [ReadField])
        -> OPMLSubscription {
        var subscription = OPMLSubscription()
        subscription.feedURL = value(of: outline, local: "xmlUrl")
        subscription.title = OPMLReadRules.title(title: value(of: outline, local: "title"),
            text: value(of: outline, local: "text"),
            siteURL: value(of: outline, local: "htmlUrl"), feedURL: subscription.feedURL)
        subscription.siteURL = OPMLReadRules.siteURL(siteURL: value(of: outline, local: "htmlUrl"),
            feedURL: subscription.feedURL)
        subscription.description = value(of: outline, local: "description")
        subscription.categoryName = category

        for field in fields { apply(field, to: &subscription) }
        return subscription
    }

    /// The switch the reference reads the name set through: a string field takes the value as the
    /// attribute holds it, and a bool field takes the value as the parse rule read it.
    private static func apply(_ field: ReadField, to subscription: inout OPMLSubscription) {
        switch field.name {
        case "scraperRules": subscription.scraperRules = field.text
        case "rewriteRules": subscription.rewriteRules = field.text
        case "urlRewriteRules": subscription.urlRewriteRules = field.text
        case "blocklistRules": subscription.blocklistRules = field.text
        case "keeplistRules": subscription.keeplistRules = field.text
        case "blockFilterEntryRules": subscription.blockFilterEntryRules = field.text
        case "keepFilterEntryRules": subscription.keepFilterEntryRules = field.text
        case "userAgent": subscription.userAgent = field.text
        case "crawler": subscription.crawler = field.flag
        case "ignoreHTTPCache": subscription.ignoreHTTPCache = field.flag
        case "fetchViaProxy": subscription.fetchViaProxy = field.flag
        case "disabled": subscription.disabled = field.flag
        case "noMediaPlayer": subscription.noMediaPlayer = field.flag
        case "hideGlobally": subscription.hideGlobally = field.flag
        case "allowSelfSignedCertificates": subscription.allowSelfSignedCertificates = field.flag
        case "disableHTTP2": subscription.disableHTTP2 = field.flag
        case "ignoreEntryUpdates": subscription.ignoreEntryUpdates = field.flag
        default: break // The guard in `readFields` reads the set; nothing outside it reaches here.
        }
    }

    /// A field of the model, matched on the local name alone, as `encoding/xml` matches a field
    /// whose tag names no namespace.
    private static func value(of outline: XMLElement, local: String) -> String {
        outline.attribute(local: local) ?? ""
    }
}
