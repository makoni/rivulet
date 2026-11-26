// Ported from Miniflux internal/model/category.go's two request shapes and the rules
// `encoding/json` answers for them (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The document a request body carries, read for the shapes this path declares.
///
/// `Decode` reads the top-level value and stops at its end, so the bytes after it are not read, and a
/// field the shape does not declare is not read either. The type check is what decides whether a
/// document fails: a value that is not the type the field declares is the reference's
/// `UnmarshalTypeError`. The two shapes differ only in what a missing field or a `null` answers — the
/// zero value for a plain field, nothing for a pointer.
public enum RequestBody {
    /// The rules the read fails on, named as this port names them. The reference answers the text its
    /// decoder builds from the position it failed at, which `docs/parity.md` records.
    public enum Rule: String, Error, Sendable {
        /// The input ended with a value still open, or had no value at all.
        case unexpectedEnd

        /// A byte the position the machine is in cannot accept.
        case unexpectedCharacter

        /// A value that is not the type the field it is assigned to declares.
        case unmarshalTypeError

        /// A value nested deeper than the depth the machine limits to.
        case maxDepthExceeded
    }

    /// `model.CategoryCreationRequest`: two plain fields, so a document that does not carry one leaves
    /// it at its zero value.
    public struct CategoryCreation: Sendable {
        /// The title the request carries, or the empty value when it does not.
        public var title = ""

        /// The hide flag the request carries, or the false value when it does not.
        public var hideGlobally = false

        /// A request with nothing read from it.
        public init() {}
    }

    /// `model.CategoryModificationRequest`: two pointer fields, so a document that does not carry one,
    /// or carries `null`, answers nothing for it.
    public struct CategoryModification: Sendable {
        /// The title the request carries, or nothing when it does not.
        public var title: String?

        /// The hide flag the request carries, or nothing when it does not.
        public var hideGlobally: Bool?

        /// A request with nothing read from it.
        public init() {}
    }

