// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/json/json.go (Apache-2.0); adapted for Swift/SQLite.
// The rules are the ones `encoding/json` answers for a struct field, so `JSONScanner` names the
// source they are traced against.

import Foundation

/// The shapes `json.go` declares, filled by the walk `d.object` does over the members the tree
/// keeps.
///
/// The reference has no code for this layer, because it decodes a feed straight into these structs,
/// so the rules here are `decode.go`'s: a value is read against the type the field is, which is
/// where `UnmarshalTypeError` comes from; `null` sets a collection to empty but leaves a string, an
/// int64 or a struct field as it started; and a key the document writes twice stays the two members
/// the tree kept, so the last assignment the field's type accepts is the value the shape holds.
///
/// The field table is the fields the adapter reads. A value whose type does not match a field the
/// adapter does not read is a failure in the reference and nothing here, which `docs/parity.md`
/// records, as does the case-insensitive name match `foldName` does.
enum JSONFieldRead {
    /// The fields the feed-level adapter reads.
    struct Feed {
        var title = ""
        var feedURL = ""
        var homePageURL = ""
        var description = ""
        var language = ""
        var iconURL = ""
        var faviconURL = ""
        var authors: [Author] = []
        var author = Author()
        var items: [Item] = []
    }

    /// The fields the entry-level adapter reads.
    struct Item {
        var id = ""
        var url = ""
        var externalURL = ""
        var title = ""
        var contentHTML = ""
        var contentText = ""
        var summary = ""
        var datePublished = ""
        var dateModified = ""
        var language = ""
        var authors: [Author] = []
        var author = Author()
        var tags: [String] = []
        var attachments: [Attachment] = []
    }

    /// `JSONAuthor`, of which the adapter uses the name.
    struct Author {
        var name = ""
    }

    /// `JSONAttachment`, of which the adapter uses the URL, the type and the size.
    struct Attachment {
        var url = ""
        var mimeType = ""
        var size = 0
    }

    /// The shape `Decode` fills from the tree, which is what `Parse` does before it builds the
    /// model.
    static func read(_ data: Data) throws -> Feed {
        try feed(try JSONReader.read(data))
    }

    // MARK: - The walk, one production per `decode.go` function

    /// `d.object` for `JSONFeed`: the members in the order the document wrote them, so the failure
    /// is the first member the field's type cannot accept rather than the first field the adapter
    /// reads, because `saveError` keeps the first failure and the walk descends into a value when
    /// it reaches it.
    static func feed(_ tree: JSONValue) throws -> Feed {
        guard case let .object(members) = tree else {
            if case .null = tree { return Feed() }
            throw JSONError.unmarshalTypeError(value: word(tree), target: "json.JSONFeed")
        }

        var document = Feed()
        for member in members {
            switch member.key {
            case "title": try assign(member.value, to: &document.title, target: "string")
            case "feed_url": try assign(member.value, to: &document.feedURL, target: "string")
            case "home_page_url": try assign(member.value, to: &document.homePageURL, target: "string")
            case "description": try assign(member.value, to: &document.description, target: "string")
            case "language": try assign(member.value, to: &document.language, target: "string")
            case "icon": try assign(member.value, to: &document.iconURL, target: "string")
            case "favicon": try assign(member.value, to: &document.faviconURL, target: "string")
            case "authors": document.authors = authors(member.value)
            case "author": try assignAuthor(member.value, to: &document.author)
            case "items": document.items = try items(member.value)
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
            case "date_published": try assign(member.value, to: &entry.datePublished, target: "string")
            case "date_modified": try assign(member.value, to: &entry.dateModified, target: "string")
            case "language": try assign(member.value, to: &entry.language, target: "string")
            case "authors": entry.authors = authors(member.value)
            case "author": try assignAuthor(member.value, to: &entry.author)
            case "tags": entry.tags = try strings(member.value)
            case "attachments": entry.attachments = try attachments(member.value)
            default: break
            }
        }
        return entry
    }

    /// `d.object` for `JSONAuthor`. The reference reads an author's website and avatar into its
    /// struct and writes nothing with them, so the shape keeps the name alone.
    static func author(_ members: [JSONMember]) throws -> Author {
        var person = Author()
        for member in members {
            if member.key == "name" { try assign(member.value, to: &person.name, target: "string") }
        }
        return person
    }

