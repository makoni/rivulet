// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/json/json.go (Apache-2.0); adapted
// for Swift/SQLite. The rules are the ones `encoding/json` answers for a
// struct field, so `JSONScanner` names the source they are traced against.

import Foundation

/// The shapes `json.go` declares, filled by the walk `d.object` does over the tree's members.
///
/// The reference has no code for this layer, because it decodes a feed straight into
/// these structs, so the rules here are `decode.go`'s: a value is read against the
/// type the field is, which is where `UnmarshalTypeError` comes from; `null` sets a
/// collection to empty but leaves a string, a bool, an `int64` or a struct field as
/// it started; and a key the document writes twice stays the two members the tree
/// kept, so the last assignment the field's type accepts is the value the shape holds.
///
/// The shape keeps every field the struct declares, not only the ones the adapter
/// writes, because the type check is what decides whether a document fails — and for
/// `authors` it is what decides whether the leniency keeps the whole array or none of
/// it. The values the adapter never writes to the model are kept for that reason alone.
enum JSONFieldRead {
    /// The fields `JSONFeed` declares. The adapter writes the model from the title, the two
    /// URLs, the description, the language, the icon, the favicon, the authors and the items.
    struct Feed {
        var version = ""
        var title = ""
        var homePageURL = ""
        var feedURL = ""
        var description = ""
        var iconURL = ""
        var faviconURL = ""
        var authors: [Author] = []
        var author = Author()
        var language = ""
        var expired = false
        var items: [Item] = []
        var hubs: [Hub] = []
    }

    /// The fields `JSONItem` declares. The adapter writes the model from
    /// the id, the two URLs, the title, the three content fields, the two
    /// dates, the language, the authors, the tags and the attachments.
    struct Item {
        var id = ""
        var url = ""
        var externalURL = ""
        var title = ""
        var contentHTML = ""
        var contentText = ""
        var summary = ""
        var imageURL = ""
        var bannerImageURL = ""
        var datePublished = ""
        var dateModified = ""
        var language = ""
        var authors: [Author] = []
        var author = Author()
        var tags: [String] = []
        var attachments: [Attachment] = []
    }

    /// The fields `JSONAuthor` declares, of which the adapter uses the name.
    struct Author {
        var name = ""
        var websiteURL = ""
        var avatarURL = ""
    }

    /// The fields `JSONAttachment` declares, of which the adapter uses the URL, the type
    /// and the size. The size is `int64` here, because that is the target `ParseInt`
    /// reads through; the model keeps `Int`, which is 64 bits on the platforms
    /// this project targets, so a value the conversion accepted converts exactly.
    struct Attachment {
        var url = ""
        var mimeType = ""
        var title = ""
        var size: Int64 = 0
        var duration: Int = 0
    }

    /// The fields `JSONHub` declares, which the adapter reads no further than the type check.
    struct Hub {
        var type = ""
        var url = ""
    }

    /// The shape `Decode` fills from the tree, which
    /// is what `Parse` does before it builds the model.
    static func read(_ data: Data) throws -> Feed {
        try feed(try JSONReader.read(data))
    }

    // MARK: - The walk, one production per `decode.go` function

    /// `d.object` for `JSONFeed`, with the fields in the order `json.go` declares them. The
    /// walk visits the members in the order the document wrote them, so the failure is the
    /// first member the field's type cannot accept, not the first field the table has, because
    /// `saveError` keeps the first failure and the walk descends into a value when it reaches it.
    static func feed(_ tree: JSONValue) throws -> Feed {
        guard case let .object(members) = tree else {
            if case .null = tree { return Feed() }
            throw JSONError.unmarshalTypeError(value: word(tree), target: "json.JSONFeed")
        }

        var document = Feed()
        for member in members {
            switch member.key {
            case "version": try assign(member.value, to: &document.version, target: "string")
            case "title": try assign(member.value, to: &document.title, target: "string")
            case "home_page_url": try assign(member.value, to: &document.homePageURL, target: "string")
            case "feed_url": try assign(member.value, to: &document.feedURL, target: "string")
            case "description": try assign(member.value, to: &document.description, target: "string")
            case "icon": try assign(member.value, to: &document.iconURL, target: "string")
            case "favicon": try assign(member.value, to: &document.faviconURL, target: "string")
            case "authors": authors(member.value, to: &document.authors)
            case "author": try assignAuthor(member.value, to: &document.author)
            case "language": try assign(member.value, to: &document.language, target: "string")
            case "expired": try assign(member.value, to: &document.expired, target: "bool")
            case "items": document.items = try collection(member.value, target: "[]json.JSONItem",
                fill: itemElement)
            case "hubs": document.hubs = try collection(member.value, target: "[]json.JSONHub",
                fill: hubElement)
            default: break
            }
        }
        return document
    }