    /// Reads `model.CategoryCreationRequest`: the fields the document carries, each rule the read
    /// fails on thrown as the name the reference's error carries.
    public static func categoryCreation(_ text: String) throws -> CategoryCreation {
        let fields = try fields(for: text)
        var request = CategoryCreation()
        switch fields["title"] {
        case .string(let value): request.title = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["hide_globally"] {
        case .boolean(let value): request.hideGlobally = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        return request
    }

    /// Reads `model.CategoryModificationRequest`, the same fields as pointers, so a document that
    /// carries `null` answers nothing for the field.
    public static func categoryModification(_ text: String) throws -> CategoryModification {
        let fields = try fields(for: text)
        var request = CategoryModification()
        switch fields["title"] {
        case .string(let value): request.title = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["hide_globally"] {
        case .boolean(let value): request.hideGlobally = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        return request
    }

    /// `model.FeedCreationRequest`: the four fields this port has columns for, all plain, so a document
    /// that does not carry one leaves it at its zero value. The reference's struct declares more fields
    /// — the filter rules, the scraper settings, the proxy — which this port has no columns for, and the
    /// pins do not read them.
    public struct FeedCreation: Sendable {
        /// The url the request carries, or the empty value when it does not.
        public var feedURL = ""

        /// The url the request carries, or the empty value when it does not.
        public var siteURL = ""

        /// The title the request carries, or the empty value when it does not.
        public var title = ""

        /// The category the request carries, or the zero value when it does not, which is the value
        /// the create path resolves to the first row by title.
        public var categoryID = 0

        /// A request with nothing read from it.
        public init() {}
    }

    /// `model.FeedModificationRequest`: the same four fields as pointers, so a document that does not
    /// carry one, or carries `null`, answers nothing for it — which is what makes the modification path
    /// patch rather than overwrite.
    public struct FeedModification: Sendable {
        /// The url the request carries, or nothing when it does not.
        public var feedURL: String?

        /// The url the request carries, or nothing when it does not.
        public var siteURL: String?

        /// The title the request carries, or nothing when it does not.
        public var title: String?

        /// The category the request carries, or nothing when it does not.
        public var categoryID: Int?

        /// A request with nothing read from it.
        public init() {}
    }

    /// Reads `model.FeedCreationRequest`: the fields the document carries, each rule the read fails
    /// on thrown as the name the reference's error carries.
    public static func feedCreation(_ text: String) throws -> FeedCreation {
        let fields = try fields(for: text)
        var request = FeedCreation()
        switch fields["feed_url"] {
        case .string(let value): request.feedURL = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["site_url"] {
        case .string(let value): request.siteURL = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["title"] {
        case .string(let value): request.title = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["category_id"] {
        case .integer(let value): request.categoryID = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        return request
    }

    public static func feedModification(_ text: String) throws -> FeedModification {
        let fields = try fields(for: text)
        var request = FeedModification()
        switch fields["feed_url"] {
        case .string(let value): request.feedURL = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["site_url"] {
        case .string(let value): request.siteURL = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["title"] {
        case .string(let value): request.title = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["category_id"] {
        case .integer(let value): request.categoryID = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        return request
    }

    /// `model.EntriesStatusUpdateRequest`: the list and the two fields. `Starred` is a pointer, so a
    /// document that does not carry it, or carries `null`, answers nothing for it — which is what lets
    /// the write path write only the half the request carried.
    public struct EntriesStatusUpdate: Sendable {
        /// The ids the request carries; a document that does not carry the field, or carries `null`,
        /// answers the empty list.
        public var entryIDs: [Int] = []

        /// The status the request carries, or the empty value when it does not.
        public var status = ""

        /// The flag the request carries, or nothing when it does not.
        public var starred: Bool?

        /// A request with nothing read from it.
        public init() {}
    }

    /// Reads `model.EntriesStatusUpdateRequest`: the fields the document carries, each rule the read
    /// fails on thrown as the name the reference's error carries.
    public static func entriesStatusUpdate(_ text: String) throws -> EntriesStatusUpdate {
        let fields = try fields(for: text)
        var request = EntriesStatusUpdate()
        switch fields["entry_ids"] {
        case .integers(let values): request.entryIDs = values
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["status"] {
        case .string(let value): request.status = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        switch fields["starred"] {
        case .boolean(let value): request.starred = value
        case .unmarshalTypeError: throw Rule.unmarshalTypeError
        default: break
        }
        return request
    }

    /// The fields the shapes declare, read as the machine read them. A field of the wrong type is
    /// recorded as the failure rather than as a value, so the shape that reads it answers it.
    private static func fields(for text: String) throws -> [String: Field] {
        let document: JSONValue
        do {
            document = try JSONReader.read(Data(text.utf8))
        } catch let error as JSONError {
            throw rule(for: error)
        }
        guard case .object(let members) = document else { throw Rule.unmarshalTypeError }

        var fields: [String: Field] = [:]
        for member in members {
            switch member.key {
            case "title":
                switch member.value {
                case .string(let value): fields[member.key] = .string(value)
                case .null: fields[member.key] = .null
                default: fields[member.key] = .unmarshalTypeError
                }
            case "hide_globally":
                switch member.value {
                case .boolean(let value): fields[member.key] = .boolean(value)
                case .null: fields[member.key] = .null
                default: fields[member.key] = .unmarshalTypeError
                }
            case "feed_url", "site_url":
                switch member.value {
                case .string(let value): fields[member.key] = .string(value)
                case .null: fields[member.key] = .null
                default: fields[member.key] = .unmarshalTypeError
                }
            case "category_id":
                switch member.value {
                // The reader keeps a number as the literal it read, so the conversion to the target type
                // is the shape's own: a literal the int64 target cannot take is the same failure the
                // reference's decoder answers for a value of the wrong type.
                case .number(let text):
                    fields[member.key] = Int(text).map(Field.integer) ?? .unmarshalTypeError
                case .null: fields[member.key] = .null
                default: fields[member.key] = .unmarshalTypeError
                }
            case "entry_ids":
                // The reference's decoder reads the slice element by element: a document that carries
                // `null` answers nothing for the field, and an element the int64 target cannot take is
                // the same failure the decoder reports for a value of the wrong type.
                switch member.value {
                case .array(let values):
                    var ids: [Int] = []
                    var failed = false
                    for value in values {
                        switch value {
                        case .number(let text):
                            guard let id = Int(text) else { failed = true; break }
                            ids.append(id)
                        default: failed = true
                        }
                    }
                    fields[member.key] = failed ? .unmarshalTypeError : .integers(ids)
                case .null: fields[member.key] = .null
                default: fields[member.key] = .unmarshalTypeError
                }
            case "status":
                switch member.value {
                case .string(let value): fields[member.key] = .string(value)
                case .null: fields[member.key] = .null
                default: fields[member.key] = .unmarshalTypeError
                }
            case "starred":
                switch member.value {
                case .boolean(let value): fields[member.key] = .boolean(value)
                case .null: fields[member.key] = .null
                default: fields[member.key] = .unmarshalTypeError
                }
            default:
                break
            }
        }
        return fields
    }

    private enum Field {
        case string(String)
        case boolean(Bool)
        case integer(Int)
        case integers([Int])
        case null
        case unmarshalTypeError
    }

    /// The rule the machine's failure is named as by this path.
    static func rule(for error: JSONError) -> Rule {
        switch error {
        case .unexpectedEnd: return .unexpectedEnd
        case .unexpectedCharacter: return .unexpectedCharacter
        case .unmarshalTypeError: return .unmarshalTypeError
        case .maxDepthExceeded: return .maxDepthExceeded
        }
    }
}