    /// `d.object` for `JSONAttachment`. The size is an `int64` field, so the number is converted
    /// through `ParseInt` rather than kept as the literal the machine read.
    static func attachment(_ members: [JSONMember]) throws -> Attachment {
        var enclosure = Attachment()
        for member in members {
            switch member.key {
            case "url": try assign(member.value, to: &enclosure.url, target: "string")
            case "mime_type": try assign(member.value, to: &enclosure.mimeType, target: "string")
            case "size_in_bytes": try size(member.value, to: &enclosure.size)
            default: break
            }
        }
        return enclosure
    }

    // MARK: - The leniency `json.go` adds

    /// `JSONAuthors.UnmarshalJSON`: the array is tried first, then a single object, and a value
    /// that is neither is ignored silently, so a bad element fails the whole attempt rather than
    /// that element.
    private static func authors(_ value: JSONValue) -> [Author] {
        switch value {
        case let .array(values):
            var people: [Author] = []
            for element in values {
                switch element {
                case let .object(members):
                    guard let person = try? author(members) else { return [] }
                    people.append(person)
                case .null: people.append(Author())
                default: return []
                }
            }
            return people
        case let .object(members):
            return (try? author(members)).map { [$0] } ?? []
        default:
            return []
        }
    }

    // MARK: - Reading one value against the type the field is

    /// `literalStore` for a string field.
    private static func assign(_ value: JSONValue, to field: inout String, target: String) throws {
        switch value {
        case let .string(text): field = text
        case .null: break     // "otherwise, ignore null for primitives/string"
        default: throw JSONError.unmarshalTypeError(value: word(value), target: target)
        }
    }

    /// `literalStore` for a struct field, which has no leniency: only an object is read, and null
    /// leaves the field as it started, which is what a repeated key separates here.
    private static func assignAuthor(_ value: JSONValue, to field: inout Author) throws {
        switch value {
        case let .object(members): field = try author(members)
        case .null: break
        default: throw JSONError.unmarshalTypeError(value: word(value), target: "json.JSONAuthor")
        }
    }

    /// `literalStore` for an int64 field, where a number the conversion cannot read is reported
    /// with the literal as the value.
    private static func size(_ value: JSONValue, to field: inout Int) throws {
        switch value {
        case let .number(text):
            guard let parsed = Int(text) else {
                throw JSONError.unmarshalTypeError(value: "number " + text, target: "int64")
            }
            field = parsed
        case .null: break
        default: throw JSONError.unmarshalTypeError(value: word(value), target: "int64")
        }
    }

    /// `d.array` for a slice field: null sets the collection, which is why an earlier assignment is
    /// cleared, and `d.value` reads each element against the element type. A null element is
    /// ignored for that element, so it stays as it started.
    private static func strings(_ value: JSONValue) throws -> [String] {
        switch value {
        case .null: return []
        case let .array(values):
            var names: [String] = []
            for element in values {
                var name = ""
                try assign(element, to: &name, target: "string")
                names.append(name)
            }
            return names
        default: throw JSONError.unmarshalTypeError(value: word(value), target: "[]string")
        }
    }

    private static func items(_ value: JSONValue) throws -> [Item] {
        switch value {
        case .null: return []
        case let .array(values):
            var entries: [Item] = []
            for element in values {
                switch element {
                case let .object(members): entries.append(try item(members))
                case .null: entries.append(Item())
                default: throw JSONError.unmarshalTypeError(value: word(element), target: "json.JSONItem")
                }
            }
            return entries
        default: throw JSONError.unmarshalTypeError(value: word(value), target: "[]json.JSONItem")
        }
    }

    private static func attachments(_ value: JSONValue) throws -> [Attachment] {
        switch value {
        case .null: return []
        case let .array(values):
            var enclosures: [Attachment] = []
            for element in values {
                switch element {
                case let .object(members): enclosures.append(try attachment(members))
                case .null: enclosures.append(Attachment())
                default: throw JSONError.unmarshalTypeError(value: word(element),
                    target: "json.JSONAttachment")
                }
            }
            return enclosures
        default: throw JSONError.unmarshalTypeError(value: word(value), target: "[]json.JSONAttachment")
        }
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