    /// `d.object` for `JSONItem`.
    static func item(_ members: [JSONMember]) throws -> Item {
        var entry = Item()
        for member in members {
            switch member.key {
            case "id": try assign(member.value, to: &entry.id, target: "string")
            case "url": try assign(member.value, to: &entry.url, target: "string")
            case "external_url": try assign(member.value, to: &entry.externalURL, target: "string")
            case "title": try assign(member.value, to: &entry.title, target: "string")
            case "content_html": try assign(member.value, to: &entry.contentHTML, target: "string")
            case "content_text": try assign(member.value, to: &entry.contentText, target: "string")
            case "summary": try assign(member.value, to: &entry.summary, target: "string")
            case "image": try assign(member.value, to: &entry.imageURL, target: "string")
            case "banner_image": try assign(member.value, to: &entry.bannerImageURL, target: "string")
            case "date_published": try assign(member.value, to: &entry.datePublished, target: "string")
            case "date_modified": try assign(member.value, to: &entry.dateModified, target: "string")
            case "language": try assign(member.value, to: &entry.language, target: "string")
            case "authors": authors(member.value, to: &entry.authors)
            case "author": try assignAuthor(member.value, to: &entry.author)
            case "tags": entry.tags = try collection(member.value, target: "[]string",
                fill: stringElement)
            case "attachments": entry.attachments = try collection(member.value,
                target: "[]json.JSONAttachment", fill: attachmentElement)
            default: break
            }
        }
        return entry
    }

    /// `d.object` for `JSONAuthor`. The website and the avatar are read because the type check
    /// is what decides whether the document fails, and the adapter writes nothing with them.
    static func author(_ members: [JSONMember]) throws -> Author {
        var person = Author()
        for member in members {
            switch member.key {
            case "name": try assign(member.value, to: &person.name, target: "string")
            case "url": try assign(member.value, to: &person.websiteURL, target: "string")
            case "avatar": try assign(member.value, to: &person.avatarURL, target: "string")
            default: break
            }
        }
        return person
    }

    /// `d.object` for `JSONAttachment`. The size is an `int64` field, so the number is
    /// converted through `ParseInt` rather than kept as the literal the machine read.
    static func attachment(_ members: [JSONMember]) throws -> Attachment {
        var enclosure = Attachment()
        for member in members {
            switch member.key {
            case "url": try assign(member.value, to: &enclosure.url, target: "string")
            case "mime_type": try assign(member.value, to: &enclosure.mimeType, target: "string")
            case "title": try assign(member.value, to: &enclosure.title, target: "string")
            case "size_in_bytes": try assign(member.value, to: &enclosure.size, target: "int64")
            case "duration_in_seconds": try assign(member.value, to: &enclosure.duration,
                target: "int")
            default: break
            }
        }
        return enclosure
    }

    /// `d.object` for `JSONHub`.
    static func hub(_ members: [JSONMember]) throws -> Hub {
        var endpoint = Hub()
        for member in members {
            switch member.key {
            case "type": try assign(member.value, to: &endpoint.type, target: "string")
            case "url": try assign(member.value, to: &endpoint.url, target: "string")
            default: break
            }
        }
        return endpoint
    }

    // MARK: - The leniency `json.go` adds

    /// `JSONAuthors.UnmarshalJSON`: the array is tried first, then a single
    /// object, and a value neither branch can read is ignored silently — the
    /// method returns without assigning, so the field keeps what it had, which is
    /// what a repeated key separates here. A bad element fails the whole attempt
    /// rather than that element, because the array branch is one `Unmarshal` call.
    private static func authors(_ value: JSONValue, to field: inout [Author]) {
        switch value {
        case .null:
            // The array branch reads null as `SetZero`, so this is an assignment, not an ignore.
            field = []
        case let .array(values):
            var people: [Author] = []
            for element in values {
                guard let person = try? authorElement(element) else { return }
                people.append(person)
            }
            field = people
        case let .object(members):
            guard let person = try? author(members) else { return }
            field = [person]
        default:
            return
        }
    }

    // MARK: - Reading one value against the type the field is

    /// `literalStore` for a string, a bool or a number field. A number is converted per target, so
    /// the word the reference reports for a value `ParseInt` cannot read is the literal as read.
    private static func assign<T: FixedWidthInteger>(_ value: JSONValue, to field: inout T,
        target: String) throws {
        switch value {
        case let .number(text):
            guard let parsed = T(text) else {
                throw JSONError.unmarshalTypeError(value: "number " + text, target: target)
            }
            field = parsed
        case .null: break     // "otherwise, ignore null for primitives/string"
        default: throw JSONError.unmarshalTypeError(value: word(value), target: target)
        }
    }

    private static func assign(_ value: JSONValue, to field: inout String, target: String) throws {
        switch value {
        case let .string(text): field = text
        case .null: break     // "otherwise, ignore null for primitives/string"
        default: throw JSONError.unmarshalTypeError(value: word(value), target: target)
        }
    }

    private static func assign(_ value: JSONValue, to field: inout Bool, target: String) throws {
        switch value {
        case let .boolean(flag): field = flag
        case .null: break     // "otherwise, ignore null for primitives/string"
        default: throw JSONError.unmarshalTypeError(value: word(value), target: target)
        }
    }

    /// `literalStore` for a struct field, which has no leniency: only an object is read,
    /// and null leaves the field as it started, which is what a repeated key separates here.
    private static func assignAuthor(_ value: JSONValue, to field: inout Author) throws {
        switch value {
        case let .object(members): field = try author(members)
        case .null: break
        default: throw JSONError.unmarshalTypeError(value: word(value), target: "json.JSONAuthor")
        }
    }

    /// `d.array` for a slice field: `null` sets the collection, which is why an earlier assignment
    /// is cleared, and `d.value` reads each element against the element type, so an element that
    /// is not the type is the failure. A null element is ignored, so it stays as it started.
    private static func collection<T>(_ value: JSONValue, target: String,
        fill: (JSONValue) throws -> T) throws -> [T] {
        switch value {
        case .null: return []
        case let .array(values):
            var kept: [T] = []
            for element in values { kept.append(try fill(element)) }
            return kept
        default: throw JSONError.unmarshalTypeError(value: word(value), target: target)
        }
    }

    private static func stringElement(_ value: JSONValue) throws -> String {
        var name = ""
        try assign(value, to: &name, target: "string")
        return name
    }

    private static func authorElement(_ value: JSONValue) throws -> Author {
        var person = Author()
        try assignAuthor(value, to: &person)
        return person
    }

    private static func itemElement(_ value: JSONValue) throws -> Item {
        guard case let .object(members) = value else {
            if case .null = value { return Item() }
            throw JSONError.unmarshalTypeError(value: word(value), target: "json.JSONItem")
        }
        return try item(members)
    }

    private static func attachmentElement(_ value: JSONValue) throws -> Attachment {
        guard case let .object(members) = value else {
            if case .null = value { return Attachment() }
            throw JSONError.unmarshalTypeError(value: word(value), target: "json.JSONAttachment")
        }
        return try attachment(members)
    }

    private static func hubElement(_ value: JSONValue) throws -> Hub {
        guard case let .object(members) = value else {
            if case .null = value { return Hub() }
            throw JSONError.unmarshalTypeError(value: word(value), target: "json.JSONHub")
        }
        return try hub(members)
    }

    /// The word Go names the value with in `UnmarshalTypeError`: the kind the literal is.
    private static func word(_ value: JSONValue) -> String {
        switch value {
        case .number: return "number"
        case .boolean: return "bool"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        case .null: return "null"
        }
    }
}
